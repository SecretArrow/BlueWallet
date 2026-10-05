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
});
