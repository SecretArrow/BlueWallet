import { CAPABILITIES, ERROR_CODES } from './protocol.mjs';
import { OctraWalletError } from './errors.mjs';
import { fromMicroOCT, isValidAddress, resolveAmount } from './units.mjs';
import { InjectedTransport } from './transports.mjs';

/**
 * OctraWalletAdapter — dApp-side adapter for BlueWallet/Octra wallets.
 *
 * Amounts are exact decimal STRINGS everywhere in this API (never floats);
 * raw micro-OCT passes through untouched. The wallet always approves
 * state-changing calls in its own UI — this adapter never signs locally.
 */
export class OctraWalletAdapter {
  /**
   * @param {object} [opts]
   * @param {string} [opts.appName]
   * @param {Array} [opts.transports] - tried in order; defaults to injected
   * @param {number} [opts.timeoutMs] - per-request ceiling (default 120000)
   */
  constructor(opts = {}) {
    this.appName = opts.appName ?? 'Octra dApp';
    this.timeoutMs = opts.timeoutMs ?? 120000;
    this.transports = opts.transports ?? [new InjectedTransport()];
    this.transport = null;
    this.address = null;
    this.permissions = [];
    this.listeners = new Map();
  }

  // ── lifecycle ──────────────────────────────────────────────────────

  /** Pick the first available transport. False when none is usable. */
  async initialize() {
    for (const t of this.transports) {
      try {
        // eslint-disable-next-line no-await-in-loop
        if (await t.available()) {
          this.transport = t;
          return true;
        }
      } catch {
        // try next transport — never fail loudly here
      }
    }
    this.transport = null;
    return false;
  }

  isReady() {
    return this.transport !== null;
  }

  _requireTransport() {
    if (!this.transport) {
      throw new OctraWalletError(
        ERROR_CODES.DISCONNECTED,
        'Adapter not initialized — call initialize() first',
      );
    }
    return this.transport;
  }

  _requireConnected() {
    this._requireTransport();
    if (!this.address) {
      throw new OctraWalletError(
        ERROR_CODES.NOT_CONNECTED,
        'Not connected — call connect() first',
      );
    }
    return this.address;
  }

  /**
   * Connect (wallet approval UI). Requested permissions are recorded and
   * echoed back: this wallet approves all-or-nothing in its dialog.
   */
  async connect(permissions = ['accounts']) {
    const t = this._requireTransport();
    const requested = Array.isArray(permissions) ? [...permissions] : [];
    let address;
    if (typeof t.connectRaw === 'function') {
      const res = await this._withTimeout(t.connectRaw());
      address = res && (res.address || (Array.isArray(res) && res[0]));
    } else {
      const accounts = await this._withTimeout(
        t.request('octra_requestAccounts', []),
      );
      address = Array.isArray(accounts) ? accounts[0] : accounts?.address;
    }
    if (!address || !isValidAddress(address)) {
      throw new OctraWalletError(
        ERROR_CODES.UNAUTHORIZED,
        'Connect did not yield a valid address',
      );
    }
    this.address = address;
    this.permissions = requested;
    this._emit('connect', { address, permissions: requested });
    return { address, permissions: requested };
  }

  async disconnect() {
    const addr = this.address;
    this.address = null;
    this.permissions = [];
    this._emit('disconnect', { reason: 'user_action', address: addr });
  }

  isConnected() {
    return this.transport !== null && this.address !== null;
  }

  getAddress() {
    return this.address;
  }

  // ── reads ──────────────────────────────────────────────────────────

  /**
   * Balances as exact decimal strings (+ raw micro-OCT passthrough).
   * Private value is null unless the wallet reports it.
   */
  async getBalance() {
    this._requireConnected();
    const t = this._requireTransport();
    const res = await this._withTimeout(t.request('octra_getBalance', []));
    // Injected path answers a JSON-RPC envelope; localhost answers a body.
    const r = unwrapRpc(res) ?? {};
    const raw = r.balance_raw ?? r.raw ?? null;
    const encRaw = r.encrypted_raw ?? r.encryptedRaw ?? null;
    const pub = r.balance ?? (raw != null ? fromMicroOCT(raw) : null);
    const priv = r.encryptedBalance ?? (encRaw != null ? fromMicroOCT(encRaw) : null);
    return {
      public: pub,
      private: priv,
      total: pub != null && priv != null ? addOct(pub, priv) : (pub ?? priv),
      raw,
      encryptedRaw: encRaw,
      currency: 'OCT',
    };
  }

  /** PVAC cipher bundle for the connected wallet (may need a refresh first). */
  async getEncryptedBalance() {
    this._requireConnected();
    const t = this._requireTransport();
    return this._withTimeout(t.request('octra_getEncryptedBalance', []));
  }

  /** Read-only contract view. No unlock, no approval. */
  async contractView({ contract, method, params = [], caller } = {}) {
    this._requireTransport();
    if (!contract || !method) {
      throw new OctraWalletError(ERROR_CODES.INVALID_PARAMS, 'contractView needs contract + method');
    }
    const t = this._requireTransport();
    return this._withTimeout(
      t.request('octra_callView', [contract, method, params, caller ?? this.address ?? '']),
    );
  }

  // ── writes (always wallet-approved) ────────────────────────────────

  /**
   * Standard transfer. Exactly one of amount/amountOct. Returns {hash}.
   * Throws INVALID_ADDRESS / INVALID_AMOUNT before touching the wallet.
   */
  async sendTransaction({ to, amount, amountOct, message } = {}) {
    this._requireConnected();
    to = typeof to === 'string' ? to.trim() : to;
    if (!isValidAddress(to)) {
      throw new OctraWalletError(ERROR_CODES.INVALID_ADDRESS, `Invalid recipient address: ${to}`);
    }
    const micro = resolveAmount({ amount, amountOct });
    if (micro === '0') {
      throw new OctraWalletError(ERROR_CODES.INVALID_AMOUNT, 'Amount must be greater than 0');
    }
    const t = this._requireTransport();
    const res = await this._withTimeout(
      t.request('octra_sendTransaction', [{ to, amount: micro, ...(message !== undefined ? { message } : {}) }]),
    );
    const hash = res?.hash ?? res?.tx_hash ?? res?.txHash;
    if (!hash) {
      throw new OctraWalletError(ERROR_CODES.TRANSACTION_FAILED, 'Send returned no transaction hash');
    }
    return { hash };
  }

  /**
   * State-changing contract call (flat params, like AML). Approval UI on
   * the wallet. OU is wallet-decided (fee oracle) and intentionally not
   * a parameter. Returns {txHash|hash}.
   */
  async callContract({ contract, method, params = [], amount, amountOct } = {}) {
    this._requireConnected();
    contract = typeof contract === 'string' ? contract.trim() : contract;
    if (!isValidAddress(contract)) {
      throw new OctraWalletError(ERROR_CODES.INVALID_ADDRESS, `Invalid contract address: ${contract}`);
    }
    if (!method) {
      throw new OctraWalletError(ERROR_CODES.INVALID_PARAMS, 'callContract needs a method');
    }
    if (!Array.isArray(params)) {
      throw new OctraWalletError(ERROR_CODES.INVALID_PARAMS, 'callContract params must be an array');
    }
    const micro =
      amount === undefined && amountOct === undefined
        ? '0' // attach nothing by default (wallet default)
        : resolveAmount({ amount, amountOct });
    const t = this._requireTransport();
    // Localhost transport routes approval-gated calls explicitly.
    if (t.name === 'localhost' && typeof t.callContractViaApproval === 'function') {
      const res = await this._withTimeout(
        t.callContractViaApproval({ address: contract, method, params, amount: micro }),
      );
      return { txHash: res?.tx_hash ?? res?.txHash, raw: res };
    }
    const res = await this._withTimeout(
      t.request('octra_callContract', [contract, method, params, micro]),
    );
    return { txHash: res?.txHash ?? res?.tx_hash ?? res?.hash, raw: res };
  }

  // ── events ─────────────────────────────────────────────────────────

  on(event, cb) {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set());
    this.listeners.get(event).add(cb);
    return this;
  }

  off(event, cb) {
    if (cb) this.listeners.get(event)?.delete(cb);
    else this.listeners.delete(event);
    return this;
  }

  _emit(event, data) {
    for (const cb of this.listeners.get(event) ?? []) {
      try {
        cb(data);
      } catch {
        // A listener must never break the adapter.
      }
    }
  }

  async _withTimeout(promise) {
    let timer;
    try {
      return await Promise.race([
        promise,
        new Promise((_, reject) => {
          timer = setTimeout(
            () => reject(new OctraWalletError(ERROR_CODES.NETWORK_UNAVAILABLE, 'Request timed out')),
            this.timeoutMs,
          );
        }),
      ]);
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  }
}

/** Exact OCT decimal addition on strings (no floats). */
function addOct(a, b) {
  const toMicro = (s) => {
    const [w = '0', f = ''] = String(s).split('.');
    return BigInt(w || '0') * 1000000n + BigInt((f + '000000').slice(0, 6));
  };
  const total = toMicro(a) + toMicro(b);
  const whole = total / 1000000n;
  const frac = (total % 1000000n).toString().padStart(6, '0').replace(/0+$/, '');
  return frac === '' ? whole.toString() : `${whole}.${frac}`;
}

/**
 * Unwrap a JSON-RPC envelope ({jsonrpc, result, id}) to its result.
 * Bodies without the envelope marker pass through untouched, so localhost
 * bodies like {result, value} keep working for field readers.
 */
export function unwrapRpc(res) {
  if (
    res &&
    typeof res === 'object' &&
    !Array.isArray(res) &&
    'jsonrpc' in res &&
    'result' in res
  ) {
    return res.result;
  }
  return res;
}

/**
 * Run fn(); on HTTP 401, ask for a token once via promptFn and retry a
 * single time. promptFn(reason) resolves the token string or null;
 * applyToken(token) installs it (e.g. transport.setToken). Non-401
 * errors pass through untouched.
 */
export async function withAuthRetry(fn, promptFn, applyToken) {
  try {
    return await fn();
  } catch (e) {
    const unauthorized =
      !!e && (e.status === 401 || /401|unauthorized/i.test(e.message || ''));
    if (!unauthorized || typeof promptFn !== 'function') throw e;
    const t = await promptFn(
      'Local server wants a Bearer token (Local Web Server settings in the wallet app).',
    );
    if (!t) throw e;
    if (typeof applyToken === 'function') {
      await applyToken(t);
    }
    return await fn();
  }
}
