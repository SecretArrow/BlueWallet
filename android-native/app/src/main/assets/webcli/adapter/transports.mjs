import { ERROR_CODES } from './protocol.mjs';
import { OctraWalletError } from './errors.mjs';

/**
 * Transport interface (duck-typed): any object with
 *   - `name: string`
 *   - `request(wireMethod: string, params?: unknown): Promise<unknown>`
 * Transports never throw bare values — always Error instances.
 */

/** Default localhost gateway (BlueWallet apps + webcli). */
export const DEFAULT_LOCAL_URL = 'http://127.0.0.1:8420';

function asError(e, fallbackCode) {
  if (e instanceof OctraWalletError) return e;
  const msg = e instanceof Error ? e.message : String(e);
  return new OctraWalletError(fallbackCode, msg);
}

/**
 * In-page transport: talks to an injected `window.octra` provider
 * (BlueWallet in-app browsers, or any RFC-O-1 wallet).
 */
export class InjectedTransport {
  name = 'injected';

  /** @param {object} [provider] - defaults to globalThis.window.octra */
  constructor(provider) {
    this.provider =
      provider ?? (typeof globalThis.window !== 'undefined'
        ? globalThis.window.octra
        : undefined);
  }

  available() {
    return !!this.provider && typeof this.provider.request === 'function';
  }

  _require() {
    if (!this.available()) {
      throw new OctraWalletError(
        ERROR_CODES.DISCONNECTED,
        'No injected octra provider found',
      );
    }
    return this.provider;
  }

  async request(wireMethod, params = []) {
    const provider = this._require();
    try {
      return await provider.request({ method: wireMethod, params });
    } catch (e) {
      throw asError(e, ERROR_CODES.NETWORK_UNAVAILABLE);
    }
  }

  /** Raw connect passthrough (approval UI lives in the wallet). */
  async connectRaw() {
    const provider = this._require();
    if (typeof provider.connect !== 'function') {
      throw new OctraWalletError(
        ERROR_CODES.UNSUPPORTED_METHOD,
        'Injected provider has no connect()',
      );
    }
    try {
      return await provider.connect();
    } catch (e) {
      throw asError(e, ERROR_CODES.USER_REJECTED);
    }
  }
}

/**
 * Localhost HTTP transport: talks to a BlueWallet app / webcli local
 * server (`/api/*`). Reads + approval-gated contract calls only —
 * plain sends are deliberately NOT exposed over HTTP (auto-sign risk),
 * so `sendTransaction` throws on this transport by design.
 */
export class LocalhostTransport {
  name = 'localhost';

  /**
   * @param {object} [opts]
   * @param {string} [opts.baseUrl] - e.g. http://127.0.0.1:8420
   * @param {string} [opts.token] - Bearer token from Local Web Server settings
   * @param {function} [opts.fetchImpl] - fetch override (tests)
   * @param {number} [opts.timeoutMs]
   */
  constructor(opts = {}) {
    this.baseUrl = (opts.baseUrl ?? DEFAULT_LOCAL_URL).replace(/\/+$/, '');
    this.token = opts.token ?? '';
    this.fetchImpl =
      opts.fetchImpl ??
      (typeof globalThis.fetch !== 'undefined' ? globalThis.fetch.bind(globalThis) : undefined);
    this.timeoutMs = opts.timeoutMs ?? 30000;
  }

  /** Update the Bearer token (e.g. after a 401 re-prompt). */
  setToken(token) {
    this.token = token ?? '';
  }

  _headers(json = false) {
    const h = {};
    if (this.token) h['Authorization'] = `Bearer ${this.token}`;
    if (json) h['Content-Type'] = 'application/json';
    return h;
  }

  async _fetch(path, { method = 'GET', body } = {}) {
    if (!this.fetchImpl) {
      throw new OctraWalletError(
        ERROR_CODES.NETWORK_UNAVAILABLE,
        'No fetch implementation available',
      );
    }
    const ctrl =
      typeof AbortController !== 'undefined' ? new AbortController() : null;
    const timer =
      ctrl != null
        ? setTimeout(() => ctrl.abort(), this.timeoutMs)
        : null;
    try {
      const res = await this.fetchImpl(`${this.baseUrl}${path}`, {
        method,
        headers: this._headers(body !== undefined),
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: ctrl?.signal,
      });
      let data = null;
      try {
        data = await res.json();
      } catch {
        throw new OctraWalletError(
          ERROR_CODES.NETWORK_UNAVAILABLE,
          `Local server returned non-JSON (HTTP ${res.status})`,
        );
      }
      if (!res.ok) {
        const msg =
          data && typeof data.error === 'string'
            ? data.error
            : `Local server HTTP ${res.status}`;
        const err = new OctraWalletError(ERROR_CODES.NETWORK_UNAVAILABLE, msg);
        err.status = res.status;
        throw err;
      }
      if (data && typeof data.error === 'string') {
        throw new OctraWalletError(ERROR_CODES.INVALID_PARAMS, data.error);
      }
      return data;
    } catch (e) {
      if (e instanceof OctraWalletError) throw e;
      const aborted =
        (e && e.name === 'AbortError') || String(e).includes('aborted');
      throw new OctraWalletError(
        ERROR_CODES.NETWORK_UNAVAILABLE,
        aborted ? `Local server timed out (${path})` : `Local server unreachable (${path}): ${e instanceof Error ? e.message : String(e)}`,
      );
    } finally {
      if (timer != null) clearTimeout(timer);
    }
  }

  /** Liveness probe: public /api/status needs no token. */
  async available() {
    if (!this.fetchImpl) return false;
    try {
      await this._fetch('/api/status');
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Raw connect: proof of tokened access via authed /api/wallet/info.
   * Used by OctraWalletAdapter.connect() on this transport.
   */
  async connectRaw() {
    const info = await this._fetch('/api/wallet/info');
    const address = info && (info.address || info.wallet_address);
    if (!address) {
      throw new OctraWalletError(
        ERROR_CODES.UNAUTHORIZED,
        'Local server wallet info has no address (is a wallet loaded?)',
      );
    }
    return { address };
  }

  /**
   * Localhost has no single generic RPC: map the small supported set.
   * Anything else throws unsupported (explicit, never silent).
   */
  async request(wireMethod, params = []) {
    switch (wireMethod) {
      case 'octra_getBalance':
        return this._fetch('/api/balance');
      case 'octra_callView': {
        const [address, method, args = [], caller] = params;
        if (!address || !method) {
          throw new OctraWalletError(
            ERROR_CODES.INVALID_PARAMS,
            'contractView needs [address, method, params?]',
          );
        }
        const q = new URLSearchParams({
          address: String(address),
          method: String(method),
          params: JSON.stringify(args),
          ...(caller ? { caller: String(caller) } : {}),
        });
        return this._fetch(`/api/contract/view?${q.toString()}`);
      }
      case 'octra_callContract':
      case 'octra_sendTransaction':
        throw new OctraWalletError(
          ERROR_CODES.UNSUPPORTED_METHOD,
          `${wireMethod} over plain HTTP would auto-sign: use the approval-gated /api/contract/call explicitly via callContract()`,
        );
      default:
        throw new OctraWalletError(
          ERROR_CODES.UNSUPPORTED_METHOD,
          `Localhost transport does not serve ${wireMethod}`,
        );
    }
  }

  /** Approval-gated contract call (device shows the confirm UI). */
  async callContractViaApproval({ address, method, params = [], amount = '0', ou = '1000' }) {
    if (!address || !method) {
      throw new OctraWalletError(
        ERROR_CODES.INVALID_PARAMS,
        'callContract needs address + method',
      );
    }
    return this._fetch('/api/contract/call', {
      method: 'POST',
      body: { address, method, params, amount, ou },
    });
  }
}
