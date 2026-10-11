# Third-party dApps in the BlueWallet browser

dApps built with the **0xio SDK** (`@0xio/sdk`, MIT) work in this wallet's
in-app Browser with no changes on the dApp side. The SDK's
`OctraProviderAdapter` drives `window.octra.request()` and auto-detects any
RFC-O-1 wallet via `window.octra.isOctra === true` plus the
`octra#initialized` event — both of which this browser provides.

Interface mapping below is clean-room (observed method names and shapes
only — no third-party code is vendored or copied).

## What the adapter sends, and what the browser answers

Connect flow (built by the adapter from three provider calls):

| Adapter step | Provider request | Browser answer |
|---|---|---|
| `connect()` → accounts | `octra_requestAccounts` `[{permissions}]` | approval dialog → `[address]`; requested scopes recorded |
| `connect()` → network | `octra_networkInfo` | `{id: 'mainnet'\|'devnet', name, chainId, rpcUrl, explorerUrl, isTestnet}` |
| `connect()` → scopes | `octra_permissions` | scopes granted at approval (all-or-nothing) |
| `getConnectionStatus()` | `octra_accounts` + the two above | same reads, no dialog |

Reads and writes:

| Adapter method | Provider request | Browser answer |
|---|---|---|
| `getBalance` | `getBalance` `{forceRefresh}` | raw balance read (`balance` decimal OCT; missing `privateBalance` → SDK-side 0) |
| `getPublicKey` | `getPublicKey` | `{publicKey}` when the wallet stored one, else an honest error |
| `sendTransaction` | `octra_sendTransaction` `{to, amount, amountOct?, message?, ...}` | **approval dialog → submit** → `{tx_hash, hash, accepted: true, success: true}` |
| `callContract` | `octra_sendContractTransaction` `{contract, method, params, amount?, ou?}` | **approval dialog → submit** (fee oracle stays authoritative; attached `ou` is read, not applied) |
| `contractCallView` | `octra_callContract` `{contract, method, params, caller?}` | read-only view, no dialog |
| `switchNetwork` | `octra_switchNetwork` `{networkId}` | `{network: current, switched}` — `true` only when already there (below) |
| `disconnect` | `disconnect` | session cleared → `{success: true}` |
| `ping`, `register_dapp` | — | answered inside the adapter, never reach the provider |

Two methods share one name and are split by shape: `octra_callContract`
with an **array** params submits (legacy behaviour, unchanged); with an
**object** params it is a view when no value is attached, a submission
otherwise. The rule is `isViewCall` (no `amount`/`ou` key → view), unit-tested
on both platforms.

Amounts follow the exact-arithmetic rule everywhere: exactly one of
`amount` (raw micro-OCT integer string) / `amountOct` (max 6 decimals);
anything inexact is rejected, never rounded. A zero amount and a message over
1000 chars are rejected before any dialog opens. `isPrivate: true` is refused
— stealth submission is not offered over the provider.

## Explicit gaps (rejected with a named error, never silent)

`octra_signTransaction`, `octra_submitTransaction`, `octra_signMessage`,
and every `octra_*` private primitive (`encrypt/decryptBalance`,
`sendPrivateTransfer`, `claimStealth`, capabilities, proofs, view-key
registration, sequences, batches) answer `4200 UNSUPPORTED_METHOD` naming the
method. Rationale:

- This wallet **submits via its own approval** and never hands out
  sign-only payloads or broadcasts opaque pre-signed blobs — that is its
  identity, kept deliberately (see `docs/ADAPTER.md`).
- Message signing and FHE-private primitives stay in the wallet UI.

## Orion-built dApps (`window.wallet` facade)

Orion's dApp SDK also ships an injected provider (`window.wallet`, with a
`window.octra` alias and the `octra:wallet#initialized` announcement). This
browser exposes a `window.wallet` object with the same high-level surface,
backed by this wallet's approval flow — Orion-built dApps that use the
injected provider connect here with no changes. (dApps driving Orion's popup
`MessageChannel` transport target the Orion wallet origin and cannot reach
this browser — that path is out of scope by construction.)

| Facade method | Backed by | Notes |
|---|---|---|
| `connect()` | `octra_requestAccounts` + reads | approval dialog → `{address, publicKey, accounts, network, networkInfo, chainId, capabilities: ['ping','events']}`; `publicKey` is `''` when the wallet stored none |
| `disconnect()` | `disconnect` | clears session, emits `disconnect` |
| `getAccounts()` / `getAddress()` | `octra_accounts` | |
| `getPublicKey()` | `getPublicKey` | honest error when unavailable |
| `getBalance()` | `octra_getBalance` | mapped to `{balance, balanceRaw, nonce}` |
| `getNetwork()` / `getNetworkInfo()` / `getNetworks()` | `octra_networkInfo` | single-network wallet → one-element list |
| `getChainId()` / `getPermissions()` | same names | |
| `signMessage`, `signTypedData`, `approveContract`, `signContract`, `signTransfer` | — | throw `{code: 'METHOD_FORBIDDEN'}` locally, never touch the bridge |
| `ping()` | local | `{pong: true, v: 1, connected, locked, capabilities, origin, ts}` |
| `isAlive()` / `isConnected()` | local session flags | |
| `request(method, params)` | `window.octra.request` | `orion_wallet_*` folded to `wallet_*`; execution-shaped names refused locally with `METHOD_FORBIDDEN` (same prohibited list as the native side) |
| `on` / `off` / `once` | local listener map | `connect`, `disconnect`, `accountChanged` emitted by the facade |

The native side answers the `wallet_*` names directly (`wallet_getAccounts`,
`wallet_getBalance`, `wallet_ping`, …) with `orion_wallet_*` folded to the
same handlers, so the facade is thin and every mapping is unit-tested.

Deliberate races: `window.wallet` is defined writable + configurable (unlike
`window.octra`, which is frozen). If a dApp bundles Orion's own injector,
its first-wins check finds ours and uses it; if another provider already
claimed the slot, our definition is skipped inside `try/catch` and
`window.octra` keeps serving.

## Manual QA (needs the emulator + internet)

1. Serve a page that imports `@0xio/sdk` from CDN and runs
   `createZeroXIOWallet({ appName, autoConnect: false })` → `initialize()` must
   be `true` inside the in-app browser.
2. `connect({ permissions: ['accounts', 'public_transactions'] })` → approval
   dialog → address, networkInfo, permissions echoed.
3. `getBalance()` → public decimal; `contractCallView()` → no dialog;
   `sendTransaction({ to, amountOct: '0.000001' })` → dialog → hash.
4. `signMessage('hi')` → clean `4200` rejection, not a hang.
