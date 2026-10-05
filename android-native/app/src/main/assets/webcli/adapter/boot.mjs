/**
 * boot.mjs — shared bootstrap for embedded dApp pages (Fase C1).
 *
 * Builds an OctraWalletAdapter preferring the injected provider (in-app
 * browser, no token needed) with a localhost fallback (Bearer token kept in
 * sessionStorage — cleared when the tab closes, never localStorage).
 * Every authed call goes through withAuthRetry(), which prompts once on 401
 * and retries a single time.
 *
 * Embed-side glue, deliberately NOT part of sdk/ — it owns DOM/session
 * concerns the SDK must stay free of.
 */
import {
  OctraWalletAdapter,
  InjectedTransport,
  LocalhostTransport,
} from './index.mjs';

const TOKEN_KEY = 'octra_local_token';

/** Session-scoped token ('' when storage is unavailable or unset). */
export function loadToken() {
  try {
    return sessionStorage.getItem(TOKEN_KEY) || '';
  } catch (_) {
    return '';
  }
}

export function saveToken(token) {
  try {
    if (token) sessionStorage.setItem(TOKEN_KEY, token);
    else sessionStorage.removeItem(TOKEN_KEY);
  } catch (_) {
    // Private-mode storage refusal must not break the page; the token then
    // lives only in memory for this tab.
  }
}

/**
 * @param {object} opts
 * @param {string} [opts.appName]
 * @param {(reason: string) => Promise<string|null>} [opts.promptToken]
 *   resolved with a token, or null to decline the retry.
 * @returns {{adapter: OctraWalletAdapter, localhost: LocalhostTransport,
 *            withAuthRetry: (fn: Function) => Promise<any>,
 *            isInitialized: () => boolean}}
 */
export function createAdapter(opts = {}) {
  const localhost = new LocalhostTransport({ token: loadToken() });
  const adapter = new OctraWalletAdapter({
    appName: opts.appName || 'Octra dApp',
    transports: [new InjectedTransport(), localhost],
  });
  const promptToken = typeof opts.promptToken === 'function'
    ? opts.promptToken
    : async () => null;

  /**
   * Run fn(); on HTTP 401 prompt once, persist the token and retry exactly
   * once. A declined prompt and every non-401 error rethrow the original
   * error untouched so callers see one failure mode, not two.
   */
  async function withAuthRetry(fn) {
    try {
      return await fn();
    } catch (e) {
      const unauthorized =
        !!e && (e.status === 401 || /401|unauthorized/i.test(e.message || ''));
      if (!unauthorized) throw e;
      const token = await promptToken(
        'Paste the Bearer token from Local Web Server settings in the wallet app.',
      );
      if (!token) throw e;
      saveToken(token);
      localhost.setToken(token);
      return await fn();
    }
  }

  return {
    adapter,
    localhost,
    withAuthRetry,
    isInitialized: () => adapter.isReady(),
  };
}
