# Blue Wallet — Octra Ecosystem

A comprehensive wallet ecosystem for the Octra blockchain, featuring **Android**, **Flutter**, **Chrome Extension**, **WebCLI**, and **dApps**.

## Project Structure

```
blue_wallet/
├── android/           # Native Android wallet (Java + C++)
├── flutter/           # Cross-platform Flutter wallet
├── webcli/            # Web-based CLI wallet with local server
├── dapps/             # Decentralized applications
│   ├── simple-dex/    # DEX with AMM for token swaps
│   ├── sdk/           # JavaScript SDK for Octra integration
│   ├── extensions/    # Chrome extension wallet
│   └── shared/        # Shared utilities and deployment tools
└── docs/              # Documentation (if needed)
```

## Quick Start

### 1. Octra Wallet — Android

**Requirements:**
- Android Studio Koala+
- Android SDK 35, NDK r27+
- CMake 3.22.1+, Java 17

**Build:**
```bash
cd android
./scripts/build-apk.sh          # Debug
./scripts/build-apk.sh release  # Release
```

**Features:**
- Ed25519 wallet management (create, import, export)
- Public + encrypted (PVAC) balance support
- Stealth transactions with ECDH key exchange
- Token discovery and transfers
- Smart contract interaction (deploy, call, view)
- PIN + biometric authentication
- 10 theme palettes
- JSON-RPC 2.0 with multi-network profiles

[Full Android Docs →](android/README.md)

---

### 2. Octra Wallet — Flutter

**Requirements:**
- Flutter 3.x stable, Dart 3.x
- Android SDK 35 (Android), Xcode 15+ (iOS/macOS)
- CMake 3.22+ (Linux/Windows)

**Build:**
```bash
cd flutter
flutter run                     # Debug
flutter build apk --release     # Release
```

**Features:**
- Cross-platform: Android, iOS, Linux, Windows, macOS
- Native crypto via FFI (`liboctra_native.so`)
- 11 theme palettes (Zenith default)
- 37 screens including DevTools for contract interaction
- SQLite for offline caching (transactions, tokens, balances)
- PVAC FHE encryption/decryption
- Stealth transaction scanning and claiming

[Full Flutter Docs →](flutter/README.md)

---

### 3. WebCLI — Web-Based Wallet

**Requirements:**
- C++17 compiler (GCC/Clang)
- OpenSSL 3.x
- libpvac (from `pvac/` directory)

**Build & Run:**
```bash
cd webcli
./setup.sh && ./octra_wallet    # Linux/macOS
setup.bat && octra_wallet.exe   # Windows
# Open http://127.0.0.1:8420
```

**Features:**
- Local HTTP server with web UI
- Wallet encryption with 6-digit PIN
- Send OCT, encrypt/decrypt balances
- Stealth transactions
- Contract deployment and interaction
- Zero third-party dependencies (custom implementation)

[Full WebCLI Docs →](webcli/README.md)

---

### 4. Chrome Extension Wallet

**Installation:**
1. Open `chrome://extensions/` → Enable "Developer mode"
2. Click "Load unpacked" → Select `extensions/` folder

**DApp Integration:**
```javascript
if (window.octra) {
  const { address } = await window.octra.connect();
  const balance = await window.octra.getBalance();
  await window.octra.sendTransaction('oct...', '1000000');
  await window.octra.callContract('oct_contract', 'transfer', ['oct_recipient', '1000000']);
}
```

**Features:**
- AES-256-GCM encryption with PBKDF2 (600k iterations)
- `window.octra` provider injection
- DApp permission management
- Custom RPC endpoint support

[Full Extension Docs →](dapps/extensions/README.md)

---

### 5. Simple DEX — Decentralized Exchange

**Requirements:**
- Node.js 18+
- Octra DevNet private key

**Setup:**
```bash
cd dapps/simple-dex
npm install
cp .env.example .env.local
# Edit .env.local and set OCTRA_PRIVATE_KEY
npm run setup
npm run deploy        # Deploy AMM + TokenFactory contracts
npm run dev           # Start dev server at localhost:3000
```

**Features:**
- **Swap**: Exchange OCT ↔ OCS01 tokens (0.3% fee)
- **Liquidity Pools**: Add/remove liquidity, earn fees
- **Token Creation**: Deploy OCS01 fungible tokens
- **Next.js 15 + React 19** with modern UI
- Environment-based configuration

**Environment Variables:**
```bash
# Network
NEXT_PUBLIC_OCTRA_NETWORK=devnet
NEXT_PUBLIC_OCTRA_RPC_URL=https://devnet.octra.org/rpc

# Wallet (DevNet test key)
OCTRA_PRIVATE_KEY=YIrIfYs+T1Y5FUhaKDkDFvXPebgR5C5BEkB1HqX9GB4=

# Contracts (auto-updated after deployment)
NEXT_PUBLIC_AMM_CONTRACT_ADDRESS=oct...
NEXT_PUBLIC_TOKEN_FACTORY_ADDRESS=oct...
```

[Full DEX Docs →](dapps/simple-dex/README.md)

---

### 6. @octra/sdk — JavaScript SDK

**Installation:**
```bash
npm install @octra/sdk
# or for local development
npm install ../dapps/sdk
```

**Usage:**
```javascript
import { OctraProvider, OctraWallet, OctraContract, OCS01Token } from '@octra/sdk';

const provider = new OctraProvider(NETWORKS.devnet.rpcUrl);
const wallet = OctraWallet.create();
const balance = await provider.getBalance(wallet.address);

const token = new OCS01Token('oct1token...', provider, wallet);
const supply = await token.totalSupply();
```

**Features:**
- Ed25519 wallet management
- Octra JSON-RPC client with retry logic
- Mobile wallet transport (deep links, in-app browser)
- Protocol wrappers: OCS01 tokens, swap pools, Fuji bridge
- Contract deployment and interaction helpers

[Full SDK Docs →](dapps/sdk/README.md)

---

## Architecture Overview

### Native Crypto Layer

All cryptographic operations are performed in **C++** via native libraries:

| Platform | Library | Crypto Functions |
|----------|---------|------------------|
| Android | `liboctra_wallet_native.so` | Ed25519, AES-GCM, PBKDF2, PVAC FHE |
| Flutter | `liboctra_native.so` | Ed25519, Curve25519, PVAC FHE |
| WebCLI | Built-in | Ed25519, TweetNaCl, PVAC |

**Key Modules:**
- `wallet.hpp/.cpp` — Key generation, import/export, address derivation
- `crypto_utils.hpp/.cpp` — SHA-256, Base64, AES-GCM, secure memory zeroing
- `tx_builder.hpp/.cpp` — Canonical JSON serialization, Ed25519 signing
- `pvac_bridge.hpp` — PVAC FHE encryption/decryption, Pedersen commitments
- `stealth.hpp/.cpp` — ECDH key exchange, stealth tag derivation
- `tweetnacl.c/.h` — Ed25519 signatures, Curve25519 operations

### Security Model

| Feature | Implementation |
|---------|----------------|
| **Key Storage** | Encrypted with AES-256-GCM + PBKDF2 (100k–600k iterations) |
| **PIN Protection** | SHA-256 hashed PIN in platform secure storage |
| **Biometric Auth** | Android Keystore / iOS Keychain / libsecret |
| **Memory Safety** | `secure_zero()` wipes buffers, `try_mlock()` prevents swap |
| **Session Lock** | Auto-lock on background/inactivity |
| **Root Detection** | Emulator and root checks (Android) |

### RPC Methods

| Method | Purpose |
|--------|---------|
| `octra_balance` | Public balance + nonce |
| `octra_encryptedBalance` | PVAC encrypted balance (authenticated) |
| `octra_transactionsByAddress` | Paginated transaction history |
| `octra_submit` | Broadcast signed transaction |
| `octra_recommendedFee` | Fee recommendation |
| `octra_listContracts` | Enumerate deployed contracts |
| `octra_contractView` | Read-only contract call |
| `octra_contractInfo` | Contract ABI + metadata |
| `octra_pvacPubkey` / `octra_registerPvacPubkey` | PVAC key lifecycle |
| `octra_viewPubkey` / `octra_registerViewPubkey` | View key lifecycle |
| `octra_stealthOutputs` | Stealth output scanning |

---

## Smart Contracts (AML Language)

### AML Syntax Overview

```aml
// SPDX-License-Identifier: MIT
contract MyContract {
  state {
    owner: address
    balances: map[address]int
  }

  event Transfer(from: address, to: address, amount: int)

  constructor() {
    self.owner = origin
  }

  view fn balance_of(account: address): int {
    return self.balances[account]
  }

  fn transfer(to: address, amount: int): bool {
    require(is_address(to), "invalid address")
    require(amount > 0, "zero amount")
    let bal = self.balances[caller]
    require(bal >= amount, "insufficient balance")
    self.balances[caller] = bal - amount
    self.balances[to] = self.balances[to] + amount
    emit Transfer(caller, to, amount)
    return true
  }
}
```

### Token Standards

| Standard | Description | AML Contract |
|----------|-------------|--------------|
| **OCS01** | Fungible Token (ERC-20 equivalent) | `contracts/token/OCS01/OCS01.aml` |
| **OCS02** | Non-Fungible Token (ERC-721) | `contracts/token/OCS02/OCS02.aml` |
| **OCS03** | Multi-Token (ERC-1155) | `contracts/token/OCS03/OCS03.aml` |

### Security Patterns

**Reentrancy Guard:**
```aml
state { status: int }  // 1=unlocked, 2=locked

fn withdraw(amount: int) {
  require(self.status != 2, "ReentrancyGuard: reentrant call")
  self.status = 2  // Lock
  // ... checks and effects ...
  transfer(caller, amount)  // Interaction last
  self.status = 1  // Unlock
}
```

**Access Control:**
```aml
// Ownable pattern
require(caller == self.owner, "ContractName: not owner")

// Role-based pattern
require(self.role_members["minter"][caller] == true, "missing role")
```

[Full AML Language Reference →](skill-dev.md#octra-aml-smart-contract-language)

---

## Development Guidelines

### Build Environments — Dependency Caching

**Philosophy:** Download Once, Reuse Forever

#### Linux/macOS
```bash
# Global caches (persist across projects)
export GRADLE_USER_HOME="$HOME/.gradle"
export PUB_CACHE="$HOME/.pub-cache"
export PIP_CACHE_DIR="$HOME/.cache/pip"
export npm_config_cache="$HOME/.npm"
export CARGO_HOME="$HOME/.cargo"

# Gradle optimization
echo "org.gradle.daemon=true" >> ~/.gradle/gradle.properties
echo "org.gradle.parallel=true" >> ~/.gradle/gradle.properties
echo "org.gradle.caching=true" >> ~/.gradle/gradle.properties
```

#### Windows (PowerShell)
```powershell
$env:GRADLE_USER_HOME = "$HOME\.gradle"
$env:PUB_CACHE = "$HOME\.pub-cache"
$env:npm_config_cache = "$HOME\.npm"
```

#### Use pnpm for Node.js
```bash
npm install -g pnpm
pnpm config set store-dir ~/.pnpm-store  # Global hard-link store
```

### Testing Checklist

Before production deployment:

- [ ] All environment variables validated
- [ ] Contracts deployed and verified
- [ ] Wallet connects without errors
- [ ] Token creation/transfer works
- [ ] Liquidity pools functional (add/remove)
- [ ] Swaps execute correctly (both directions)
- [ ] Balances update in real-time
- [ ] Error messages are user-friendly
- [ ] Transaction explorer links work
- [ ] Security audit completed (reentrancy, access control, integer safety)

---

## Network Configuration

| Network | RPC URL | Explorer | Purpose |
|---------|---------|----------|---------|
| **DevNet** | `https://devnet.octra.org/rpc` | `https://devnet.octrascan.io` | Development & testing |
| **Mainnet** | _TBD_ | _TBD_ | Production (not yet live) |

**Default DevNet Private Key (for testing):**
```
OCTRA_PRIVATE_KEY=YIrIfYs+T1Y5FUhaKDkDFvXPebgR5C5BEkB1HqX9GB4=
```
⚠️ **Never use this key on mainnet. Generate your own for production.**

---

## Security Considerations

### For Developers

1. **Never hardcode private keys** — Use environment variables or secure vaults
2. **Validate all inputs** — Addresses, amounts, contract parameters
3. **Use reentrancy guards** — Protect withdraw/deposit functions
4. **Follow CEI pattern** — Checks → Effects → Interactions
5. **Test on DevNet first** — Never deploy untested code to mainnet
6. **Audit smart contracts** — Use the AML Security Audit Checklist

### For Users

1. **Backup private keys** — Store offline in multiple secure locations
2. **Use strong PINs** — Minimum 6 digits, avoid patterns
3. **Enable biometric auth** — When available on your device
4. **Verify contract addresses** — Double-check before interacting
5. **Beware of phishing** — Only use official wallet apps and dApps

---

## Troubleshooting

### "OCTRA_PRIVATE_KEY not set"

```bash
cd dapps/simple-dex
cp .env.example .env.local
# Edit .env.local and set your private key
```

### "Contract not configured"

```bash
npm run deploy        # Deploy contracts
npm run deploy:verify # Verify deployment
```

### Build errors (Android/Flutter)

```bash
# Clear caches
rm -rf node_modules .next build
npm install

# Rebuild native libraries
cd android && ./scripts/build-apk.sh clean
```

### Transaction timeout

- Increase `NEXT_PUBLIC_TX_TIMEOUT` in `.env.local`
- Check DevNet status on scanner
- Verify gas settings are sufficient

---

## Resources

- [Octra Documentation](https://docs.octra.org/)
- [DevNet Scanner](https://devnet.octrascan.io/)
- [Next.js 15 Docs](https://nextjs.org/docs)
- [Flutter Docs](https://flutter.dev)
- [Android Developer Guide](https://developer.android.com)

---

## License

- **Wallet Apps (Android, Flutter, WebCLI, Extension)**: GPL with OpenSSL exception
- **SDK & dApps**: MIT
- **Smart Contracts**: MIT

---

**Disclaimer**: This software is for educational and testing purposes. Use on mainnet at your own risk. The authors are not responsible for any financial losses.
