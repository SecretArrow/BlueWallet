import { ERROR_CODES } from './protocol.mjs';

/** Typed adapter error. Never thrown bare — always with a code. */
export class OctraWalletError extends Error {
  /**
   * @param {number} code - one of ERROR_CODES
   * @param {string} message - human-readable, safe to display
   * @param {unknown} [details] - extra context (never secrets)
   */
  constructor(code, message, details) {
    super(message);
    this.name = 'OctraWalletError';
    this.code = code;
    if (details !== undefined) this.details = details;
  }
}

/** Build a USER_REJECTED error. */
export function userRejected(detail = 'User rejected the request') {
  return new OctraWalletError(ERROR_CODES.USER_REJECTED, detail);
}
