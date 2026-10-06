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
| A6 | Flutter: tanpa auto-retry (retry buta bisa double-submit; pemanggil yang memutuskan). Android: retry hanya untuk error transien, tidak untuk IAE, max 5, interrupt dikembalikan |
| A7 | Cabang `Log.w` Android tidak di-unit-test (stub Log crash di JVM polos); diverifikasi via inspeksi + lint |
| A8 | Race nonce antar-send konkuren tidak diatasi di level repo (node menolak nonce duplikat; error dipermukaan). Serialisasi penuh via antrean nonce = backlog |
| A9 | `submitTx`/send yang tanpa tx_hash = gagal (throw), bukan sukses kosong. Phantom-tx dilarang di kedua app |
| A10 | Kebijakan PIN: tepat 6 digit saat SET (selaras kedua app + verifier). VERIFY tidak menegakkan format (PIN lama tetap bisa diverifikasi). PinStore Android menyimpan PIN mentah karena arsitektur butuh PIN untuk dekripsi wallet — dilindungi EncryptedSharedPreferences + keystore; fallback plaintext kini ber-Log.w |
| A11 | Mnemonic disimpan ternormalisasi (lowercase, spasi tunggal) setelah lolos checksum; validasi import menormalkan dulu sehingga tempelan berantakan tetap diterima bila checksum benar |
| A12 | Server lokal: auth fail-closed (token kosong = tolak semua) + compare constant-time. Input malformed → 400; gagal bisnis/node → 200 + envelope error (kontrak existing dipertahankan). Request tak-tertangani → 500, tak pernah gantung |
| A13 | Approval request: ID unik (UUID / collision-loop), duplikat = throw (bukan overwrite verdict dApp lain); entri basi di-purge (Android TTL 10 mnt); interrupt dikembalikan. DeepLinkService Flutter tanpa konsumen = backlog wiring, bukan dihapus |
| A14 | Room `fallbackToDestructiveMigration` DIPERTAHANKAN sementara: skema v2 belum pernah rilis ke user (histori squash), migrasi eksplisit tanpa skema v1 yang pasti lebih berbahaya (risiko bootloop). Ditinjau ulang sebelum bump versi DB berikutnya |
| A15 | Polling bounds: interval 1 dtk–24 jam, threshold 0–7 hari. UI memvalidasi batas yang sama (tanpa itu setter throw = crash). Threshold 0 = selalu notifikasi |
| A16 | Proxy: host wajib isi, port 1..65535, tipe SOCKS/HTTP (kanonik upper). UI memvalidasi duluan; setter throw + row-tap toast sebagai jaring. Send: recipient tak-kosong + amount > 0 sebelum network (builder tetap validasi ulang) |
| A17 | Render langsung dibatasi 8 MB dua sisi (aset lebih besar via gateway streaming atau pesan jelas). Renderer crash tak lagi membunuh activity (Android dialog reload). E2E browser membuka URL laporan sungguhan |

## Inventaris modul × risiko × fase

### KRITIS — jalur uang, kunci, konsensus (Fase 1)

| Area | android-native | flutter | Status |
|---|---|---|---|
| Tx build/sign/submit + canonical JSON | `cpp/tx_builder.*`, `octra_jni.cpp` (sign*), `WalletRepository.submitTx` | `crypto_service.dart` (buildSigned*), `native_crypto.dart`, `octra_ffi.cpp` | Belum diaudit |
| Nonce handling | `BaseTxActivity`, `WalletRepository.fetchBalance` | `wallet_service.dart` refresh/`_currentNonce` | ✅ Fase 1.2 selesai (pending_nonce + parse + clamp; bukti di bawah) |
| Fee oracle + fallback | `OctraRpcClient.fetchFee*`, `WalletRepository.fetchRecommendedOu` | `network_service.dart`, `wallet_service.dart` fetchFee* | Belum diaudit |
| key_switch | `WalletRepository.submitKeySwitch` | `wallet_service.dart` submitKeySwitch | ✅ submit guard Fase 1.2; migrasi payload+proof penuh butuh uji node (backlog) |
| Encrypt/decrypt/stealth balance | `signEncryptTx/signDecryptTx/signStealthSendTx` (JNI), `Encrypt/DecryptBalanceActivity`, `StealthSendActivity` | `crypto_service.dart`, `encrypt/decrypt_balance_screen.dart`, `stealth_send_screen.dart` | ✅ Fase 1.3 selesai (validasi input; bukti di bawah) |
| PVAC decrypt + ECDH/stealth scan | `cpp/stealth.*`, `pvac_bridge.hpp`, `StealthScanActivity`, `StealthClaimService` | `native_crypto.dart` ecdh/stealth, `stealth_scan_screen.dart` | Belum diaudit |
| RPC client (timeout/retry/error) | `OctraRpcClient.java`, `cpp/rpc_client.*` | `network_service.dart` RpcClient + `wallet_service.dart` _rpc | ✅ Fase 1.1 selesai (dispatch+parse; lihat bukti di bawah) |
| Wallet create/import/HD/mnemonic | `cpp/wallet.*`, `AddWalletActivity`, `Bip39.java`, `MnemonicStore`, `DeriveChildWalletActivity` | `mnemonic_service.dart`, `add/mnemonic/derive_child_wallet_screen.dart`, `bip39_wordlist.dart` | ✅ Fase 1.4 selesai (normalisasi, checksum, path; bukti di bawah) |
| Key storage + PIN | `OctraNative` (mlock/zero), `PinStore`, `WalletKeysLoader`, `WalletPinVerifier`, `UnlockActivity`, `ChangePinActivity` | `pin_service.dart`, secure storage, `pin_entry/change_pin_screen.dart` | ✅ Fase 1.4 selesai (kebijakan 6-digit, hash Flutter; bukti di bawah) |

### TINGGI — bridge, server, jaringan, data (Fase 2)

| Area | android-native | flutter | Status |
|---|---|---|---|
| Local server 27 endpoint | `LocalWebServerService.java` | `local_web_server_service.dart` | ✅ Fase 2.1 selesai (auth + validasi; bukti di bawah) |
| dApp bridge + approval | `DappBrowserActivity` (+bridge), `DeepLinkBridgeActivity`, `TxRequestManager`, `DappOriginStore` | `dapp_browser_screen.dart`, `confirm_contract_call_screen.dart`, `deep_link_service.dart` | ✅ Fase 2.2 selesai (request tracking + origin; bukti di bawah) |
| oct:// render path | `DappBrowserActivity` + `OctUrlParser.java` ✅ teruji (17 test) | `dapp_browser_screen.dart` `_loadOctUrl` | ✅ teruji: `OctUrl` murni + E2E serve (bukti Fase 2.0 di bawah) |
| Deep link intent | `AndroidManifest.xml` (octra://, octra-wallet://) | `deep_link_service.dart`, `app_router.dart` | ✅ Fase 2.2 selesai (parse + startup aman; DeepLinkService tanpa konsumen = backlog) |
| Network profiles + URL | `UrlSecurityValidator.java` ✅ teruji, `NodeProfileStore`, `NetworkSettingsActivity` | `network_service.dart` ✅ migrasi teruji parsial | ✅ Fase 2.3 selesai (null-guard, dedup, default hidup; bukti di bawah) |
| DB + cache + migrasi | `OctraDatabase`, `TxHistoryDao/Entity`, `TokenSnapshot*`, `TxTaskStore`, `WalletProfileStore` | `database_service.dart`, models/* | ✅ Fase 2.3 selesai parsial (parse + TTL + guard; migrasi destruktif = risiko diterima, lihat A14) |

### SEDANG — layanan latar + alur bantu (Fase 3)

| Area | android-native | flutter | Status |
|---|---|---|---|
| Polling/autoscan/claim | `AutoScanService/Worker/Activity`, `TxForegroundService`, `StealthClaimService`, `StealthTaskManager` | `polling/background_polling_service.dart`, `auto_scan_screen.dart`, stealth tasks screens | Belum diaudit |
| History/token loading | `MainActivity` tokens, `TransactionsManagerActivity`, `HistoryDetailActivity` | `history_tab.dart`, `transactions_manager_screen.dart`, `history_detail_screen.dart` | Belum diaudit |
| QR scan | `QrScanActivity` (CameraX+MLKit+zxing) | `qr_scan_screen.dart` | Hasil mentah tervalidasi di send (Fase 1.3); parsing payment-URI = backlog |
| Address book | `AddressBookStore` | `address_book_service.dart`, `address_entry.dart` | ✅ Fase 3.3 selesai (validasi + dedup + load toleran; bukti di bawah) |
| Biometrik/session lock | `UnlockActivity` (BiometricPrompt) | `biometric_service.dart`, `session_lock_screen.dart`, `biometric_settings_screen.dart` | ✅ Fase 3.4 parsial Android (keputusan timeout murni + teruji); Flutter tanpa enforcement = backlog fitur |
| Export/kunci terlihat | `ExportWalletsActivity`, `ViewKeysActivity`, `ConfirmDeleteWalletActivity` | `export/view_keys/wallets_screen.dart`, `confirm_action_screen.dart` | Diinspeksi: PIN-gate + anti-double-tap + proteksi wallet-terakhir OK, tanpa perubahan |
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
4. Cakupan cabang terlapor per PR (Fase 4): tabel JaCoCo + lcov di
   ringkasan job; threshold pengetat menyusul setelah baseline ada.

## Bukti Fase 4 — gate cakupan cabang

| # | Skenario | Penanganan | Test |
|---|---|---|---|
| 1 | Laporan JaCoCo hilang/rusak | parser lapor eksplisit, exit 0 (report-only; threshold belakangan) | fixture sintetis lokal |
| 2 | Laporan lcov hilang/rusak | sama | fixture sintetis lokal |
| 3 | Task report tanpa data exec | `GradleException` eksplisit (tak pernah diam) | CI |
| 4 | Threshold masa depan | belum diaktifkan — didokumentasikan sebagai langkah berikut (baseline dulu) | — |

## Bukti Fase 3.4 — session timeout + format tampil

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | lock nonaktif (≤0) | tak pernah kunci (existing, kini teruji) | — (tanpa enforcement = backlog fitur, bukan hardening) | matriks expiry |
| 2 | belum pernah tercatat | paksa kunci (existing) | — | matriks expiry |
| 3 | tepat di batas / 1ms sebelum | kunci / tidak (existing) | — | boundary tests |
| 4 | jam mundur / menit raksasa | fail-open eksplisit / long anti-overflow | — | skew + MAX_INT tests |
| 5 | desimal token absurd | render mentah, cap 0..36 (dulu: potensi OOM) | sama (dulu: hang/OOM `pow`+`padLeft`) | out-of-range grup dua sisi |
| 6 | nilai sampah | render mentah (existing) | sama (existing) | garbage tests |
| 7 | hapus wallet terakhir / double-tap / PIN salah | proteksi + disable tombol + pesan (existing, diinspeksi) | — (alur setara di layar, diinspeksi) | inspeksi |

## Bukti Fase 3.4 — session timeout + format tampil

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | lock nonaktif (≤0) | tak pernah kunci (existing, kini teruji) | — (tanpa enforcement = backlog fitur, bukan hardening) | matriks expiry |
| 2 | belum pernah tercatat | paksa kunci (existing) | — | matriks expiry |
| 3 | tepat di batas / 1ms sebelum | kunci / tidak (existing) | — | boundary tests |
| 4 | jam mundur / menit raksasa | fail-open eksplisit / long anti-overflow | — | skew + MAX_INT tests |
| 5 | desimal token absurd | render mentah, cap 0..36 (dulu: potensi OOM) | sama (dulu: hang/OOM `pow`+`padLeft`) | out-of-range grup dua sisi |
| 6 | nilai sampah | render mentah (existing) | sama (existing) | garbage tests |
| 7 | hapus wallet terakhir / double-tap / PIN salah | proteksi + disable tombol + pesan (existing, diinspeksi) | — (alur setara di layar, diinspeksi) | inspeksi |

## Bukti browser hardening — cap render + renderer + E2E

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | aset > 8 MB | 413 + tawaran gateway/aktifkan server (dulu: buffer penuh → risiko OOM) | sama via snackbar/gateway | `isTooLarge`/`exceedsDirectLimit` grup |
| 2 | renderer mati (OOM/crash) | dialog Reload/Close, activity hidup (dulu: ikut mati) | — (plugin tak ekspos API; backlog) | inspeksi |
| 3 | URL laporan di browser asli | E2E manual | E2E `oct_browser_test`: render tanpa "Cannot open" | emulator |
| 4 | error body kosong | `octError` kini bawa pesan (dulu: body kosong) | snackbar sudah deskriptif (existing) | inspeksi |

## Bukti Fase 3.3 — address book

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | label/address null-kosong | address wajib (throw); label boleh kosong (UI substitusi, selaras) | sama (address wajib; label opsional) | grup require/add |
| 2 | duplikat address | kembalikan existing (existing) | kembalikan existing (baru; dulu: duplikat) | dedup implisit via id test |
| 3 | update id asing | tulis ulang tanpa perubahan (existing) | `false` (baru) | update test |
| 4 | baris korup di storage | dilewati per-item (existing `optString`) | `tryFromJson` skip (dulu: seluruh buku hilang!) | tryFromJson 6 kasus |
| 5 | Entry null-field | konstruktor trim+"" (existing) | — (non-nullable, compile-time) | ctor test |

## Bukti Fase 3.2 — proxy + send guards

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | host kosong/port liar/tipe asing | `validateProxy` throw di tulis (dulu: gagal misterius di OkHttp) | sama + `canonicalType` | matriks dua sisi |
| 2 | entry legacy sampah di-tap | toast eksplisit (dulu: crash) | snackbar eksplisit (dulu: crash) | inspeksi |
| 3 | JSON simpanan korup | dilewati per-item? (existing: seluruh list gagal → default? A-term) | entry sampah di-skip, list kosong → pertahankan (dulu: seluruh list hilang) | `tryFromJson` grup |
| 4 | recipient kosong / amount ≤ 0 | `requireRecipient` + `requireAmountRaw` (Fase 1.3) | guard di `send*` pra-network (builder validasi ulang) | builder tests (Fase 1.3) |
| 5 | QR berisi sampah | masuk field → ditolak di send (Fase 1.3) | sama (field → send guard) | inspeksi |

## Bukti Fase 3.1 — status stealth + polling bounds

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | status asing/typo | gagal keras (dulu: gantung `running` + heartbeat abadi) | layar baca status lokal tanpa normalisasi terpusat (backlog) | unknown test (Android) |
| 2 | "unfinished" dikira sukses | fail-first ordering | — | `unfinished` test |
| 3 | step non-numerik | -1 (existing, kini teruji) | — | parseStepNumerator grup |
| 4 | interval/threshold liar | throw saat tulis + clamp saat baca | throw + clamp (cermin) | clamp grup dua sisi |
| 5 | UI simpan di luar bounds | UI ikut validasi (tanpa itu = crash) | UI ikut validasi | inspeksi |
| 6 | overflow `mnt*60000` | dibatasi UI ≤10080 (604,8jt < 2^63) | sama (di bawah 2^31) | inspeksi |

## Bukti Fase 2.3 — profiles, cache, timestamp

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | nama null/kosong/sampah | "Node" + sanitize (dulu: NPE) | trim + "Node" default | sanitize + addProfile grup |
| 2 | nama duplikat | `uniqueName` diekstrak (perilaku sama) | `dedupeName` statik | kedua grup dedup |
| 3 | list/item null | `findByName` null-safe | `firstOrNull` + fallback (existing) | findByName grup |
| 4 | profil korup di storage | dilewati per-item, default bila kosong (existing) | catch → default (existing) | inspeksi |
| 5 | default mati (host lama) | konstanta → host hidup (terbukti via probe) | konstanta → host hidup + migrasi baca (existing) | inspeksi |
| 6 | update id asing | void diam (kontrak lama dipertahankan) | `false` (dulu: void diam) | updateProfile test |
| 7 | timestamp sampah | `optLong/optInt` + default (existing, wajar) | `parseTimestamp` publik + teruji | parseTimestamp 3 grup |
| 8 | DB destruktif | diterima sementara (A14) | migrasi v1→v3 eksplisit (existing) | — |

## Bukti Fase 2.2 — bridge approval + origin + deep link

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | id null/kosong/duplikat | throw `IAE`/`ISE` (dulu: overwrite verdict!) | collision-loop + throw (dulu: overwrite) | `createRejects*`, `newRequestId` grup |
| 2 | complete/remove id tak dikenal/null | no-op aman (CHM tolak null → guard) | `remove` aman (existing) | `nullIdsAreSafeNoops`, `completeMissingIdIsNoop` |
| 3 | waiter dibangunkan | latch + verdict (existing) | completer 5 mnt (existing) | `completeWakesWaiterWithVerdict` |
| 4 | entri basi menumpuk | purge TTL 10 mnt + cap 500 | — (completer timeout 5 mnt existing) | `purgeDropsOnlyStaleEntries` |
| 5 | interrupt saat tunggu | flag dikembalikan (dulu: hilang) | N/A (Future-based) | inspeksi |
| 6 | origin ber-port/titik/besar-kecil | strip port + titik + lower (dulu: entry ber-port tak pernah cocok) + self-heal baca + deny-all dihormati | — (allowlist di Android; Flutter pakai dialog per-request) | 5 grup normalize |
| 7 | deep link rusak/startup | N/A (OS memvalidasi skema) | `_dispatch` abaikan + `checkInitialLink` tak bisa crash startup | inspeksi |
| 8 | ID collision | UUID (dulu: ms+rand1000) | microsecond+32bit+loop (dulu: ms+rand1000) | uniqueness 1000x |

## Bukti Fase 2.1 — validasi local server

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | token salah/hilang/header non-Bearer | tolak + log (existing) | tolak (existing) | grup auth |
| 2 | token server kosong (belum generate) | TOLAK (dulu: terbuka!) | TOLAK (dulu: terbuka bila header `Bearer ` kosong!) | fail-closed tests |
| 3 | limit/offset/epoch negatif-raksasa-sampah | clamp 1..200 / 0..1jt / ≥0 | clamp sama | bounded matrix dua sisi |
| 4 | body bukan JSON object | 400 terpusat (`parsePostBody`→`BadRequestException`; unlock/call dibungkus eksplisit) | 400 per-handler + jaring 500 global anti-gantung | integrasi; 400-path via handler |
| 5 | params non-array / amount-ou non-digit | `params must be array`, `requireUintString` → 400 | sama → 400 | `requireUintString` grup + integrasi |
| 6 | hash kosong | `requireNonEmpty` → 400 (dulu: mengalir ke node) | cek existing → 400 (tetap) | grup require + inspeksi |
| 7 | error tak-terduga lolos handler | 500 existing (`serve` catch) | 500 global baru (dulu: gantung) | inspeksi |

## Bukti Fase 2.0 — oct:// render + serve test

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | URL laporan (`oct://oct99…/index.html`) terparse | case base58 utuh | case base58 utuh | vektor eksak dua sisi |
| 2 | ID kosong / skema salah | `OctUrlParser` (existing): exception/null-safe | `OctUrl.parse` throw `ArgumentError` spesifik | grup reject |
| 3 | query/fragment | strip (existing) | strip | grup strip |
| 4 | gateway URL | N/A (direct RPC) | `gatewayHttpUrl` + port | grup gateway |
| 5 | MIME parameter/kosong | N/A | `cleanMime` + `isTextMime` | grup MIME |
| 6 | node serve asetnya | `circleAsset` (existing, E2E manual) | E2E `oct_circle_test`: `circle_asset` → text/html + body non-kosong | nightly/manual emulator |
| 7 | aset hilang di node | toast kode (existing) | snackbar error (existing) | E2E negatif implisit |

## Bukti Fase 1.4 — mnemonic, PIN, storage

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | tempelan berantakan (spasi/tab/newline, kapital) | `Bip39.normalize` + `validate()` menormalkan dulu (dulu: "Unknown word") | `_normalizeWords` (existing) | normalize test + vektor tempelan |
| 2 | mnemonic null | `normalize` throw IAE; `validate` false | `validate('')` false (existing) | normalize_rejectsNull, wrong-count |
| 3 | checksum salah / kata asing / jumlah salah | `validate` false (existing, kini +normalisasi) | `validate` false (existing) | vektor abandon×12, xyzzy, 11/13 kata |
| 4 | path derivasi sampah | `parsePath` statik: throw spesifik per komponen | `normalizePath` (existing) | parsePath 4 valid + 5 invalid |
| 5 | set PIN bukan 6-digit | `setDefaultPin` throw (UI sudah 6-digit; server unlock kini error eksplisit) | `setPin/changePin` throw `ArgumentError` | `isValidPin` 8 kasus + setPin 5 kasus |
| 6 | verifikasi PIN lama | tak disentuh (back-compat, A10) | `verifyPin` tak disentuh | — (kontrak dijaga) |
| 7 | keystore rusak → fallback plaintext | `Log.w` eksplisit (dulu: diam) di PinStore + MnemonicStore | `debugPrint` + rethrow/false (existing) | inspeksi + lint |
| 8 | simpan mnemonic sampah | `saveMnemonic` tolak blank + checksum gagal (backstop UI) | entry-point tervalidasi via `MnemonicService.validate` di alur import (vektor di atas) | inspeksi + vektor |
| 9 | success-path storage | butuh Context/keystore (E2E/manual) | butuh MethodChannel (E2E/manual) | integrasi |

## Bukti Fase 1.3 — input validation tx privacy

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | amount hilang/sampah/nol/negatif | `TxInputValidator.requireAmountRaw` throw (dulu: jadi 0 diam-diam → tx nol bakar fee) | `requireTxInputs` + guard send* (`amount <= 0`) | `TxInputValidatorTest`, `requireTxInputs` grup |
| 2 | recipient kosong | `requireRecipient` di doSend/doStealth (jalur token sudah punya) | guard `toAddress.isEmpty` + validator | kedua sisi |
| 3 | view pubkey sampah/panjang salah | node/JNI menolak (loud); base64 gagal → throw | panjang != 32 → throw sebelum FFI (anti-overflow buffer 32B) | `viewPub` length implisit; ecdh size test |
| 4 | kunci ECDH salah ukuran | JNI: assert + native check | `ArgumentError` eksplisit pra-FFI (assert release-proof) | `ecdh key sizes` grup |
| 5 | sk/from/to/ou/nonce kosong-nol | — (ditangani JNI/node) | `requireTxInputs` di 6 builder, baris pertama (testable tanpa native lib) | `requireTxInputs` 6 cabang |
| 6 | native timeout/interrupt | `executeNativeCallWithTimeout`: Timeout→cancel+throw; Execution→unwrap cause; Interrupt→flag+rethrow (dulu: wrapper noise + flag hilang) | builder gagal cepat pre-network; RPC `.timeout()` + tanpa sleep (Fase 1.1) | inspeksi |
| 7 | ou/nonce String vs int | — | amountStr ≥ 0 (`'0'` legit key_switch/circle), nonce > 0 | amountStr/nonce tests |

## Bukti Fase 1.2 — nonce, fee oracle, submit guard

| # | Skenario | Android | Flutter | Test |
|---|---|---|---|---|
| 1 | pending_nonce ada | dipakai (`selectNonce`), webcli parity — dulu: diabaikan, nonce basi | dipakai (existing), kini via `parseNonceValue` | `selectNonce_prefersPendingNonce`, precedence test |
| 2 | nonce angka/string/null/hilang | terima num+string; else fallback; `fetchNonce` tetap throw bila hilang total (kontrak lama) | terima num+string; else 0 (termasuk cache korup yang dulu crash `as int?`) | `selectNonce_*`, `parseNonceValue` grup |
| 3 | nonce negatif/super-besar | clamp 0..MAX_INT | clamp 0..2^31-1 | kedua grup clamp |
| 4 | fee bucket valid | `selectFee` (existing, diekstrak) | `parseRecommendedFee` (existing, diekstrak) | kedua grup valid |
| 5 | fee 0/negatif/sampah/hilang | fallback (existing) | fallback + `debugPrint` (dulu: `catch` diam) | kedua grup fallback |
| 6 | submit tanpa tx_hash | `submitTx` throw (dulu: `""` mengalir ke polling/progress) | `requireTxHash` di 7 situs + submitKeySwitch; `_recordTx` tolak hash kosong | integrasi (Android); requireTxHash grup (Flutter) |
| 7 | race nonce konkuren | tidak diatasi (A8) — node menolak, error dipermukaan | sama (A8) | didokumentasikan |
| 8 | OU key_switch | dari fee oracle, fallback 3000 (existing) | sama (existing) | integrasi |

## Bukti Fase 1.1 — RPC dispatch layer

| # | Skenario | Android (`OctraRpcClient`) | Flutter (`RpcClient`) | Test |
|---|---|---|---|---|
| 1 | method null/kosong | `call()` → IAE, tanpa network | `call()` → failure, mock 0 call | `OctraRpcClientTest.call_rejects*`, `rpc_client_test.dart` guards |
| 2 | params null | `[]` (existing) | `[]` (existing) | implisit via wrappers |
| 3 | URL kosong/invalid | fallback DEFAULT + `Log.w` (kontrak lama, A7) | `ArgumentError` spesifik / failure `not configured` | validator test + `setUrl` tests |
| 4 | port non-angka/di luar 1..65535 | N/A (OkHttp IAE → tanpa retry, kasus 6) | `ArgumentError` | `setUrl` tests |
| 5 | HTTP non-2xx | `IOException` + kode + snippet body | `_parseResponse` atas body apa pun | Android: integrasi; Flutter: `HTTP 500` test |
| 6 | error permanen (IAE) | tanpa retry, langsung throw | N/A (tanpa retry, A6) | `callWithRetry_doesNotRetryPermanentErrors` |
| 7 | attempts ≤0 / >5 | clamp 1..5 (`MAX_ATTEMPTS`) | timeout clamp 1..300 | clamp timeout via timeout test; attempts via inspeksi |
| 8 | interrupt saat backoff | flag dikembalikan + rethrow (dulu: ditelan) | N/A (tanpa sleep) | inspeksi + lint |
| 9 | semua percobaan gagal | throw last / ISE | failure terakhir | integrasi |
| 10 | body kosong/bukan JSON | `IllegalStateException` / `JSONException` berkonteks URL+method | `Parse error` | Flutter: garbage/array tests |
| 11 | result obj/skalar/array | wrap `value` (existing) | pass-through, kecuali null | `extractResult_*` + scalar/`0` tests |
| 12 | result null tanpa error | throw informatif | failure `Empty result` (baru) | `extractResult_nullResultThrows` + null-result test |
| 13 | error obj/string/number | pesan diekstrak (existing) | pesan diekstrak (existing) | `throwOnRpcError_handlesAllShapes` + loop test |
| 14 | error null eksplisit | pass (tanpa error) | failure `Unknown` (dulu: `failure('null')`) | `throwOnRpcError` + null-error test |
| 15 | params tak-encodable | N/A (org.json ketat) | failure `Request encoding` (dulu: label `Connection` salah) | unencodable test |
| 16 | timeout/socket | `IOException` via OkHttp+callTimeout 90s | failure `Connection failed` | Flutter: socket+timeout tests |
| 17 | envelope tanpa result+error | failure `Unknown` | failure `Unknown` | unknown-shape tests |

## Bukti Fase C1 — swap.js pindah ke OctraWalletAdapter

Perilaku user-facing sengaja 100% sama; yang berubah hanya siapa yang
mengeksekusi request. Embed Android + Flutter disinkronkan byte-identik
(diterapkan `sdk/test/embed.test.mjs` sebagai gerbang anti-drift).

| # | Skenario | Lokasi penanganan | Test |
|---|---|---|---|
| 1 | Halaman dimuat tanpa transport (injected & localhost mati) | `swap.js adapter()` → `throw 'no wallet transport available'`, view swap disembunyikan | `adapter.test.mjs initialize_is_falseWithNoUsableTransport` |
| 2 | 401 pada panggilan ter-auth (balance / swap / grant) | `boot.mjs withAuthRetry` → modal token sekali, `saveToken` ke sessionStorage, retry sekali saja | `adapter.test.mjs retriesOnceAfterA401RePrompt` + `passesThroughNon401AndDeclinedPrompts` |
| 3 | Pengguna batal pada prompt token | `cancelToken` → resolve `null` → error 401 asli diteruskan (bukan error baru) |idem baris 2 |
| 4 | Prompt kedua saat modal masih terbuka | `_pendingTokenPrompt` di-chain, modal tidak ditumpuk | guard slot-tunggal di `swap.js` |
| 5 | sessionStorage diblokir (private mode) | `loadToken`/`saveToken` try-catch → token hanya hidup di memori tab | guard `boot.mjs` |
| 6 | `.mjs` diserve sebagai `application/octet-stream` | `LocalWebServerService.getMimeType` / `mimeTypeFor` (Java statis, Dart statis) | `LocalServerValidationTest.getMimeType_*`, `local_server_validation_test.dart mimeTypeFor` |
| 7 | Salinan embed meleset dari `sdk/src` | `sdk/test/embed.test.mjs` membandingkan byte per modul, dua embed | 12 test drift |
| 8 | Import relatif ke modul hilang | `embed.test.mjs` resolve graf modul swap.js di disk | 2 test graf |
| 9 | `catch (e) {}` kosong menelan kegagalan | `waitReceipt` menyimpan `lastReceiptError`; balance/reserve menampilkan `adapterMsg(e)` | `embed.test.mjs swap.js has no empty catch blocks` |
| 10 | Hash tx kosong dari dompet | `if (!buyHash) throw` (dulu `!r.tx_hash`) — gagal eksplisit, bukan sukses palsu | `adapter.test.mjs emptyHashIsAFailureNotSuccess` |
| 11 | Fee `ou` hardcode (`SWAP_FEE_OU`, `GRANT_FEE_OU`) | konstanta dihapus; fee decided wallet (fee oracle) | konstanta absen (grep) |
| 12 | `viewVal` menerima `{result}` / `{value}` / primitif | helper `viewVal` + normalisasi `undefined`/`null` → `''` | `adapter.test.mjs unwrapsEnvelopes*` |
| 13 | Saldo OCTtak dilaporkan (hanya `public`) | fallback `parseUnits(bal.public)`; `undefined` dijaga | cabang di `loadBalances` |
| 14 | `pubspec.yaml` tidak mem-bundle `assets/webcli/adapter/` | entri direktori ditambahkan | build Flutter di CI |

### Asumsi eksplisit (C1)

- A18 — Endpoint publik (`/api/wallet/status`, `/api/wallet/unlock`,
  `/api/wallet`, `/api/contract/view`, `/api/contract/receipt`) tetap
  `fetch` langsung: unlock butuh PIN pada dialog native dompet yang tidak
  bisa direplikasi adapter, jadi memindahkannya tidak menambah nilai dan
  berisiko mengubah UX.
- A19 — Hanya halaman `swap` yang dimigrasikan pada C1; `bridge`/`circles`
  menyusul sebagai C2/C3 (bridging EVM + program circles punya flows
  multi-langkah yang perlu dipetakan terpisah).
- A20 — `withAuthRetry` hanya mencoba satu kali setelah 401; 401 kedua
 dilaporkan sebagai error biasa agar tidak ada loop prompt tak terbatas.
- A21 — `sdk/` tetap MIT dan tetap belum dipublikasikan ke npm; embed
  adalah salinan byte-identik, bukan symlink (asset Android tidak mendukung).
- A22 — Divergensi swap.js hanya ada di embed (submodule `webcli/` upstream
  tidak disentuh) supaya upstream tetap bisa dipakai sebagai referensi
  vanilla dan sync submodule tidak Bentrok.

## Bukti Fase C2 — bridge.js pindah ke adapter + dua route mati

Selain migrasi, dua bug nyata ditemukan dan diperbaiki (bukan kosmetik).
Embed Android + Flutter tetap sinkron byte-identik.

| # | Skenario | Lokasi penanganan | Test |
|---|---|---|---|
| 1 | Saldo OCT selalu 0 di localhost | `adapter.getBalance()` kini menerima `public_raw`/`public_oct` **dan** `balance`/`balance_raw`/`encrypted_*` | `getBalance accepts every wallet surface shape` (5 test) |
| 2 | Micro-amount tiba sebagai JSON number (bulat) risking kehilangan presisi | `strOrNull()` menormalkan ke string desimal exact; non-bulat ditolak (null) | `localhost body: {public_raw…}` |
| 3 | Dompet terkunci/server error ditampilkan sebagai saldo 0 | `getBalance()` mengembalikan `error` + `public: null`, bukan angka 0 | `server error body surfaces, not silently zero`, `empty/unknown shapes…` |
| 4 | Hanya saldo terenkripsi (sembunyi) | `private` dari `encrypted_oct`/`encrypted_raw`, `total` = public+private | `localhost encrypted-only wallet` |
| 5 | `epoch` kosong setelah lock terkonfirmasi | `throw` eksplisit + saran auto-resume lewat history | cabang `if (!epochId)` di `doForward` |
| 6 | `/api/transaction?hash=` tidak pernah ada (404) | route baru publik + read-only di kedua server | `normalizeTransaction_*` (JVM) & `/api/transaction normalization` (Dart) |
| 7 | Node menjawab `epoch_id` (spelling lama) | normalizer menerima keduanya | `acceptsEpochIdSpelling` (JVM & Dart) |
| 8 | Hash tak dikenal vs error server | `found: false` + HTTP 200 (bukan 404/500) agar poller retry, bukan gagal | `normalizeTransaction_nullOrEmptyIsNotFound` |
| 9 | `hash` kosong di query | `BadRequestException`/`400 Missing transaction hash` | guard `requireNonEmpty` (JVM) |
| 10 | Hash berisi `&`/`=` (injeksi query) | `encodeURIComponent` di transport + validasi router | `LocalhostTransport URL-encodes the hash` |
| 11 | `error: null` di respons tx (JSONException/null) | `isNull`/`!= null` dijaga, `error_detail` hanya bila ada | `surfacesRejectionReason…` (JVM & Dart) |
| 12 | Hash tak ada di respons node | fallback ke `hash` param, tidak pernah string kosong | `reportsFoundWithEpoch` |
| 13 | 401 saat baca saldo / lock | `boot.mjs withAuthRetry` → modal token sekali → sessionStorage → retry sekali | test boot (Fase C1) + `embed.test.mjs` |
| 14 | Prompt token pada halaman ber-CSP | modal ditambahkan ke `bridge.html`, tombol lewat `data-action` yang sama | `bridge.html loads bridge.js as a module` |
| 15 | Token tak bisa ditutup via keyboard | Escape → batal, Enter → simpan | handler `keydown` + tabel A24 |
| 16 | `catch {}` kosong bertambah di `bridge.js` | baseline 13 di-pin di `embed.test.mjs` (hanya boleh turun) | `bridge.js empty catches do not grow` |
| 17 | `/balance` atau `/transaction` masih dipanggil langsung | prohibited-pattern assertion | `bridge.js routes Octra reads/writes through the adapter` |
| 18 | `ou` hardcode tinggalkan tx kurang bayar | prohibited-pattern `\d+` | idem |
| 19 | `waitReceipt` menelan alasan kegagalan | `_lastReceiptError` dipakai di pesan forward + history | cabang `waitReceipt` |
| 20 | Tidak ada transport untuk epoch lookup history | `last_error: 'no wallet transport for epoch lookup'` (retry, bukan gagal diam) | `historyCheckOne` |

### Asumsi eksplisit (C2)

- A23 — `/api/transaction` dibuat **publik** seperti `/api/fee` (read-only,
  tanpa dompet). Endpoint authed akan membuat halaman dApp tertanam yang
  tidak membawa token selalu 401.
- A24 — MetaMask/EVM tidak dimigrasikan: `eth_*` milik MetaMask, bukan
  permukaan dompet Octra, dan memindahkannya ke adapter tak menambah nilai.
- A25 — `/api/contract/receipt` tetap `fetch` langsung: publik, dan adapter
  tidak menambah apa pun selain lapisan error.
- A26 — 13 `catch {}` warisan upstream sengaja **belum** ditutup: flow
  Ethereum (receipt poller, signer poller, localStorage) belum dipetakan
  kasusnya. Dibatasi dan dipin, bukan diabaikan.
- A27 — `/api/transaction` mengembalikan bentuk ringkas (`found`, `epoch`,
  `status`, `block_height`), bukan objek tx penuh — cukup untuk bridge dan
  tidak membocorkan `signature`/`public_key` seperti `/api/tx` upstream.
- A28 — `octra_getTransaction` masuk `ADAPTER_ONLY_METHODS`, bukan
  `LEGACY_METHODS`: ia lookup node, bukan state dompet, jadi injected
  provider memang tidak wajib menyediakannya.

## Bukti Fase C3 — circles.js: audit coverage lebih dulu, baru migrasi

Audit menemukan fakta yang lebih penting daripada migrasinya: `circles.js`
memakai **75 endpoint, hanya 7 yang dilayani server lokal aplikasi** (68 hanya
ada di webcli desktop). Memasang adapter di atas 68 route mati akan menutupi
fakta itu, jadi batasnya dibuat eksplisit — `docs/CIRCLES-GAP.md`.

| # | Skenario | Lokasi penanganan | Test |
|---|---|---|---|
| 1 | Halaman memanggil 78 endpoint mati di app build | inventaris + preflight probe `/api/relay/health` | `circles bridge endpoint coverage` (8 test) |
| 2 | Android & Flutter-serving endpoint berbeda | `same set (no platform drift)` | idem |
| 3 | Dokumen inventaris basi | test membandingkan daftar di `CIRCLES-GAP.md` vs hasil hitung | `the documented gap matches the measured gap exactly` |
| 4 | Gap membesar diam-diam | baseline 68 di-pin (hanya boleh turun) | `the gap only shrinks (pinned baseline)` |
| 5 | Daftar `DESKTOP_ONLY_ENDPOINTS` basi | setiap entri harus benar-benar tidak dilayani app | `DESKTOP_ONLY_ENDPOINTS … genuinely missing` |
| 6 | `circles.js` diubah jadi module script | `CircleBridgePolicy` (13 rujukan) jadi tak terlihat — test menolak `type="module"` | `the page tells the user which build they are on` |
| 7 | Import adapter gagal | `loadAdapter()` cache ditolak di-reset agar percobaan berikutnya retry | cabang `.catch` di `loadAdapter` |
| 8 | Tidak ada transport untuk baca saldo | `throw 'no wallet transport available…'` | cabang di `wallet.balance` |
| 9 | Body server error (`{error}`) terBaca saldo 0 | `balance.error` dilempar, bukan jadi 0 | cabang di `wallet.balance` |
| 10 | 401 pada baca saldo | pesan menyebut Local Web Server settings (A30) | idem |
| 11 | `/api/keys` tidak ada di app build | error menyebut route + build, bukan "Not found" | `wallet.keys` catch |
| 12 | 404 tanpa konteks | `url failed: HTTP <status> — <detail>` | `404s name the endpoint and status…` |
| 13 | Body non-JSON (halaman proxy) | error khusus "non-JSON body", bukan `SyntaxError` | idem |
| 14 | `octRawFrom` menerima `{error}` saja | `typeof bal !== 'object'` guard → `'0'` | helper `octRawFrom` |
| 15 | `octRawFrom` menerima desimal non-numeric | regex `\d*` per bagian → `'0'`, tak pernah NaN | idem |
| 16 | Embed circles.js berbeda antar platform | perbandingan byte kedua embed | `circles.js matches the upstream source…` |
| 17 | Adapter tidak ada di folder embed | eksistensi `adapter/boot.mjs` diverifikasi | idem |

### Asumsi eksplisit (C3)

- A29 — `wallet.info` tetap `fetch` langsung: circles butuh `rpc_url`, yang
  sengaja tidak diekspos adapter (permukaan dompet dijaga seminimal mungkin).
- A30 — `circles` tidak punya modal token; 401 dijawab dengan instruksi, bukan
  prompt. Menambah modal ke halaman 2268 baris di luar batas C3.
- A31 — 68 route tidak diimplementasi. Masing-masing butuh keputusan backend
  (RPC mana, level auth, perlu wallet unlock atau tidak); menebak 68 route
  demi "halaman berfungsi" adalah tebakan, bukan implementasi.
- A32 — Probe `/api/relay/health` bersifat advisory, tidak memblokir: endpoint
  yang ada (`circle/info`, deploy, unggah aset) tetap harus berfungsi.
- A33 — `DESKTOP_ONLY_ENDPOINTS` berisi 11 route; test hanya menuntut
  setiap entri benar-benar hilang (A-list bisa diperluas tanpa risiko drift).
- A34 — Baseline "hanya boleh turun" dipilih untuk gap dan catch kosong
  alike: mencegah pengembalian diam-diam tanpa memaksa 68 route selesai.
