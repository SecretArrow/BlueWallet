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

  it('keeps the legacy dialect intact (dual-stack, no removal)', () => {
    assert.deepEqual([...LEGACY_METHODS], [
      'octra_accounts',
      'octra_chainId',
      'octra_getBalance',
      'octra_sendTransaction',
      'octra_callContract',
      'octra_callView',
    ]);
  });

  it('registers the canonical new names as RFC aliases', () => {
    // Canonical NEW: wallet_sendTransaction (submit, approval-gated),
    // wallet_callView (read-only).
    assert.ok(RFC_METHODS.includes('wallet_sendTransaction'));
    assert.ok(RFC_METHODS.includes('wallet_callView'));
    assert.ok(SUPPORTED_METHODS.includes('wallet_sendTransaction'));
    assert.ok(SUPPORTED_METHODS.includes('wallet_callView'));
    // No overlap: new names are additions, not replacements.
    for (const m of ['wallet_sendTransaction', 'wallet_callView']) {
      assert.equal(LEGACY_METHODS.includes(m), false);
    }
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
