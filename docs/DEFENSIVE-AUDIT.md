# Defensive Audit — BlueWallet

Standar kerja: 8 aturan defensive programming (pemetaan kasus dulu,
guard clauses + pasangan tiap cabang, validasi input, try/catch informatif
tanpa `catch` kosong, tanpa jalur mati, null/async eksplisit, tabel bukti +
test per cabang, asumsi eksplisit).

> Catatan gaya: "tiap `if` berpasangan" diterapkan sebagai guard-clause +
> early-return dengan aliran normal yang terdokumentasi di tabel bukti
> (bukan `else` harfiah yang mengaburkan).

## Asumsi default (fail-safe)

| # | Asumsi |
|---|---|
| A1 | Ragu → tolak dengan pesan jelas, jangan lanjut diam-diam |
| A2 | Timeout RPC ikut pola existing (30 dtk) kecuali diputuskan lain |
| A3 | Uang = integer microcoins; tidak ada floating point di dekat uang |
| A4 | Kunci privat tidak pernah keluar native memory / secure storage |
| A5 | Endpoint lokal yang gagal → JSON error + HTTP status yang tepat |

## Inventaris modul × risiko × fase

### KRITIS — jalur uang, kunci, konsensus (Fase 1)

| Area | android-native | flutter | Status |
|---|---|---|---|
| Tx build/sign/submit + canonical JSON | `cpp/tx_builder.*`, `octra_jni.cpp` (sign*), `WalletRepository.submitTx` | `crypto_service.dart` (buildSigned*), `native_crypto.dart`, `octra_ffi.cpp` | Belum diaudit |
| Nonce handling | `BaseTxActivity`, `WalletRepository.fetchBalance` | `wallet_service.dart` refresh/`_currentNonce` | Belum diaudit |
| Fee oracle + fallback | `OctraRpcClient.fetchFee*`, `WalletRepository.fetchRecommendedOu` | `network_service.dart`, `wallet_service.dart` fetchFee* | Belum diaudit |
| key_switch | `WalletRepository.submitKeySwitch` | `wallet_service.dart` submitKeySwitch | Belum diaudit |
| Encrypt/decrypt/stealth balance | `signEncryptTx/signDecryptTx/signStealthSendTx` (JNI), `Encrypt/DecryptBalanceActivity`, `StealthSendActivity` | `crypto_service.dart`, `encrypt/decrypt_balance_screen.dart`, `stealth_send_screen.dart` | Belum diaudit |
| PVAC decrypt + ECDH/stealth scan | `cpp/stealth.*`, `pvac_bridge.hpp`, `StealthScanActivity`, `StealthClaimService` | `native_crypto.dart` ecdh/stealth, `stealth_scan_screen.dart` | Belum diaudit |
| RPC client (timeout/retry/error) | `OctraRpcClient.java`, `cpp/rpc_client.*` | `network_service.dart` RpcClient + `wallet_service.dart` _rpc | Belum diaudit |
| Wallet create/import/HD/mnemonic | `cpp/wallet.*`, `AddWalletActivity`, `Bip39.java`, `MnemonicStore`, `DeriveChildWalletActivity` | `mnemonic_service.dart`, `add/mnemonic/derive_child_wallet_screen.dart`, `bip39_wordlist.dart` | Belum diaudit |
| Key storage + PIN | `OctraNative` (mlock/zero), `PinStore`, `WalletKeysLoader`, `WalletPinVerifier`, `UnlockActivity`, `ChangePinActivity` | `pin_service.dart`, `flutter_secure_storage` via `wallet_service.dart`, `pin_entry_screen.dart`, `change_pin_screen.dart` | Belum diaudit |

### TINGGI — bridge, server, jaringan, data (Fase 2)

| Area | android-native | flutter | Status |
|---|---|---|---|
| Local server 27 endpoint | `LocalWebServerService.java` | `local_web_server_service.dart` | Belum diaudit |
| dApp bridge + approval | `DappBrowserActivity` (+bridge), `DeepLinkBridgeActivity`, `TxRequestManager`, `DappOriginStore` | `dapp_browser_screen.dart`, `confirm_contract_call_screen.dart`, `deep_link_service.dart` | Belum diaudit |
| oct:// render path | `DappBrowserActivity` + `OctUrlParser.java` ✅ teruji (17 test) | `dapp_browser_screen.dart` `_loadOctUrl` | Parser teruji; render belum diaudit |
| Deep link intent | `AndroidManifest.xml` (octra://, octra-wallet://) | `deep_link_service.dart`, `app_router.dart` | Belum diaudit |
| Network profiles + URL | `UrlSecurityValidator.java` ✅ teruji, `NodeProfileStore`, `NetworkSettingsActivity` | `network_service.dart` ✅ migrasi teruji parsial | Validator teruji; store belum |
| DB + cache + migrasi | `OctraDatabase`, `TxHistoryDao/Entity`, `TokenSnapshot*`, `TxTaskStore`, `WalletProfileStore` | `database_service.dart`, models/* | Belum diaudit |

### SEDANG — layanan latar + alur bantu (Fase 3)

| Area | android-native | flutter | Status |
|---|---|---|---|
| Polling/autoscan/claim | `AutoScanService/Worker/Activity`, `TxForegroundService`, `StealthClaimService`, `StealthTaskManager` | `polling/background_polling_service.dart`, `auto_scan_screen.dart`, stealth tasks screens | Belum diaudit |
| History/token loading | `MainActivity` tokens, `TransactionsManagerActivity`, `HistoryDetailActivity` | `history_tab.dart`, `transactions_manager_screen.dart`, `history_detail_screen.dart` | Belum diaudit |
| QR scan | `QrScanActivity` (CameraX+MLKit+zxing) | `qr_scan_screen.dart` | Belum diaudit |
| Biometrik/session lock | `UnlockActivity` (BiometricPrompt) | `biometric_service.dart`, `session_lock_screen.dart`, `biometric_settings_screen.dart` | Belum diaudit |
| Export/kunci terlihat | `ExportWalletsActivity`, `ViewKeysActivity`, `ConfirmDeleteWalletActivity` | `export/view_keys/wallets_screen.dart`, `confirm_action_screen.dart` | Belum diaudit |
| Setup/onboarding | `SetupActivity`, `WalletFilePinActivity`, `WalletsMenuActivity` | `setup_screen.dart`, `startup_screen.dart` | Belum diaudit |
| Tor proxy, data usage, polling settings | `TorProxyStore/SettingsActivity`, `DataUsage*`, `TxSettingsActivity`, `PollingSettingsStore` | `tor_proxy_service.dart`, `data_usage_service.dart`, settings screens | Belum diaudit |
| Permissions/dApp origins | `PermissionManager`, `PermissionsCenterActivity`, `DappOriginsActivity` | `permissions_center_screen.dart`, `dapp_origins_screen.dart` | Belum diaudit |

### RENDAH — presentasi (Fase 3 akhir, bila sempat)

Theme (10 vs 11 palet), About, dashboard/animasi (`BalanceAnimator`), widget generik,
`ErrorDisplayHelper`, `AppErrorCode`, receive screen + QR generate.

## Cara verifikasi per fase (wajib)

1. Tabel `Skenario → Lokasi penanganan` di PR (valid, kosong, invalid,
   batas, network/timeout, akses ditolak).
2. Test per cabang: JVM (`app/src/test`, tanpa emulator) + Dart
   (`flutter test`); E2E bila menyentuh UI.
3. CI hijau: `analyze` fatal-infos, `lintDebug` 0-error, Spotless,
   `testDebugUnitTest`, `flutter test`, debug build dua app.
