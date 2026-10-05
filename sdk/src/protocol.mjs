/**
 * Wire protocol registry for OctraWalletAdapter (Fase B).
 *
 * Dual-stack: the legacy BlueWallet dialect keeps working and RFC-O-1
 * aliases dispatch alongside it. Error codes follow RFC-O-1 so third-party
 * adapters keep interoperating. Pure data + pure functions only.
 */

/** Bump when the envelope shape or handshake semantics change incompatibly. */
export const PROTOCOL_VERSION = 1;

/** Lowest protocol version this build can still talk to. */
export const MIN_PROTOCOL_VERSION = 1;

/** Legacy BlueWallet wire methods (as spoken by window.octra / local server). */
export const LEGACY_METHODS = Object.freeze([
  'octra_accounts',
  'octra_chainId',
  'octra_getBalance',
  'octra_sendTransaction',
  'octra_callContract',
  'octra_callView',
]);

/** RFC-O-1 aliases answered by BlueWallet wallets (Fase A). */
export const RFC_METHODS = Object.freeze([
  'octra_requestAccounts',
  'octra_getEncryptedBalance',
]);

/** Every method name the wallet answers to, in either dialect. */
export const SUPPORTED_METHODS = Object.freeze([...LEGACY_METHODS, ...RFC_METHODS]);

/**
 * Trim + null-guard a raw method name. Unknown names pass through unchanged
 * and are rejected downstream as unsupported.
 */
export function canonicalizeMethod(method) {
  if (typeof method !== 'string') return '';
  return method.trim();
}

/** True when the wallet dispatches this method (either dialect). */
export function isSupportedMethod(method) {
  const m = canonicalizeMethod(method);
  return LEGACY_METHODS.includes(m) || RFC_METHODS.includes(m);
}

/** Stable machine-readable error codes (RFC-O-1). */
export const ERROR_CODES = Object.freeze({
  NO_CODE: 0,
  USER_REJECTED: 4001,
  UNAUTHORIZED: 4100,
  UNSUPPORTED_METHOD: 4200,
  DISCONNECTED: 4900,
  NETWORK_UNAVAILABLE: 4901,
  INVALID_PARAMS: 4201,
  INVALID_AMOUNT: 4202,
  NOT_CONNECTED: 4101,
  INVALID_ADDRESS: 4102,
  TRANSACTION_FAILED: 4300,
});

/** Capabilities BlueWallet wallets advertise. */
export const CAPABILITIES = Object.freeze([
  'connect',
  'accounts',
  'balance',
  'encryptedBalance',
  'sendTransaction',
  'callContract',
  'contractView',
  'events',
]);

/** Events the adapter emits locally. */
export const EVENTS = Object.freeze([
  'connect',
  'disconnect',
  'accountsChanged',
]);

/** Negotiate the highest protocol version both sides support. */
export function negotiateVersion(theirs) {
  if (!Number.isInteger(theirs) || theirs < MIN_PROTOCOL_VERSION) return null;
  return Math.min(theirs, PROTOCOL_VERSION);
}
