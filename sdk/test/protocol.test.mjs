import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  LEGACY_METHODS,
  RFC_METHODS,
  SUPPORTED_METHODS,
  canonicalizeMethod,
  isSupportedMethod,
  ERROR_CODES,
  CAPABILITIES,
  negotiateVersion,
} from '../src/protocol.mjs';

describe('protocol', () => {
  it('covers both dialects without overlap gaps', () => {
    for (const m of LEGACY_METHODS) assert.equal(isSupportedMethod(m), true);
    for (const m of RFC_METHODS) assert.equal(isSupportedMethod(m), true);
    assert.equal(
      SUPPORTED_METHODS.length,
      LEGACY_METHODS.length + RFC_METHODS.length,
    );
  });

  it('canonicalize trims and null-guards', () => {
    assert.equal(canonicalizeMethod('  octra_requestAccounts  '), 'octra_requestAccounts');
    assert.equal(canonicalizeMethod(null), '');
    assert.equal(canonicalizeMethod(42), '');
  });

  it('rejects unknown and execution-flavored names', () => {
    assert.equal(isSupportedMethod('octra_broadcast'), false);
    assert.equal(isSupportedMethod('eth_sendTransaction'), false);
    assert.equal(isSupportedMethod(''), false);
  });

  it('pins RFC-O-1 error codes', () => {
    assert.equal(
      [ERROR_CODES.USER_REJECTED, ERROR_CODES.UNAUTHORIZED,
        ERROR_CODES.UNSUPPORTED_METHOD, ERROR_CODES.DISCONNECTED,
        ERROR_CODES.NETWORK_UNAVAILABLE].join(','),
      '4001,4100,4200,4900,4901',
    );
  });

  it('advertises sign-free capabilities (submits stay wallet-approved)', () => {
    assert.ok(CAPABILITIES.includes('sendTransaction'));
    assert.ok(!CAPABILITIES.includes('localSign'));
  });

  it('negotiates versions', () => {
    assert.equal(negotiateVersion(1), 1);
    assert.equal(negotiateVersion(99), 1);
    assert.equal(negotiateVersion(0), null);
    assert.equal(negotiateVersion('x'), null);
  });
});
