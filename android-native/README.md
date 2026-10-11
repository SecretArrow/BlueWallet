# Octra Wallet — Android Native

Full-featured native Android wallet for the Octra cryptocurrency network. All
cryptographic operations run inside a bundled C++ library (`liboctra_wallet_native.so`)
accessed through JNI, so private keys never leave the native layer.

## Download APK

Pre-built APK releases are available from GitHub Actions:

1. Go to the [Actions tab](../../actions/workflows/android-build.yml).
2. Select the latest successful workflow run.
3. Download the `octra_wallet-debug` or `octra_wallet-release` artifact.

## Requirements

| Tool | Version |
|------|---------|
| Android Studio | Koala or later |
| Android SDK | 35 (Android 15) |
| Android NDK | r27+ |
| CMake | 3.22.1+ |
| Java | 17 |

- **Minimum Android**: 9 (API 28)
- **Target Android**: 15 (API 35)

## Features

### Wallet Management

- **Create wallet** — Ed25519 keypair generated in C++ with secure random entropy.
- **Import wallet** — Import from base64-encoded private key.
- **HD Version Autodetect** — Space-separated BIP-39 mnemonic phrases (12 or 24 words) entered into the private key input field are automatically detected and processed. The app probes the active JSON-RPC node for both HD derivation Version 1 and Version 2 balances, and automatically selects the correct derivation schema dynamically.
- **Mnemonic secure storage** — Imported mnemonics are encrypted using AES-256-GCM via the Android Keystore system and persisted in `MnemonicStore`, keeping them secure.
- **Multi-wallet profiles** — Create, switch, and delete an unlimited number of
  wallets. Each profile stores a name and Octra address.
- **Export wallet** — Dedicated export screen for backing up key material.
- **View keys** — Reveal private key and view public key on demand.
- **Change PIN** — Re-encrypts the wallet file with a new PIN.
- **Legacy wallet migration** — Automatically detects and loads pre-encryption
  (legacy) wallet files.

### Balance & Transactions

- **Public balance** — Fetched via JSON-RPC `octra_balance`; displayed with
  6-decimal precision using `BigDecimal` (no floating-point).
- **Encrypted balance (PVAC)** — Separate authenticated RPC call
  (`octra_encryptedBalance`) with Ed25519-signed request + public key. The
  returned cipher is decrypted locally via the PVAC FHE library.
- **Total balance** — Sum of public + decrypted encrypted balance.
- **Send OCT** — Build canonical JSON → Ed25519 sign → broadcast via
  `octra_submit`.
- **Receive** — Displays wallet address with QR code.
- **Encrypt / Decrypt balance** — Move funds between public and encrypted pools
  using Pedersen commitments and zero-knowledge proofs.
- **Transaction history** — Paginated via `octra_transactionsByAddress`; cached
  locally in Room DB for instant offline display.
- **Transaction detail** — Single transaction lookup via `octra_transaction`.
- **Transaction progress** — Real-time progress tracking with foreground service
  notifications.
- **Transactions manager** — View and manage all pending/completed transaction
  tasks.
- **Recommended fees** — Fetched via `octra_recommendedFee` RPC; separate
  standard and stealth fee defaults.

### Token Support

- **Token discovery** — `octra_listContracts` enumerates all deployed contracts;
  each is probed for symbol, name, decimals, and balance.
- **Parallel token loading** — Contracts probed concurrently (batches of 8) for
  fast dashboard population.
- **Token transfers** — Signed contract-call transactions via native C++ layer.
- **Token snapshot caching** — Room DB stores the last token snapshot per wallet
  with a timestamp; cached data is displayed immediately while fresh data loads
  in the background.
- **Token search/filter** — Search bar on the dashboard filters the token list
  in real time.

### Stealth Transactions

- **Stealth send** — ECDH key exchange → shared secret → stealth tag + claim
  secret + claim public key; signed natively.
- **Stealth scanning** — Scans `octra_stealthOutputs` for incoming stealth
  payments matched against the wallet's view secret key.
- **Stealth claim service** — Foreground service claims detected stealth outputs
  automatically.
- **Stealth task management** — Persistent task tracking with list and detail
  screens for multi-step stealth operations.
- **View public key registration** — Registers the X25519 view key on-chain via
  `octra_registerViewPubkey`.

### Contract Interaction

- **List contracts** — `octra_listContracts`
- **Contract storage** — Read individual storage keys via `octra_contractStorage`.
- **Contract view call** — Read-only method invocation via `octra_contractView`.
- **Compile assembly / AML** — Server-side compilation of assembly or AML source.
- **Compute contract address** — Deterministic address from deployer + nonce.
- **Contract receipt** — Execution result lookup for contract transactions.
- **Contract ABI** — Fetch or upload ABI; source verification via
  `octra_verifyContract`.

### Security

- **PIN protection** — 6-digit PIN; wallet files encrypted with PBKDF2-HMAC-SHA256
  (100 000 iterations) + AES-256-GCM in C++.
- **Biometric unlock** — AndroidX `BiometricPrompt` (fingerprint/face); optional
  enrollment with PIN fallback.
- **Session lock** — Auto-locks after inactivity; requires re-authentication to
  resume.
- **Root & emulator detection** — `SecurityChecker` warns when running on rooted
  devices or emulators (checks su paths, management packages, build fingerprints).
- **Memory protection** — `secure_zero()` wipes secret key buffers; `try_mlock()`
  locks memory pages to prevent swap.
- **URL security validation** — Warns when RPC endpoint uses cleartext HTTP.
- **Backup disabled** — `android:allowBackup="false"` prevents cloud backup of
  wallet data.
- **dApp origin allowlist** — `DappOriginsActivity` manages which dApp hostnames
  are permitted.

### Network

- **JSON-RPC 2.0** — Full client implementation with configurable retry count.
- **Multi-network profiles** — Named node configurations (RPC URL + explorer URL);
  add, remove, and switch at runtime.
- **Default devnet** — `http://165.227.225.79:8080` (RPC) /
  `https://devnet.octrascan.io` (explorer).
- **Explorer integration** — Transaction hashes link directly to the block
  explorer.

### UI / UX

- **10 theme palettes** — Zenith (default), Moonbloom, Frostline, Signal,
  Night Pulse, Obsidian Grid, Neon Forge, Ivory Circuit, Solar Paper,
  Mist Terminal. Switchable at runtime.
- **Material Design** — AppCompat + Material Components; all activities extend
  `AppCompatActivity`.
- **QR code scanning** — Camera-based scanner for addresses and payment URIs.
- **Deep linking** — `octra://send?to=<addr>&amount=<val>` parsed by
  `MainActivity`.
- **Auto-scan** — Configurable interval; `AutoScanService` (foreground) +
  `AutoScanWorker` (WorkManager) periodically refresh balances.
- **Address book** — Save, edit, search, and pick saved addresses.
- **Portrait lock** — All activities locked to portrait orientation.

### dApp Browser & Wallet Adapter

- **In-app dApp browser** — Loads dApp websites and injects the `window.octra`
  / `window.wallet` provider (see `DappBrowserActivity`).
- **Modular wallet adapter** — `WalletAdapter` + `OctraWalletAdapter` +
  `AdapterRegistry` dispatch provider methods; the `DappJsBridge`
  exposes only a minimal validated `@JavascriptInterface`.
  Every sensitive call (connect, send, contract call, network switch)
  requires explicit user approval; cancel/dismiss always counts as rejection.
- **Per-origin sessions** — Approvals persist per hostname in `DappOriginStore`
  and can be revoked in the DApp Origins screen or Permissions Center.
- **Startpage** — Search + URL bar, quick explorer links, and the last
  10 visited websites (`RecentVisitsStore`, persisted, deduplicated).
- **Deep link bridge** — External browsers reach the wallet via the
  `octra-wallet://` scheme (`DeepLinkBridgeActivity`), signed natively.

## Screens (33 Activities)

| Activity | Purpose |
|----------|---------|
| `MainActivity` | Dashboard — balances, token list, deep link handler |
| `SetupActivity` | First-launch onboarding |
| `UnlockActivity` | PIN + biometric unlock |
| `SessionLockActivity` | Inactivity auto-lock |
| `PinEntryActivity` | Standalone PIN input |
| `ChangePinActivity` | Change wallet PIN |
| `WalletFilePinActivity` | PIN for file-level operations |
| `AddWalletActivity` | Create / import wallet |
| `WalletsActivity` | List wallet profiles |
| `WalletsMenuActivity` | Wallet management menu |
| `ViewKeysActivity` | Show keys |
| `ExportWalletsActivity` | Export wallet data |
| `ConfirmDeleteWalletActivity` | Confirm wallet deletion |
| `ConfirmActionActivity` | Generic sensitive-action confirmation |
| `SendActivity` | Standard OCT send |
| `SendMenuActivity` | Send type selector (standard / stealth / token) |
| `StealthSendActivity` | Stealth send flow |
| `StealthScanActivity` | Scan incoming stealth payments |
| `StealthTasksActivity` | List stealth tasks |
| `StealthTaskDetailActivity` | Stealth task detail |
| `EncryptBalanceActivity` | Public → encrypted |
| `DecryptBalanceActivity` | Encrypted → public |
| `ReceiveActivity` | Address + QR code |
| `TransactionsManagerActivity` | Manage pending/completed txs |
| `TxProgressActivity` | Live transaction progress |
| `HistoryDetailActivity` | Single transaction detail |
| `NetworkSettingsActivity` | RPC / explorer settings |
| `AddNetworkActivity` | Add custom node |
| `DappBrowserActivity` | In-app dApp browser + Startpage (10 recent visits) |
| `DeepLinkBridgeActivity` | Intercepts contract-call deep links, displays premium swap prompt dialog, and routes the signed hash back |
| `ThemePaletteActivity` | Theme picker |
| `QrScanActivity` | Camera QR scanner |
| `AutoScanActivity` | Auto-scan interval configuration |
| `PermissionsCenterActivity` | Permissions management |
| `AddressBookActivity` | Address book |
| `AddressBookEntryActivity` | Add / edit address entry |
| `DappOriginsActivity` | dApp origin allowlist |
| `AboutActivity` | App info |

**Foreground services**: `TxForegroundService` (send / encrypt / decrypt /
stealth / token_send), `AutoScanService` (periodic balance refresh),
`StealthClaimService` (stealth output claiming).

## Project Structure

```
android/
├── app/
│   ├── src/main/
│   │   ├── java/com/octopus/wallet/   # Java source
│   │   ├── cpp/                     # Native C++ source
│   │   ├── res/                     # Layouts, drawables, values
│   │   └── AndroidManifest.xml
│   ├── build.gradle
│   └── proguard-rules.pro
├── build.gradle                     # Project-level config
├── settings.gradle
├── gradle.properties
├── scripts/                         # Build, install, sign scripts
└── tools/                           # Launcher icon generation
```

## Native C++ Layer

All cryptographic operations are implemented in C++ and exposed to Java through
31 JNI functions in `octra_jni.cpp`:

| Module | Responsibility |
|--------|---------------|
| `wallet.hpp/.cpp` | Create, import (private key or BIP-39 mnemonic with designated HD derivation v1/v2 version), load, save, change PIN, address derivation |
| `crypto_utils.hpp/.cpp` | SHA-256, Base64, Base58, PBKDF2, AES-GCM encrypt/decrypt, `secure_zero`, `try_mlock` |
| `tx_builder.hpp/.cpp` | Canonical JSON serialization, Ed25519 signing (standard and generic smart contract transaction calls), transaction hashing |
| `pvac_bridge.hpp` | PVAC FHE: keygen, encrypt, decrypt, `get_balance`, ciphertext subtraction, Pedersen commit |
| `stealth.hpp/.cpp` | Curve25519 ECDH, stealth tag/claim-secret/claim-pub derivation, Ed25519→Curve25519 conversion |
| `tweetnacl.c/.h` | Ed25519 signatures, Curve25519 scalar multiplication |
| `randombytes.c` | Secure random byte generation (`/dev/urandom`) |

## Local Database (Room)

| Table | Purpose |
|-------|---------|
| `tx_history` | Full transaction history per wallet (UNIQUE on wallet_id + hash) |
| `token_snapshot` | Dashboard token snapshot with timestamp for instant offline restore |

## Build Instructions

### Quick Build

```bash
cd android
./scripts/build-apk.sh          # Debug APK
./scripts/build-apk.sh release  # Release APK
```

The script auto-detects Java 17, bootstraps the Android SDK if missing, and
installs required components (`platforms;android-35`, `build-tools;35.0.0`,
`cmake;3.22.1`, `ndk;27.3.13750724`).

Output files:
- `octra_wallet-debug.apk`
- `octra_wallet-release.apk` (signed) or `octra_wallet-release-unsigned.apk`

### Signed Release Build

1. Generate a keystore (one-time):
```bash
keytool -genkeypair -v -keystore release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias octra-wallet
```

2. Create `keystore.properties`:
```properties
storeFile=release-key.jks
storePassword=your_keystore_password
keyAlias=octra-wallet
keyPassword=your_key_password
```

3. Build:
```bash
./scripts/build-apk.sh release
```

### Android Studio

1. Open Android Studio → **Open an existing project** → select `android/`.
2. Wait for Gradle sync.
3. **Build → Make Project**.

### Gradle

```bash
./gradlew assembleDebug    # Debug
./gradlew assembleRelease  # Release
```

### GitHub Actions

The APK is built automatically on every push to main/master. To enable signed
releases, add these repository secrets:

- `RELEASE_KEYSTORE_BASE64`
- `KEYSTORE_PASSWORD`
- `KEY_ALIAS`
- `KEY_PASSWORD`

## Install

```bash
adb install octra_wallet-debug.apk
```

## RPC Methods

| Method | Purpose |
|--------|---------|
| `octra_balance` | Public balance + nonce |
| `octra_encryptedBalance` | Authenticated encrypted balance cipher |
| `octra_transactionsByAddress` | Paginated transaction history |
| `octra_transaction` | Single transaction lookup |
| `octra_submit` | Broadcast signed transaction |
| `octra_recommendedFee` | Fee recommendation |
| `octra_pvacPubkey` | Query PVAC public key |
| `octra_registerPvacPubkey` | Register PVAC key on-chain |
| `octra_viewPubkey` | Query view public key |
| `octra_registerViewPubkey` | Register view key on-chain |
| `octra_stealthOutputs` | List stealth outputs for scanning |
| `octra_listContracts` | Enumerate deployed contracts |
| `octra_contractStorage` | Read contract storage key |
| `octra_contractView` | Read-only contract call |
| `octra_compileAssembly` | Compile assembly source |
| `octra_compileAml` | Compile AML source |
| `octra_computeContractAddress` | Deterministic contract address |
| `octra_vmContract` | VM-level contract info |
| `octra_contractReceipt` | Contract execution receipt |
| `octra_contractAbi` | Fetch contract ABI |
| `octra_saveAbi` | Upload contract ABI |
| `octra_verifyContract` | Submit source for verification |

## dApp Provider API (`window.octra` / `window.wallet`)

The in-app browser injects a provider (no local server required). Sensitive
methods always ask the user first; unsupported sign-only / FHE-private
methods are refused explicitly, never simulated.

| Method | Description |
|--------|-------------|
| `connect` / `octra_requestAccounts` / `wallet_connect` | Approval-gated connect, returns address(es) |
| `octra_accounts` / `wallet_getAccounts` / `wallet_getAddress` | Connected address (session required) |
| `octra_chainId` / `wallet_getChainId` | Active chain id |
| `octra_networkInfo` / `wallet_getNetworkInfo` | Network id, name, RPC + explorer URLs |
| `octra_permissions` / `wallet_getPermissions` | Granted scopes |
| `octra_getBalance` / `wallet_getBalance` | Node balance for the connected address |
| `octra_getEncryptedBalance` | Authenticated PVAC cipher for the active wallet |
| `getPublicKey` | Base64 Ed25519 public key |
| `octra_sendTransaction` | Approval-gated, natively signed OCT send |
| `octra_callContract` / `octra_sendContractTransaction` | Approval-gated, natively signed contract call |
| `octra_callView` | Read-only contract view (no approval) |
| `octra_switchNetwork` | Honest answer: this wallet follows its configured node |
| `disconnect` / `wallet_disconnect` | End the origin session |
| `wallet_ping` | Liveness probe (no wallet access) |

## Dependencies

- **TweetNaCl** — Ed25519 signatures and X25519 key exchange
- **nlohmann/json** — JSON parsing (C++)
- **OkHttp** — HTTP client for RPC calls
- **Room** — Local SQLite database
- **AndroidX Biometric** — Fingerprint / face authentication
- **ZXing** — QR code scanning

## License

Released under the GPL license with OpenSSL exception. See `COPYING` for details.
