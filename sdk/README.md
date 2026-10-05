# OctraWalletAdapter (`@bluewallet/octra-wallet-adapter`)

dApp-side adapter for BlueWallet / Octra wallets. Clean-room implementation
(patterns learned from OrionWallet `src/sdk` and the 0xio SDK guide — no code
copied; OrionWallet is CC BY-NC-SA 4.0). Zero dependencies, vanilla `.mjs`.

## Transports (tried in order)

| Transport | Needs | Supports |
|---|---|---|
| `InjectedTransport` | `window.octra` (in-app browsers, RFC-O-1 wallets) | everything the wallet speaks |
| `LocalhostTransport` | local server `127.0.0.1:8420` (+ token for writes) | reads + approval-gated `callContract` only — plain sends are refused by design (auto-sign risk) |

## API (amounts are exact decimal STRINGS, never floats)

```js
import { OctraWalletAdapter, InjectedTransport, LocalhostTransport } from './src/index.mjs';

const adapter = new OctraWalletAdapter({
  appName: 'My dApp',
  transports: [new InjectedTransport(), new LocalhostTransport({ token })],
});

await adapter.initialize();          // false when nothing is usable
const { address } = await adapter.connect(['accounts']);
await adapter.getBalance();          // {public, private, total, raw, ..., currency:'OCT'}
await adapter.sendTransaction({ to, amountOct: '10.5' });   // or {to, amount:'10500000'}
await adapter.callContract({ contract, method, params: [...] }); // approval UI on wallet
await adapter.contractView({ contract, method, params: [] });   // read-only, no approval
await adapter.getEncryptedBalance(); // PVAC cipher bundle
adapter.on('connect', console.log).on('disconnect', console.log);
```

Exactly one of `amount`/`amountOct`; `ou` is wallet-decided (fee oracle) and
intentionally not a parameter. Errors are `OctraWalletError` with RFC-O-1
`code` (4001/4100/4200/4900/4901 + adapter-local 4101/4102/4202/4220/4300).

## Test

```bash
npm test   # node --test, zero install needed (Node 18+)
```
