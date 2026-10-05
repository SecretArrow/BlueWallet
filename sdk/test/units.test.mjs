import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { ERROR_CODES } from '../src/protocol.mjs';
import {
  isValidAddress,
  octToMicro,
  fromMicroOCT,
  resolveAmount,
} from '../src/units.mjs';

const ADDR = 'oct' + '1'.repeat(44);

describe('isValidAddress', () => {
  it('accepts oct+44 base58', () => {
    assert.equal(isValidAddress(ADDR), true);
  });

  it('rejects shape violations', () => {
    assert.equal(isValidAddress(''), false);
    assert.equal(isValidAddress(null), false);
    assert.equal(isValidAddress('oct' + '1'.repeat(43)), false);
    assert.equal(isValidAddress('oct' + '1'.repeat(45)), false);
    assert.equal(isValidAddress('eth' + '1'.repeat(44)), false);
    assert.equal(isValidAddress('oct' + '0'.repeat(44)), false); // 0 not base58
    assert.equal(isValidAddress('oct' + 'O'.repeat(44)), false); // O not base58
  });

  it('trims paste artifacts, then validates shape', () => {
    assert.equal(isValidAddress('  ' + ADDR + '  '), true);
    assert.equal(isValidAddress(ADDR + '\n'), true);
  });
});

describe('octToMicro (exact, max 6 decimals)', () => {
  it('converts cleanly', () => {
    assert.equal(octToMicro('10.5'), '10500000');
    assert.equal(octToMicro('0.000001'), '1');
    assert.equal(octToMicro('0'), '0');
    assert.equal(octToMicro(2), '2000000');
    assert.equal(octToMicro('  3.25  '), '3250000');
  });

  it('rejects inexact and invalid input with INVALID_AMOUNT', () => {
    for (const bad of ['0.30000000000000004', 'abc', '', '-5', '1.2345678', null, undefined, {}]) {
      assert.throws(() => octToMicro(bad), (e) => e.code === ERROR_CODES.INVALID_AMOUNT, `for ${String(bad)}`);
    }
    // The classic float trap: 0.1 + 0.2 must NOT silently pass.
    assert.throws(() => octToMicro(0.1 + 0.2), (e) => e.code === ERROR_CODES.INVALID_AMOUNT);
  });
});

describe('fromMicroOCT', () => {
  it('converts exactly', () => {
    assert.equal(fromMicroOCT('10500000'), '10.5');
    assert.equal(fromMicroOCT(1500000), '1.5');
    assert.equal(fromMicroOCT('0'), '0');
    assert.equal(fromMicroOCT(1000000n), '1');
  });

  it('rejects garbage and negatives', () => {
    assert.throws(() => fromMicroOCT('abc'), (e) => e.code === ERROR_CODES.INVALID_AMOUNT);
    assert.throws(() => fromMicroOCT('-5'), (e) => e.code === ERROR_CODES.INVALID_AMOUNT);
  });
});

describe('resolveAmount (exactly one of amount/amountOct)', () => {
  it('resolves each form', () => {
    assert.equal(resolveAmount({ amount: '10500000' }), '10500000');
    assert.equal(resolveAmount({ amountOct: '10.5' }), '10500000');
  });

  it('rejects both, neither, and garbage', () => {
    assert.throws(() => resolveAmount({ amount: '1', amountOct: '1' }), (e) => e.code === ERROR_CODES.INVALID_AMOUNT);
    assert.throws(() => resolveAmount({}), (e) => e.code === ERROR_CODES.INVALID_AMOUNT);
    assert.throws(() => resolveAmount({ amount: '-1' }), (e) => e.code === ERROR_CODES.INVALID_AMOUNT);
    assert.throws(() => resolveAmount({ amount: '1.5' }), (e) => e.code === ERROR_CODES.INVALID_AMOUNT);
  });
});
