# BlueWallet dApp Adapter (OctraWalletAdapter program)

## Status: Fase A — wallet-side RFC-O-1 dual-stack

The in-app browsers (Android `DappBrowserActivity`, Flutter
`DappBrowserScreen`) expose `window.octra` in two dialects at once.
Third-party adapters (e.g. 0xio `OctraProviderAdapter`) auto-detect this
wallet via the RFC-O-1 names; existing integrations keep working untouched.

## Status: Fase B — `OctraWalletAdapter` JS package (`sdk/`)

Vanilla `.mjs`, zero dependencies, clean-room implementation (patterns
learned from OrionWallet `src/sdk` + 0xio guide — no code copied).

- `src/protocol.mjs` — method registry (legacy + RFC), error codes, capabilities
- `src/errors.mjs` — typed `OctraWalletError`
- `src/units.mjs` — exact OCT↔micro conversion, address shape check
- `src/transports.mjs` — `InjectedTransport` (window.octra), `LocalhostTransport` (reads + approval-gated calls; plain sends refused by design)
- `src/adapter.mjs` — `OctraWalletAdapter` (lifecycle, reads, approved writes, events)
- `test/*.test.mjs` — `node --test`, CI job `sdk`
- `demo/dapp.html` — runnable demo (relative import, serve over HTTP)

Amounts are exact decimal strings; `ou` is wallet-decided (fee oracle).

## Status: Fase C1 — `swap` migrated to the adapter

The embedded `swap` page (both app embeds) now routes its authenticated
calls through the adapter. Public endpoints (`/api/wallet/status`,
`/api/wallet/unlock`, `/api/wallet`, `/api/contract/receipt`) still use plain
`fetch` — the unlock PIN lives in a native dialog the adapter cannot replicate.

| Before (direct fetch) | After (adapter) |
|---|---|
| `GET /api/balance` | `adapter.getBalance()` via `withAuthRetry` |
| `GET /api/contract/view?…get_reserves` | `adapter.contractView({ method: 'get_reserves' })` |
| `GET /api/contract/view?…balance_of` | `adapter.contractView({ method: 'balance_of' })` |
| `POST /api/contract/call` (swap/grant) | `adapter.callContract({ … })` via `withAuthRetry` |

Consequences:

- `ou: '100000'` / `'1000'` are gone — the wallet's fee oracle decides, so a
  stale hardcoded OU can no longer underpay a swap.
- A 401 prompts for the local-server Bearer token once, stores it in
  `sessionStorage` (never `localStorage`), and retries exactly once.
- Adapter errors are typed; the page shows `[code] message`.
- The vendored copies under `*/assets/webcli/adapter/` must stay byte-identical
  to `sdk/src` — `sdk/test/embed.test.mjs` fails the build otherwise.
- `.mjs` is now served as `application/javascript` (both local servers), or
  browsers refuse the module import.

The `webcli/` submodule (upstream) is intentionally untouched — the divergence
lives only in the two app embeds.

## Status: Fase C2 — `bridge` migrated + two dead routes fixed

`bridge.js` (both embeds) routes its Octra-side reads and the lock call
through the adapter. Ethereum-side traffic (MetaMask `eth_*`, signer,
relayer) is deliberately untouched — it is not an Octra wallet surface.

| Before | After |
|---|---|
| `GET /api/balance` (×2) | `adapter.getBalance()` via `withAuthRetry` |
| `POST /api/contract/call` `lock_to_eth` (`ou: '1000'`) | `adapter.callContract({ method: 'lock_to_eth' })` — fee oracle decides |
| `GET /api/transaction?hash=` (×2) | `adapter.getTransaction({ hash })` |
| `GET /api/wallet/status`, `/api/wallet`, `/api/contract/receipt` | unchanged (`fetch`) |

Bugs found and fixed while migrating (not cosmetic):

1. **`getBalance()` read the wrong field names.** It looked for
   `balance`/`balance_raw`, which is the *injected* shape. The local server
   answers `public_raw`/`public_oct`, so every localhost page rendered
   **0 OCT** for a funded wallet — `bridge`, `swap` and the dApp adapter
   alike. `getBalance()` now accepts both surfaces plus encrypted-only
   wallets, normalizes micro-amounts to exact decimal strings, and exposes
   `error` instead of fabricating a zero.
2. **`/api/transaction?hash=` never existed.** `bridge.js` called it to
   resolve the epoch of a lock tx; neither local server nor the upstream
   webcli server (which serves `/api/tx`) had that route, so every epoch
   lookup 404'd and the forward flow could never reach the claim step.
   Added as a public, read-only route on both servers with a shared pure
   normalizer (`normalizeTransaction`) that answers `found: false` for an
   unknown hash — so the poller can tell "not mined yet" from a fault.
3. **13 empty `catch {}` blocks** are inherited from upstream `bridge.js`
   (localStorage guards, EVM receipt/signer pollers). Closing them is C3
   work; `sdk/test/embed.test.mjs` pins the count at ≤13 so it can only
   shrink, never grow silently.

`octra_getTransaction` is an **adapter-only** method (`ADAPTER_ONLY_METHODS`)
— it is a node lookup, not wallet state, so injected providers legitimately
answer `UNSUPPORTED_METHOD`.

## Method surface

| Legacy (existing) | RFC-O-1 alias | Notes |
|---|---|---|
| `connect()` | `requestAccounts()` | approval-gated; alias answers `["addr"]` |
| `octra_accounts`, `octra_chainId` | — | pre-connect reads |
| `octra_getBalance` | — | cached balances |
| — | `octra_getEncryptedBalance` | `{address, cipher}`; error when never refreshed |
| `octra_sendTransaction` | — | approval UI |
| `octra_callContract` | — | approval UI |
| `octra_callView` | — | read-only |

## Error codes (RFC-O-1, 4th `__octra_response` argument)

| Code | Meaning | When |
|---|---|---|
| `0` / omitted | legacy message-only | existing call sites (unchanged wire) |
| `4001` | user rejected | deny/approve-cancel paths |
| `4100` | unauthorized | not connected, wallet locked |
| `4200` | unsupported method | unknown method / message type |
| `4900` | disconnected | provider disconnect |
| `4901` | network unavailable | RPC fetch failures |

Old dApps ignore the 4th argument — fully backward compatible.

## Deprecation policy (strangler)

- Legacy dialect: supported, deprecation warnings planned, **removal at v0.19.0**.
- `OctraWalletAdapter` JS package (Fase B) becomes the documented path.
- Internal pages (swap/bridge/circles) migrate to the adapter (Fase C).
