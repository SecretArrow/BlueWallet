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
