# Octra Wallet Android - Feature Documentation

## Overview

Octra Wallet is a native Android cryptocurrency wallet application for the Octra blockchain. It provides comprehensive wallet management, transaction capabilities, privacy features, and DApp integration.

---

## 1. Wallet Management

### 1.1 Wallet Creation & Import
- **Create New Wallet**: Generate a new wallet with a 6-digit PIN
- **Import Wallet**: Import existing wallet using private key
- **PIN Protection**: 6-digit PIN for wallet security
- **Default PIN Storage**: Optional default PIN for quick access

### 1.2 Multiple Wallet Support
- **Wallet Selector**: Switch between multiple wallets
- **Wallet Profiles**: Each wallet has its own directory and settings
- **Wallet List**: View all created/imported wallets
- **Derive Child Wallets**: Create child wallets from master wallet

### 1.3 Wallet Operations
- **Export Wallet**: Export wallet data
- **View Keys**: View public and private keys
- **Delete Wallet**: Remove wallet with confirmation
- **Wallet File PIN**: Additional PIN for wallet file access

---

## 2. Balance & Token Management

### 2.1 Native OCT Balance
- **Public Balance**: View spendable OCT balance
- **Encrypted Balance**: View encrypted OCT balance
- **Total Balance**: Combined view of all balances
- **Balance Formatting**: Human-readable amount display (6 decimals)

### 2.2 Contract Tokens
- **Token List**: Display all held contract tokens
- **Token Details**: Symbol, name, balance type, address, decimals
- **Token Search**: Filter tokens by name or symbol
- **Token Balance Fetching**: Parallel token balance queries (8 threads)

### 2.3 Balance Operations
- **Encrypt Balance**: Convert public OCT to encrypted OCT
- **Decrypt Balance**: Convert encrypted OCT to public OCT
- **Custom Gas Fees**: Configurable transaction fees
- **Recommended Fees**: Auto-suggested fees based on operation type

---

## 3. Transactions

### 3.1 Standard Send
- **Send OCT**: Transfer OCT to any address
- **Address Validation**: Validates `oct` prefix and 47-character format
- **Amount Input**: Decimal input with automatic raw conversion
- **Message/Memo**: Optional transaction message
- **Amount Preview**: Real-time amount display
- **Confirmation Dialog**: Transaction details before sending

### 3.2 Token Transfers
- **Send Tokens**: Transfer contract tokens
- **Token Mode**: Automatic detection of token transfers
- **Decimal Handling**: Proper decimal conversion for tokens
- **Token Metadata**: Symbol and name display

### 3.3 Transaction Processing
- **Foreground Service**: Background transaction processing
- **Transaction Progress**: Real-time status updates
- **Pending Transactions**: Track unconfirmed transactions
- **Transaction Manager**: View and manage all pending transactions
- **Auto Refresh**: Silent balance refresh after transactions

### 3.4 Transaction History
- **History List**: Paginated transaction history
- **History Details**: Full transaction information
- **History Sorting**: Sort by timestamp or block height
- **History Caching**: Offline access via SharedPreferences and Room DB
- **Pull to Refresh**: Swipe to refresh history
- **Load More**: Infinite scroll pagination

---

## 4. Stealth Features (Privacy)

### 4.1 Stealth Send
- **Privacy Transactions**: Send OCT with enhanced privacy
- **Stealth Queue**: Queue stealth tasks for processing
- **Custom Fees**: Configurable stealth transaction fees
- **Task Management**: View and manage stealth tasks

### 4.2 Stealth Scan
- **Output Discovery**: Scan for claimable stealth outputs
- **Output List**: Display all available outputs
- **Output Selection**: Select outputs to claim
- **Batch Claim**: Claim multiple outputs at once

### 4.3 Stealth Claim
- **Background Claiming**: Claim outputs via foreground service
- **Claim Status**: Track claim progress
- **Claim Notifications**: Status updates for claims

---

## 5. DApp Browser

### 5.1 In-App Browser
- **WebView Browser**: Full-featured web browser
- **URL Navigation**: Enter and navigate to URLs
- **Progress Indicator**: Page loading progress
- **Back Navigation**: Browser history support

### 5.2 Wallet Provider
- **window.octra**: Injected wallet provider
- **Connect Request**: DApp connection approval dialog
- **Origin Management**: Allow/block DApp origins
- **Chain ID**: Network identification (mainnet/devnet)

### 5.3 DApp Methods
- **octra_accounts**: Get connected account address
- **octra_chainId**: Get current chain ID
- **octra_getBalance**: Fetch wallet balance
- **octra_sendTransaction**: Sign and send transactions
- **octra_callContract**: Execute contract calls
- **octra_callView**: Read-only contract queries

### 5.4 Security
- **Connection Approval**: User confirmation for DApp connections
- **Transaction Confirmation**: Approval dialog for all transactions
- **Origin Validation**: Verify DApp origins before interaction

---

## 6. Address Book

### 6.1 Address Management
- **Save Addresses**: Store frequently used addresses
- **Edit Labels**: Customize address labels
- **Delete Addresses**: Remove saved addresses
- **Search Addresses**: Filter by label or address

### 6.2 Integration
- **Pick Mode**: Select address from book when sending
- **Copy to Clipboard**: One-tap address copying
- **Auto-clear Clipboard**: Security feature (30-second timeout)

---

## 7. Network Management

### 7.1 Network Profiles
- **Default Network**: Pre-configured Octra network
- **Custom Networks**: Add custom RPC endpoints
- **Network Switching**: Change active network
- **Explorer URL**: Block explorer integration

### 7.2 Configuration
- **RPC URL**: Node endpoint configuration
- **Explorer URL**: Block explorer URL
- **Network Security**: HTTPS enforcement options

---

## 8. Security Features

### 8.1 Authentication
- **PIN Protection**: 6-digit numeric PIN
- **PIN Change**: Update wallet PIN
- **Session Lock**: Auto-lock after inactivity
- **Session Timeout**: Configurable timeout duration
- **Biometric Support**: Fingerprint/face authentication (via system)

### 8.2 Data Protection
- **Screenshot Prevention**: FLAG_SECURE on all screens
- **Clipboard Auto-clear**: Clear clipboard after 30 seconds
- **Encrypted Storage**: Secure wallet file storage
- **No Backup**: Disabled Android backup for security

### 8.3 Transaction Security
- **Confirmation Dialogs**: All transactions require confirmation
- **Address Validation**: Format and prefix validation
- **Amount Validation**: Prevent invalid amounts
- **Fee Validation**: Ensure positive fee values

---

## 9. Theme & Customization

### 9.1 Available Themes
- **Zenith**: Minimal theme (default)
- **Moonbloom**: Dark theme
- **Frostline**: Cool blue theme
- **Signal**: Vibrant theme
- **NightPulse**: Dark pulse theme
- **ObsidianGrid**: Dark grid theme
- **NeonForge**: Dark neon theme
- **IvoryCircuit**: Light circuit theme
- **SolarPaper**: Light paper theme
- **MistTerminal**: Light terminal theme

### 9.2 Theme Features
- **Instant Switch**: Apply themes without restart
- **Theme Persistence**: Remember selected theme
- **System Integration**: Respects system dark mode

---

## 10. QR Code Features

### 10.1 QR Scanning
- **Camera Scan**: Scan QR codes using device camera
- **Address Extraction**: Extract addresses from QR codes
- **Deep Link Support**: Parse QR deep links

### 10.2 Deep Links
- **octra://send**: Pre-fill send form
  - Format: `octra://send?to=<address>&amount=<value>`
- **octra-wallet://**: External browser bridge
- **Intent Handling**: Process deep links from other apps

---

## 11. Auto Scan

### 11.1 Background Scanning
- **Configurable Interval**: Set scan frequency (minutes)
- **Foreground Service**: Reliable background operation
- **Balance Refresh**: Auto-update balances
- **Manual Control**: Enable/disable scanning

### 11.2 Notifications
- **Scan Status**: Background scan notifications
- **Transaction Alerts**: New transaction notifications
- **Permission Request**: Notification permission (Android 13+)

---

## 12. Caching & Offline Support

### 12.1 Transaction Cache
- **SharedPreferences**: Quick access cache
- **Room Database**: Persistent storage
- **Offline History**: View cached transactions offline
- **Cache Sync**: Automatic cache updates

### 12.2 Token Cache
- **Token Snapshots**: Cache token balances
- **Balance Cache**: Store balance information
- **Quick Load**: Fast initial load from cache

---

## 13. User Interface

### 13.1 Navigation
- **Bottom Navigation**: Dashboard, History, Settings tabs
- **Toolbar Navigation**: Back button support
- **Deep Navigation**: Multi-level screen hierarchy

### 13.2 Dashboard
- **Balance Display**: Total, public, and encrypted balances
- **Token List**: Scrollable token list
- **Quick Actions**: Send and receive buttons
- **Wallet Selector**: Dropdown wallet switcher
- **Pull to Refresh**: Swipe to refresh data

### 13.3 History View
- **Transaction List**: Chronological transaction list
- **Transaction Icons**: Direction indicators (sent/received)
- **Status Badges**: Confirmed, pending, rejected
- **Scroll to Top**: Quick return to recent transactions

### 13.4 Settings
- **Settings Menu**: Organized settings categories
- **Quick Actions**: Easy access to common features
- **About Screen**: App version and information

---

## 14. Native Integration

### 14.1 Native Library
- **JNI Bridge**: Java-Native Interface integration
- **C++ Core**: Native cryptographic operations
- **Performance**: Optimized transaction building
- **Security**: Secure key management

### 14.2 Native Features
- **Wallet Creation**: Native wallet generation
- **Transaction Signing**: Native signature generation
- **Key Derivation**: BIP39 mnemonic support
- **Encryption**: Balance encryption/decryption

---

## 15. Permissions

### 15.1 Required Permissions
- **INTERNET**: Network communication
- **ACCESS_NETWORK_STATE**: Network status monitoring
- **CAMERA**: QR code scanning
- **USE_BIOMETRIC**: Biometric authentication
- **FOREGROUND_SERVICE**: Background services
- **POST_NOTIFICATIONS**: Notification support (Android 13+)

### 15.2 Optional Permissions
- **READ_EXTERNAL_STORAGE**: Import wallet files
- **WRITE_EXTERNAL_STORAGE**: Export wallet files
- **MANAGE_EXTERNAL_STORAGE**: Full storage access

---

## 16. Error Handling

### 16.1 Error Codes
- **AppErrorCode**: Structured error reporting
- **Error Display**: User-friendly error messages
- **Error Logging**: Debug information capture

### 16.2 Error Recovery
- **Retry Mechanisms**: Automatic retry for network errors
- **Graceful Degradation**: Fallback for failed operations
- **User Feedback**: Clear error messages

---

## Technical Stack

- **Language**: Java
- **Architecture**: Activity-based with ViewModels
- **Database**: Room (SQLite)
- **Networking**: Custom RPC client
- **Native**: C++ with JNI
- **UI**: Material Design 3
- **Security**: FLAG_SECURE, encrypted storage