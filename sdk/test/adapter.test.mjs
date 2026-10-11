import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { ERROR_CODES } from '../src/protocol.mjs';
import { OctraWalletError } from '../src/errors.mjs';
import { OctraWalletAdapter } from '../src/adapter.mjs';
import { LocalhostTransport } from '../src/transports.mjs';

const ADDR = 'oct' + '1'.repeat(44);
const OTHER = 'oct' + '2'.repeat(44);

/** In-memory transport double: scripted wire responses + call log. */
function fakeTransport(responses = {}) {
  const calls = [];
  return {
    name: 'fake',
    calls,
    available: async () => true,
    async request(method, params) {
      calls.push({ method, params });
      if (!(method in responses)) {
        throw new OctraWalletError(ERROR_CODES.UNSUPPORTED_METHOD, `no script for ${method}`);
      }
      const r = responses[method];
      if (r instanceof Error) throw r;
      return typeof r === 'function' ? r(params) : r;
    },
  };
}

function adapterWith(responses, opts = {}) {
  return new OctraWalletAdapter({
    transports: [fakeTransport(responses)],
    ...opts,
  });
}

describe('lifecycle', () => {
  it('initialize picks the first available transport', async () => {
    const dead = { name: 'dead', available: async () => false };
    const live = fakeTransport({});
    const a = new OctraWalletAdapter({ transports: [dead, live] });
    assert.equal(await a.initialize(), true);
    assert.equal(a.isReady(), true);
    assert.equal(a.transport, live);
  });

  it('initialize is false with no usable transport', async () => {
    const a = new OctraWalletAdapter({
      transports: [{ name: 'dead', available: async () => false }],
    });
    assert.equal(await a.initialize(), false);
    assert.equal(a.isReady(), false);
  });

  it('methods refuse before connect', async () => {
    const a = adapterWith({});
    await a.initialize();
    await assert.rejects(() => a.sendTransaction({ to: ADDR, amount: '1' }),
      (e) => e.code === ERROR_CODES.NOT_CONNECTED);
    await assert.rejects(() => a.getBalance(),
      (e) => e.code === ERROR_CODES.NOT_CONNECTED);
  });

  it('connect normalizes and emits', async () => {
    const a = adapterWith({ octra_requestAccounts: [ADDR] });
    await a.initialize();
    const seen = [];
    a.on('connect', (d) => seen.push(d));
    const res = await a.connect(['accounts']);
    assert.equal(res.address, ADDR);
    assert.deepEqual(res.permissions, ['accounts']);
    assert.equal(a.isConnected(), true);
    assert.equal(a.getAddress(), ADDR);
    assert.equal(seen.length, 1);
    await a.disconnect();
    assert.equal(a.isConnected(), false);
    assert.equal(a.getAddress(), null);
  });

  it('connect rejects invalid addresses', async () => {
    const a = adapterWith({ octra_requestAccounts: ['bogus'] });
    await a.initialize();
    await assert.rejects(() => a.connect(), (e) => e.code === ERROR_CODES.UNAUTHORIZED);
    assert.equal(a.isConnected(), false);
  });
});

describe('sendTransaction', () => {
  function connected(responses = {}) {
    const a = adapterWith({
      octra_requestAccounts: [ADDR],
      'wallet_sendTransaction': { hash: 'h1' },
      ...responses,
    });
    return (async () => {
      await a.initialize();
      await a.connect();
      return a;
    })();
  }

  it('sends micro-OCT and normalizes the hash', async () => {
    const a = await connected();
    const r = await a.sendTransaction({ to: OTHER, amountOct: '10.5' });
    assert.equal(r.hash, 'h1');
    const t = a.transport;
    assert.equal(t.calls.at(-1).method, 'wallet_sendTransaction');
    assert.deepEqual(t.calls.at(-1).params[0].amount, '10500000');
  });

  it('validates before touching the transport', async () => {
    const a = await connected();
    const n = a.transport.calls.length;
    await assert.rejects(() => a.sendTransaction({ to: 'bad', amount: '1' }),
      (e) => e.code === ERROR_CODES.INVALID_ADDRESS);
    await assert.rejects(() => a.sendTransaction({ to: OTHER, amount: '0' }),
      (e) => e.code === ERROR_CODES.INVALID_AMOUNT);
    await assert.rejects(() => a.sendTransaction({ to: OTHER }),
      (e) => e.code === ERROR_CODES.INVALID_AMOUNT);
    await assert.rejects(
      () => a.sendTransaction({ to: OTHER, amount: '1', amountOct: '1' }),
      (e) => e.code === ERROR_CODES.INVALID_AMOUNT);
    assert.equal(a.transport.calls.length, n, 'no wire calls on invalid input');
  });

  it('empty hash is a failure, not success', async () => {
    const a = await connected({ 'wallet_sendTransaction': {} });
    await assert.rejects(() => a.sendTransaction({ to: OTHER, amount: '1' }),
      (e) => e.code === ERROR_CODES.TRANSACTION_FAILED);
  });
});

describe('callContract / contractView / balances', () => {
  it('calls through with normalized results', async () => {
    const a = adapterWith({
      octra_requestAccounts: [ADDR],
      octra_sendContractTransaction: { txHash: 't1' },
      wallet_callView: { price: '5' },
      getBalance: { balance_raw: '2000000' },
      octra_getEncryptedBalance: { address: ADDR, cipher: 'c1' },
    });
    await a.initialize();
    await a.connect();
    const c = await a.callContract({ contract: OTHER, method: 'swap', params: [1] });
    assert.equal(c.txHash, 't1');
    const v = await a.contractView({ contract: OTHER, method: 'get_price' });
    assert.deepEqual(v, { price: '5' });
    const b = await a.getBalance();
    assert.equal(b.public, '2');
    assert.equal(b.currency, 'OCT');
    const e = await a.getEncryptedBalance();
    assert.equal(e.cipher, 'c1');
  });

  it('sends the canonical new wire names', async () => {
    const a = adapterWith({
      octra_requestAccounts: [ADDR],
      octra_sendContractTransaction: { txHash: 't1' },
      wallet_callView: { price: '5' },
      getBalance: { balance_raw: '2000000' },
    });
    await a.initialize();
    await a.connect();
    await a.callContract({ contract: OTHER, method: 'swap', params: [] });
    assert.equal(a.transport.calls.at(-1).method, 'octra_sendContractTransaction');
    await a.contractView({ contract: OTHER, method: 'get_price' });
    assert.equal(a.transport.calls.at(-1).method, 'wallet_callView');
    await a.getBalance();
    assert.equal(a.transport.calls.at(-1).method, 'getBalance');
  });

  it('legacy names still served via the localhost compat path', async () => {
    // Dual-stack guard: legacy names keep working; canonical new names
    // route to the same /api endpoints.
    const { LocalhostTransport } = await import('../src/transports.mjs');
    const t = new LocalhostTransport({
      fetchImpl: async (url) => {
        const u = String(url);
        if (u.endsWith('/api/balance')) return { ok: true, status: 200, json: async () => ({ balance_raw: '1000000' }) };
        if (u.includes('/api/contract/view')) return { ok: true, status: 200, json: async () => ({ price: '1' }) };
        return { ok: false, status: 404, json: async () => ({ error: 'not found' }) };
      },
    });
    // Both dialects hit the same /api routes.
    assert.deepEqual(await t.request('octra_getBalance', []), { balance_raw: '1000000' });
    assert.deepEqual(await t.request('getBalance', []), { balance_raw: '1000000' });
    assert.deepEqual(
      await t.request('octra_callView', ['octAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'm', [], '']),
      { price: '1' },
    );
    assert.deepEqual(
      await t.request('wallet_callView', ['octAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'm', [], '']),
      { price: '1' },
    );
    // Plain sends stay refused on both dialects (approval-gated only).
    await assert.rejects(() => t.request('octra_sendTransaction', []),
      (e) => e.code === ERROR_CODES.UNSUPPORTED_METHOD);
    await assert.rejects(() => t.request('wallet_sendTransaction', []),
      (e) => e.code === ERROR_CODES.UNSUPPORTED_METHOD);
    await assert.rejects(() => t.request('octra_callContract', []),
      (e) => e.code === ERROR_CODES.UNSUPPORTED_METHOD);
    await assert.rejects(() => t.request('octra_sendContractTransaction', []),
      (e) => e.code === ERROR_CODES.UNSUPPORTED_METHOD);
  });

  it('validates contract inputs', async () => {
    const a = adapterWith({ octra_requestAccounts: [ADDR] });
    await a.initialize();
    await a.connect();
    await assert.rejects(() => a.callContract({ contract: 'bad', method: 'm' }),
      (e) => e.code === ERROR_CODES.INVALID_ADDRESS);
    await assert.rejects(() => a.callContract({ contract: OTHER, method: '' }),
      (e) => e.code === ERROR_CODES.INVALID_PARAMS);
    await assert.rejects(
      () => a.callContract({ contract: OTHER, method: 'm', params: {} }),
      (e) => e.code === ERROR_CODES.INVALID_PARAMS);
    await assert.rejects(() => a.contractView({ contract: '', method: 'm' }),
      (e) => e.code === ERROR_CODES.INVALID_PARAMS);
  });

  it('events fan out without breaking on listener errors', async () => {
    const a = adapterWith({ octra_requestAccounts: [ADDR] });
    await a.initialize();
    let hits = 0;
    a.on('connect', () => { hits++; throw new Error('listener boom'); });
    a.on('connect', () => { hits++; });
    await a.connect();
    assert.equal(hits, 2);
    a.off('connect');
    await a.disconnect();
  });
});

describe('LocalhostTransport guards (no network)', () => {
  function transportWith(routes) {
    return new LocalhostTransport({
      fetchImpl: async (url, opts = {}) => {
        const path = String(url).split('127.0.0.1:8420')[1] || '/';
        const hit = routes[path] ?? routes[path.split('?')[0]];
        if (typeof hit === 'function') return hit(opts);
        if (hit) return hit;
        return {
          ok: false,
          status: 404,
          json: async () => ({ error: 'not found' }),
        };
      },
    });
  }

  const ok = (body) => ({ ok: true, status: 200, json: async () => body });

  it('unsupported methods fail explicitly', async () => {
    const t = new LocalhostTransport({ fetchImpl: async () => {
      throw new Error('must not be called');
    } });
    await assert.rejects(() => t.request('octra_sendTransaction', []),
      (e) => e.code === ERROR_CODES.UNSUPPORTED_METHOD);
    await assert.rejects(() => t.request('wallet_sendTransaction', []),
      (e) => e.code === ERROR_CODES.UNSUPPORTED_METHOD);
    await assert.rejects(() => t.request('octra_callContract', []),
      (e) => e.code === ERROR_CODES.UNSUPPORTED_METHOD);
    await assert.rejects(() => t.request('octra_sendContractTransaction', []),
      (e) => e.code === ERROR_CODES.UNSUPPORTED_METHOD);
    await assert.rejects(() => t.request('nope', []),
      (e) => e.code === ERROR_CODES.UNSUPPORTED_METHOD);
    await assert.rejects(
      () => t.callContractViaApproval({ address: '', method: 'm' }),
      (e) => e.code === ERROR_CODES.INVALID_PARAMS);
  });

  it('connectRaw reads the wallet address (desktop dialect)', async () => {
    const t = transportWith({ '/api/wallet': ok({ address: 'octAAA' }) });
    assert.deepEqual(await t.connectRaw(), { address: 'octAAA' });
    const bad = transportWith({ '/api/wallet': ok({}) });
    await assert.rejects(() => bad.connectRaw(),
      (e) => e.code === ERROR_CODES.UNAUTHORIZED);
  });

  it('connectRaw maps locked wallet (503) to UNAUTHORIZED', async () => {
    const t = transportWith({
      '/api/wallet': { ok: false, status: 503, json: async () => ({ error: 'no wallet loaded' }) },
    });
    await assert.rejects(() => t.connectRaw(),
      (e) => e.code === ERROR_CODES.UNAUTHORIZED && /unlock first/.test(e.message));
  });

  it('setToken updates auth and HTTP errors carry status', async () => {
    let seenAuth = '';
    const t = new LocalhostTransport({
      fetchImpl: async (url, opts = {}) => {
        seenAuth = (opts.headers || {}).Authorization || '';
        return { ok: false, status: 401, json: async () => ({ error: 'Unauthorized' }) };
      },
    });
    t.setToken('tok123');
    await assert.rejects(() => t.request('getBalance', []),
      (e) => e.code === ERROR_CODES.NETWORK_UNAVAILABLE && e.status === 401);
    assert.equal(seenAuth, 'Bearer tok123');
  });

  it('InjectedTransport.connectRaw prefers request(), falls back to legacy connect()', async () => {
    const { InjectedTransport } = await import('../src/transports.mjs');
    // Modern path: provider with request() answers octra_requestAccounts.
    const seen = [];
    const modern = new InjectedTransport({
      async request({ method }) {
        seen.push(method);
        assert.equal(method, 'octra_requestAccounts');
        return ['octAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'];
      },
    });
    assert.equal(await modern.available(), true);
    assert.deepEqual(await modern.connectRaw(), ['octAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA']);
    assert.deepEqual(seen, ['octra_requestAccounts']);
    // Legacy path: provider without request() falls back to connect().
    let connectCalls = 0;
    const legacy = new InjectedTransport({
      async connect() {
        connectCalls++;
        return { address: 'octBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' };
      },
    });
    assert.equal(await legacy.available(), true);
    assert.deepEqual(await legacy.connectRaw(), { address: 'octBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' });
    assert.equal(connectCalls, 1);
  });
});

describe('unwrapRpc + withAuthRetry', () => {
  it('unwraps envelopes, passes bodies through', async () => {
    const m = await import('../src/adapter.mjs');
    assert.deepEqual(m.unwrapRpc({ jsonrpc: '2.0', result: { a: 1 }, id: 1 }), { a: 1 });
    assert.deepEqual(m.unwrapRpc({ result: 5, value: 5 }), { result: 5, value: 5 });
    assert.equal(m.unwrapRpc('raw'), 'raw');
    assert.equal(m.unwrapRpc(null), null);
    assert.deepEqual(m.unwrapRpc([1]), [1]);
  });

  it('retries once after a 401 re-prompt', async () => {
    const m = await import('../src/adapter.mjs');
    let calls = 0;
    const err401 = Object.assign(new Error('Unauthorized'), { status: 401 });
    const fn = async () => {
      calls++;
      if (calls === 1) throw err401;
      return 'ok-second-try';
    };
    let applied = '';
    const out = await m.withAuthRetry(fn, async () => 'tok', async (t) => { applied = t; });
    assert.equal(out, 'ok-second-try');
    assert.equal(calls, 2);
    assert.equal(applied, 'tok');
  });

  it('passes through non-401 and declined prompts', async () => {
    const m = await import('../src/adapter.mjs');
    const boom = new Error('boom');
    await assert.rejects(() => m.withAuthRetry(async () => { throw boom; }, async () => 'tok'), (e) => e === boom);
    const err401 = Object.assign(new Error('Unauthorized'), { status: 401 });
    await assert.rejects(
      () => m.withAuthRetry(async () => { throw err401; }, async () => null),
      (e) => e === err401);
  });

  it('connects over localhost via connectRaw', async () => {
    const { OctraWalletAdapter, LocalhostTransport } = await import('../src/index.mjs');
    const t = new LocalhostTransport({
      fetchImpl: async (url) => {
        const u = String(url);
        if (u.endsWith('/api/wallet/status')) {
          return { ok: true, status: 200, json: async () => ({ loaded: false }) };
        }
        if (u.endsWith('/api/wallet')) {
          return { ok: true, status: 200, json: async () => ({ address: 'oct' + '3'.repeat(44) }) };
        }
        throw new Error('unexpected ' + url);
      },
    });
    const a = new OctraWalletAdapter({ transports: [t] });
    assert.equal(await a.initialize(), true);
    const res = await a.connect();
    assert.equal(res.address, 'oct' + '3'.repeat(44));
    assert.equal(a.isConnected(), true);
  });
});

describe('getBalance accepts every wallet surface shape', () => {
  async function balanceOf(wireBody) {
    const a = adapterWith({
      octra_requestAccounts: [ADDR],
      getBalance: wireBody,
    });
    await a.initialize();
    await a.connect();
    return a.getBalance();
  }

  it('injected RPC envelope: {balance, balance_raw}', async () => {
    const b = await balanceOf({
      jsonrpc: '2.0',
      id: 1,
      result: { balance: '10.5', balance_raw: '10500000', nonce: 4 },
    });
    assert.equal(b.public, '10.5');
    assert.equal(b.raw, '10500000');
    assert.equal(b.nonce, 4);
    assert.equal(b.total, '10.5');
  });

  it('localhost body: {public_raw, encrypted_raw, ..._oct}', async () => {
    // Regression: only balance_raw/balance used to be read, so every
    // localhost page rendered a 0 OCT balance.
    const b = await balanceOf({
      public_raw: 2000000,
      encrypted_raw: 500000,
      total_raw: 2500000,
      public_oct: '2',
      encrypted_oct: '0.5',
      total_oct: '2.5',
      nonce: 9,
    });
    assert.equal(b.public, '2');
    assert.equal(b.private, '0.5');
    assert.equal(b.total, '2.5');
    assert.equal(b.raw, '2000000');
    assert.equal(b.encryptedRaw, '500000');
    assert.equal(b.totalRaw, '2500000');
    assert.equal(b.nonce, 9);
  });

  it('localhost encrypted-only wallet', async () => {
    const b = await balanceOf({ public_raw: '0', encrypted_raw: '750000', encrypted_oct: '0.75' });
    assert.equal(b.public, '0');
    assert.equal(b.private, '0.75');
    assert.equal(b.total, '0.75');
  });

  it('empty/unknown shapes yield nulls, never a crash or a fake 0', async () => {
    for (const body of [{}, null, { error: 'nope' }, 'weird', { balance: '' }]) {
      const b = await balanceOf(body);
      assert.equal(b.public, null, `for ${JSON.stringify(body)}`);
      assert.equal(b.total, null);
      assert.equal(b.raw, null);
      assert.equal(b.currency, 'OCT');
    }
  });

  it('server error body surfaces, not silently zero', async () => {
    const b = await balanceOf({ error: 'Wallet not loaded' });
    assert.equal(b.public, null);
    assert.equal(b.error, 'Wallet not loaded');
  });
});

describe('getTransaction (adapter-only node lookup)', () => {
  it('routes through the transport and unwraps the envelope', async () => {
    const a = adapterWith({
      octra_requestAccounts: [ADDR],
      octra_getTransaction: { jsonrpc: '2.0', result: { found: true, epoch: 12 } },
    });
    await a.initialize();
    await a.connect();
    const tx = await a.getTransaction({ hash: '  0xabc  ' });
    assert.equal(tx.found, true);
    assert.equal(tx.epoch, 12);
    assert.equal(a.transport.calls.at(-1).method, 'octra_getTransaction');
    assert.deepEqual(a.transport.calls.at(-1).params, ['0xabc']);
  });

  it('rejects empty/non-string hashes before any wire call', async () => {
    const a = adapterWith({ octra_requestAccounts: [ADDR] });
    await a.initialize();
    await a.connect();
    const n = a.transport.calls.length;
    for (const bad of [{}, { hash: '' }, { hash: '   ' }, { hash: null }, { hash: 42 }]) {
      await assert.rejects(() => a.getTransaction(bad),
        (e) => e.code === ERROR_CODES.INVALID_PARAMS, `for ${JSON.stringify(bad)}`);
    }
    await assert.rejects(() => a.getTransaction(), (e) => e.code === ERROR_CODES.INVALID_PARAMS);
    assert.equal(a.transport.calls.length, n, 'no wire call on invalid hash');
  });

  it('a miss is data, not an exception', async () => {
    const a = adapterWith({
      octra_requestAccounts: [ADDR],
      octra_getTransaction: { found: false, hash: '0xdead' },
    });
    await a.initialize();
    await a.connect();
    const tx = await a.getTransaction({ hash: '0xdead' });
    assert.equal(tx.found, false);
    assert.equal(tx.epoch, undefined);
  });

  it('LocalhostTransport URL-encodes the hash', async () => {
    let seen = '';
    const t = new LocalhostTransport({
      fetchImpl: async (url) => {
        seen = String(url);
        return { ok: true, status: 200, json: async () => ({ found: false }) };
      },
    });
    await t.request('octra_getTransaction', ['a b&c=d']);
    // encodeURIComponent leaves '/' and ':' alone — both are legal in a hash.
    assert.ok(seen.endsWith('/api/tx?hash=a%20b%26c%3Dd'), `unexpected URL: ${seen}`);
    assert.ok(!/[&]c=/.test(seen.split('?')[1].replace('hash=a%20b%26c%3Dd', '')), 'hash must not inject extra params');
    await assert.rejects(() => t.request('octra_getTransaction', ['']),
      (e) => e.code === ERROR_CODES.INVALID_PARAMS);
    await assert.rejects(() => t.request('octra_getTransaction', [null]),
      (e) => e.code === ERROR_CODES.INVALID_PARAMS);
  });

  it('LocalhostTransport maps unknown tx (desktop 404) to found:false', async () => {
    const t = new LocalhostTransport({
      fetchImpl: async () => ({
        ok: false,
        status: 404,
        json: async () => ({ error: 'transaction not found' }),
      }),
    });
    assert.deepEqual(await t.request('octra_getTransaction', ['abc']), {
      found: false,
      hash: 'abc',
    });
  });
});
