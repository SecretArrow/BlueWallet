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
      'octra_sendTransaction': { hash: 'h1' },
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
    assert.equal(t.calls.at(-1).method, 'octra_sendTransaction');
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
    const a = await connected({ 'octra_sendTransaction': {} });
    await assert.rejects(() => a.sendTransaction({ to: OTHER, amount: '1' }),
      (e) => e.code === ERROR_CODES.TRANSACTION_FAILED);
  });
});

describe('callContract / contractView / balances', () => {
  it('calls through with normalized results', async () => {
    const a = adapterWith({
      octra_requestAccounts: [ADDR],
      octra_callContract: { txHash: 't1' },
      octra_callView: { price: '5' },
      octra_getBalance: { balance_raw: '2000000' },
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
    await assert.rejects(() => t.request('nope', []),
      (e) => e.code === ERROR_CODES.UNSUPPORTED_METHOD);
    await assert.rejects(
      () => t.callContractViaApproval({ address: '', method: 'm' }),
      (e) => e.code === ERROR_CODES.INVALID_PARAMS);
  });

  it('connectRaw reads the authed wallet address', async () => {
    const t = transportWith({ '/api/wallet/info': ok({ address: 'octAAA' }) });
    assert.deepEqual(await t.connectRaw(), { address: 'octAAA' });
    const bad = transportWith({ '/api/wallet/info': ok({}) });
    await assert.rejects(() => bad.connectRaw(),
      (e) => e.code === ERROR_CODES.UNAUTHORIZED);
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
    await assert.rejects(() => t.request('octra_getBalance', []),
      (e) => e.code === ERROR_CODES.NETWORK_UNAVAILABLE && e.status === 401);
    assert.equal(seenAuth, 'Bearer tok123');
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
        if (u.endsWith('/api/status')) {
          return { ok: true, status: 200, json: async () => ({ status: 'running' }) };
        }
        if (u.endsWith('/api/wallet/info')) {
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
