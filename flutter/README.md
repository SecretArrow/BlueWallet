# Octra Wallet — Flutter

Cross-platform wallet for the Octra cryptocurrency network built with Flutter.
Cryptographic operations are handled by a bundled native C++ library
(`liboctra_native.so` / `octra_native.dll`) accessed through Dart FFI, keeping
private keys entirely in native memory.

Supports **Android**, **iOS**, **Linux**, **Windows**, and **macOS**.

## Requirements

| Tool | Version |
|------|---------|
| Flutter | 3.x stable |
| Dart | 3.x |
| Android SDK | 35 (for Android builds) |
| Xcode | 15+ (for iOS/macOS builds) |
| CMake | 3.22+ (for Linux/Windows native builds) |

## Features

### Wallet Management

- **Create wallet** — Ed25519 keypair generated in C++ with `/dev/urandom`
  entropy via Dart FFI.
- **Import wallet** — Accepts 64-byte NaCl secret key (base64), 32-byte seed
  (base64), or hex (64/128 characters).
- **Multi-wallet** — Unlimited wallets; active wallet selectable at runtime.
  Profiles persisted to SharedPreferences as JSON.
- **Remove wallet** — Deletes key from secure storage (minimum 1 wallet
  enforced).
- **Export wallet** — Dedicated screen for backing up key material.
- **View keys** — Reveal private and public keys on demand.

### Balance & Transactions

- **Public balance** — Fetched via JSON-RPC `octra_balance`; raw microcoins
  converted to 6-decimal OCT display using **pure integer arithmetic** (no
  floating-point). `formatOct()` and `parseOct()` operate on `int` values.
- **Encrypted balance (PVAC)** — Separate authenticated RPC call
  (`octra_encryptedBalance`) with Ed25519-signed request + public key. The
  returned cipher is decrypted locally via the PVAC FHE library in C++.
- **Total balance** — Sum of public + decrypted encrypted balance.
- **Send OCT** — Build canonical JSON → Ed25519 sign → broadcast via
  `octra_submit`.
- **Receive** — QR code generation via `qr_flutter` with copyable address.
- **Encrypt / Decrypt balance** — Move funds between public and encrypted pools
  using Pedersen commitments and zero-knowledge proofs.
- **Transaction history** — Paginated via `octra_transactionsByAddress`; cached
  in SQLite for instant offline display.
- **Transaction detail** — Single transaction lookup via `octra_transaction`.
- **Transaction manager** — View and manage all pending/completed transactions.
- **Transaction progress** — Live broadcast/confirmation status screen.
- **Recommended fees** — `octra_recommendedFee` RPC; separate standard (1000)
  and stealth (5000) defaults.
- **Offline balance cache** — SQLite `balance_cache` table for fallback display
  when offline.
- **BigDecimal-safe formatting** — `_formatTokenBalance()` uses `BigInt` for
  arbitrary-precision token amounts with variable decimals.

### Token Support

- **Token discovery** — `octra_listContracts` enumerates all deployed contracts;
  each probed for symbol, name, decimals, and balance.
- **Parallel loading** — Contracts probed in concurrent batches of 8 for fast
  dashboard population.
- **Token transfers** — Signed `op_type: 'call'` transactions with `transfer`
  function via `TokenTransferScreen`.
- **Token caching** — SQLite `token_cache` table stores the last snapshot per
  wallet as a JSON blob with a 5-minute TTL. Cached tokens display instantly
  while fresh data loads in the background.
- **Zero-balance hiding** — Tokens with a zero balance are automatically hidden.

### Stealth Transactions

- **Stealth send** — ECDH key exchange → shared secret → stealth tag + claim
  secret + claim public key; FHE delta cipher + range proofs (stealth_data v5).
- **Stealth scanning** — `octra_stealthOutputs` matched against the wallet's
  view secret key via Curve25519 ECDH.
- **Stealth task management** — Persistent task tracking with list and detail
  screens for multi-step stealth operations.
- **View keypair** — X25519 derived from Ed25519 secret key; registered on-chain
  via `octra_registerViewPubkey`.
- **FHE delta / Pedersen commitments** — `pvacBuildStealthDelta` builds delta
  cipher, commitment, and two range proofs (delta + balance).

### Contract Interaction (DevTools)

Desktop-gated developer tools for smart contract interaction:

- **Deploy contract** — `op_type: 'deploy'` transaction with bytecode +
  constructor arguments.
- **Call contract** — State-changing function call with arguments and operation
  units.
- **View contract** — Read-only method invocation via `octra_contractView`.
- **Contract info** — ABI, storage, and metadata via `octra_contractInfo`.
- **Contract storage** — Read individual storage slots.
- **Transaction receipt** — Execution result lookup by hash.
- **Verify contract** — Submit source code for on-chain verification.
- **Compute address** — Deterministic contract address from deployer + nonce.

### Security

- **PIN protection** — SHA-256 hashed PIN stored in platform secure storage
  (Android Keystore / iOS Keychain / Linux libsecret). Set, verify, change, and
  clear via `PinService`.
- **Biometric authentication** — Fingerprint/face via `local_auth`; optional
  enrollment with device PIN fallback.
- **Session lock** — Auto-locks on background/inactivity; requires
  re-authentication.
- **Secure key storage** — `flutter_secure_storage` wraps platform-native
  keystores.
- **Native crypto** — All crypto operations via C++ FFI; no Dart-side fallback.
  Application fails hard if the native library is unavailable.
- **Signed RPC requests** — Encrypted balance and PVAC registration require
  Ed25519 signatures.
- **PVAC pubkey auto-registration** — Automatically registers the PVAC public
  key on-chain before encrypt/decrypt/stealth operations.
- **dApp origin allowlist** — Manage permitted dApp hostnames.

### Network

- **JSON-RPC 2.0** — Full client implementation with 30-second timeout.
  Endpoint builder auto-appends `/rpc` to the base URL.
- **Multi-network profiles** — Add, remove, edit, and switch node + explorer
  URLs; persisted to SharedPreferences.
- **Default devnet** — `http://165.227.225.79:8080` (RPC) /
  `https://devnet.octrascan.io` (explorer).
- **Error handling** — Friendly messages for socket errors, timeouts, and
  unfunded (account-not-found) wallets.

### UI / UX

- **11 theme palettes** — Dark: Zenith (default), Moonbloom, Signal,
  Night Pulse, Obsidian Grid, Neon Forge. Light: Frostline, Ivory Circuit,
  Solar Paper, Mist Terminal, Pastel. Switchable at runtime; persisted via
  SharedPreferences.
- **Material Design 3** — `useMaterial3: true` with full `ColorScheme`, custom
  `AppBarTheme`, `CardTheme`, `NavigationBarTheme`.
- **Edge-to-edge** — Mobile: `SystemUiMode.edgeToEdge` with portrait lock.
- **Adaptive layout** — `AdaptiveBody` widget: centered max-width (600 px) on
  desktop; full-width on mobile.
- **Custom widgets** — `OctraCard` (styled card with thin border),
  `AddressChip` (monospace copyable address), `StatusBadge`, `TonalButton`,
  `CompactIconButton`.
- **QR scanning** — Camera-based address/payment scanner via `QrScanScreen`.
- **Auto-scan** — Configurable periodic balance refresh.
- **Address book** — Save, edit, and search contacts with label and notes.
- **Share / Clipboard** — One-tap address copy; external sharing via
  `share_plus`.
- **URL launcher** — Explorer links open externally via `url_launcher`.

## Screens & Routes (37 total)

| Route | Screen | Category |
|-------|--------|----------|
| `/splash` | StartupScreen | Auth |
| `/setup` | SetupScreen | Setup |
| `/pin` | PinEntryScreen | Auth |
| `/session-lock` | SessionLockScreen | Auth |
| `/home` | MainScreen (Dashboard · History · Settings) | Main |
| `/send-menu` | SendMenuScreen | Send |
| `/send` | SendScreen | Send |
| `/token-transfer` | TokenTransferScreen | Send |
| `/receive` | ReceiveScreen | Receive |
| `/wallets` | WalletsScreen | Wallets |
| `/add-wallet` | AddWalletScreen | Wallets |
| `/view-keys` | ViewKeysScreen | Wallets |
| `/export-wallet` | ExportWalletScreen | Wallets |
| `/tx-progress` | TxProgressScreen | Wallets |
| `/stealth-send` | StealthSendScreen | Stealth |
| `/stealth-tasks` | StealthTasksScreen | Stealth |
| `/stealth-task-detail` | StealthTaskDetailScreen | Stealth |
| `/stealth-scan` | StealthScanScreen | Stealth |
| `/encrypt-balance` | EncryptBalanceScreen | Balance |
| `/decrypt-balance` | DecryptBalanceScreen | Balance |
| `/qr-scan` | QrScanScreen | Scan |
| `/auto-scan` | AutoScanScreen | Scan |
| `/tx-manager` | TransactionsManagerScreen | Transactions |
| `/tx-detail` | HistoryDetailScreen | Transactions |
| `/confirm-action` | ConfirmActionScreen | Confirm |
| `/about` | AboutScreen | Settings |
| `/network-settings` | NetworkSettingsScreen | Settings |
| `/theme-palette` | ThemePaletteScreen | Settings |
| `/change-pin` | ChangePinScreen | Settings |
| `/biometric-settings` | BiometricSettingsScreen | Settings |
| `/address-book` | AddressBookScreen | Settings |
| `/address-book-entry` | AddressBookEntryScreen | Settings |
| `/dapp-origins` | DappOriginsScreen | Settings |
| `/permissions-center` | PermissionsCenterScreen | Settings |
| `/dev-tools` | DevToolsScreen | DevTools |
| `/dev-deploy` | DevDeployScreen | DevTools |
| `/dev-call` | DevCallScreen | DevTools |
| `/dev-view` | DevViewScreen | DevTools |
| `/dev-info` | DevInfoScreen | DevTools |
| `/dev-receipt` | DevReceiptScreen | DevTools |
| `/dev-verify` | DevVerifyScreen | DevTools |
| `/dev-storage` | DevStorageScreen | DevTools |
| `/dev-compute-addr` | DevComputeAddrScreen | DevTools |

## Architecture

### Services (8)

| Service | Role |
|---------|------|
| `WalletService` | Core ChangeNotifier — wallet CRUD, balance/nonce fetch, tx building/signing/submit, token loading, stealth ops, PVAC lifecycle |
| `CryptoService` | Static API — key gen/import, address derivation, tx signing (canonical JSON), PVAC encrypt/decrypt, stealth building |
| `NativeCrypto` | FFI singleton — loads native library and binds 30+ C++ functions |
| `DatabaseService` | SQLite singleton — tx history, balance cache, address book, token cache |
| `NetworkService` | ChangeNotifier — multi-network profiles, node URL + explorer URL management |
| `PinService` | Static — PIN hash set/verify/change/clear via secure storage |
| `BiometricService` | Static — fingerprint/face auth; mobile-only with safe desktop defaults |
| `AddressBookService` | ChangeNotifier — CRUD for saved addresses; SharedPreferences persistence |

### State Management

- **MultiProvider** at app root provides 4 ChangeNotifiers: `ThemeManager`,
  `WalletService`, `NetworkService`, `AddressBookService`.
- Screens read services via `Provider.of<T>(context)`.
- `DatabaseService` and `NativeCrypto` use the singleton pattern.
- `PinService`, `BiometricService`, `CryptoService` are fully static.

### Database (SQLite)

`octra_wallet.db` — version 3, with managed schema migrations:

| Table | Purpose |
|-------|---------|
| `tx_history` | Full transaction history per wallet (UNIQUE on wallet_id + hash) |
| `balance_cache` | Offline balance fallback (wallet_id PK) |
| `address_book` | Saved contacts with label and notes (UNIQUE on wallet_id + address) |
| `token_cache` | Token snapshot JSON with 5-minute TTL (wallet_id PK) |

Migrations: v1→v2 adds `block_hash` to `tx_history`; v2→v3 adds `token_cache`.

### Platform Native Libraries

| Platform | Library | Notes |
|----------|---------|-------|
| Android | `liboctra_native.so` | arm64-v8a, x86_64 |
| iOS | Statically linked | `DynamicLibrary.process()` |
| Linux | `liboctra_native.so` | Bundled in lib/ |
| Windows | `octra_native.dll` | Bundled |
| macOS | Statically linked | `DynamicLibrary.process()` |

## RPC Methods

| Method | Purpose |
|--------|---------|
| `octra_balance` | Public balance + nonce |
| `octra_encryptedBalance` | Authenticated encrypted balance cipher |
| `octra_transactionsByAddress` | Paginated transaction history |
| `octra_submit` | Broadcast signed transaction |
| `octra_recommendedFee` | Fee recommendation |
| `octra_transaction` | Single transaction lookup |
| `octra_listContracts` | Enumerate deployed contracts |
| `octra_contractStorage` | Read contract storage key |
| `octra_contractView` | Read-only contract call |
| `octra_contractInfo` | Contract ABI + metadata |
| `octra_receipt` | Contract execution receipt |
| `octra_verifyContract` | Submit source for verification |
| `octra_computeContractAddress` | Deterministic contract address |
| `octra_pvacPubkey` | Query PVAC public key |
| `octra_viewPubkey` | Query view public key |
| `octra_registerPvacPubkey` | Register PVAC key on-chain |
| `octra_registerViewPubkey` | Register view key on-chain |
| `octra_stealthOutputs` | List stealth outputs for scanning |

## Project Structure

```
flutter/
├── lib/
│   ├── main.dart              # Entry point
│   ├── app.dart               # MaterialApp + MultiProvider setup
│   ├── models/                # Data models (wallet, tx, token, etc.)
│   ├── router/                # GoRouter route definitions
│   ├── screens/               # All screens organized by feature
│   │   ├── auth/              # PIN, session lock
│   │   ├── main/              # Dashboard, history, settings tabs
│   │   ├── send/              # Send, token transfer, send menu
│   │   ├── receive/           # Receive with QR
│   │   ├── wallets/           # Wallet management
│   │   ├── stealth/           # Stealth send, scan, tasks
│   │   ├── transactions/      # History detail, tx manager
│   │   ├── devtools/          # Contract interaction tools
│   │   ├── settings/          # Theme, network, PIN, biometric
│   │   ├── scan/              # QR scan, auto-scan
│   │   └── confirm/           # Confirmation screen
│   ├── services/              # Business logic services
│   ├── theme/                 # Theme palettes + ThemeManager
│   └── widgets/               # Reusable UI components
├── assets/images/             # App logos
├── android/                   # Android platform project
├── ios/                       # iOS platform project
├── linux/                     # Linux platform project
├── windows/                   # Windows platform project
├── test/                      # Unit and widget tests
└── pubspec.yaml               # Dependencies
```

## Build

### Debug

```bash
flutter run               # Run on connected device
flutter build apk --debug # Android APK
flutter build ios --debug  # iOS (requires macOS)
```

### Release

```bash
flutter build apk --release
flutter build ios --release
flutter build linux --release
flutter build windows --release
```

### Analyze

```bash
flutter analyze
dart analyze
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `provider` | State management |
| `go_router` | Declarative routing |
| `sqflite` / `sqflite_common_ffi` | SQLite database |
| `flutter_secure_storage` | Platform-native secure key storage |
| `local_auth` | Biometric authentication |
| `qr_flutter` | QR code generation |
| `share_plus` | External sharing |
| `url_launcher` | Open explorer links |
| `file_picker` | Wallet import/export files |
| `flutter_svg` | SVG asset rendering |
| `package_info_plus` | App version info |
| `path_provider` | Platform storage paths |
| `shared_preferences` | Lightweight key-value persistence |

## License

Released under the GPL license with OpenSSL exception. See `COPYING` for details.
