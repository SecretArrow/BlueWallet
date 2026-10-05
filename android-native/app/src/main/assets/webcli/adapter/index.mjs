/**
 * OctraWalletAdapter — public entry point.
 *
 * import { OctraWalletAdapter, InjectedTransport, LocalhostTransport } from './index.mjs';
 * (or '../src/index.mjs' from the demo page).
 */
export {
  PROTOCOL_VERSION,
  MIN_PROTOCOL_VERSION,
  LEGACY_METHODS,
  RFC_METHODS,
  SUPPORTED_METHODS,
  canonicalizeMethod,
  isSupportedMethod,
  ERROR_CODES,
  CAPABILITIES,
  EVENTS,
  negotiateVersion,
} from './protocol.mjs';
export { OctraWalletError, userRejected } from './errors.mjs';
export {
  MICRO_PER_OCT,
  isValidAddress,
  octToMicro,
  fromMicroOCT,
  resolveAmount,
} from './units.mjs';
export {
  DEFAULT_LOCAL_URL,
  InjectedTransport,
  LocalhostTransport,
} from './transports.mjs';
export { OctraWalletAdapter } from './adapter.mjs';
export { unwrapRpc, withAuthRetry } from './adapter.mjs';
