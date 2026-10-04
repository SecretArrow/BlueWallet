import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  Native function typedefs
// ══════════════════════════════════════════════════════════════════════════════

// ── Core key generation ──────────────────────────────────────────────────────
typedef _KeygenN = Void Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _KeygenD = void Function(Pointer<Uint8>, Pointer<Uint8>);

typedef _KeygenFromSeedN = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _KeygenFromSeedD = int Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);

typedef _PkFromSkN = Void Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _PkFromSkD = void Function(Pointer<Uint8>, Pointer<Uint8>);

typedef _DeriveAddrN = Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32);
typedef _DeriveAddrD = int Function(Pointer<Uint8>, Pointer<Uint8>, int);

// ── Ed25519 signing ──────────────────────────────────────────────────────────
typedef _SignN = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Int32, Pointer<Uint8>);
typedef _SignD = int Function(
    Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>);

typedef _VerifyN = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Int32, Pointer<Uint8>);
typedef _VerifyD = int Function(
    Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>);

// ── SHA-256 ──────────────────────────────────────────────────────────────────
typedef _Sha256N = Void Function(Pointer<Uint8>, Int32, Pointer<Uint8>);
typedef _Sha256D = void Function(Pointer<Uint8>, int, Pointer<Uint8>);

// ── AES-256-GCM ──────────────────────────────────────────────────────────────
typedef _AesEncN = Int32 Function(Pointer<Uint8>, Pointer<Uint8>,
    Pointer<Uint8>, Int32, Pointer<Uint8>, Pointer<Uint8>);
typedef _AesEncD = int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>,
    int, Pointer<Uint8>, Pointer<Uint8>);

typedef _AesDecN = Int32 Function(Pointer<Uint8>, Pointer<Uint8>,
    Pointer<Uint8>, Int32, Pointer<Uint8>, Pointer<Uint8>);
typedef _AesDecD = int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>,
    int, Pointer<Uint8>, Pointer<Uint8>);

// ── Encoding helpers ─────────────────────────────────────────────────────────
typedef _HexEncN = Int32 Function(Pointer<Uint8>, Int32, Pointer<Uint8>, Int32);
typedef _HexEncD = int Function(Pointer<Uint8>, int, Pointer<Uint8>, int);

// ── Random bytes ─────────────────────────────────────────────────────────────
typedef _RandBytesN = Void Function(Pointer<Uint8>, Int32);
typedef _RandBytesD = void Function(Pointer<Uint8>, int);
// ---------- Cache & Stealth typedefs ----------
typedef _CachePutPkN = Int32 Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _CachePutPkD = int Function(Pointer<Uint8>, Pointer<Uint8>);

typedef _CacheGetPkN = Int32 Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _CacheGetPkD = int Function(Pointer<Uint8>, Pointer<Uint8>);

typedef _CacheFeeN = Int32 Function(Pointer<Uint8>, Int32);
typedef _CacheFeeD = int Function(Pointer<Uint8>, int);

typedef _CacheGetFeeN = Pointer<Utf8> Function();
typedef _CacheGetFeeD = Pointer<Utf8> Function();

// ---------- Polling typedefs ----------
typedef _IsPollingN = Int32 Function();
typedef _IsPollingD = int Function();

typedef _StartPollingN = Void Function();
typedef _StartPollingD = void Function();

typedef _StopPollingN = Void Function();
typedef _StopPollingD = void Function();

// ---------- Stealth Scanning typedefs ----------
typedef _IsStealthScanningN = Int32 Function();
typedef _IsStealthScanningD = int Function();

typedef _StartStealthScanN = Void Function();
typedef _StartStealthScanD = void Function();
// ── Stealth transaction helpers ──────────────────────────────────────────────
typedef _DeriveViewKpN = Void Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _DeriveViewKpD = void Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);

typedef _EcdhN = Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _EcdhD = int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);

typedef _StealthTagN = Void Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _StealthTagD = void Function(Pointer<Uint8>, Pointer<Uint8>);

typedef _ClaimSecretN = Void Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _ClaimSecretD = void Function(Pointer<Uint8>, Pointer<Uint8>);

typedef _ClaimPubN = Void Function(
    Pointer<Uint8>, Pointer<Uint8>, Int32, Pointer<Uint8>);
typedef _ClaimPubD = void Function(
    Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>);

typedef _ScalarMultBaseN = Void Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _ScalarMultBaseD = void Function(Pointer<Uint8>, Pointer<Uint8>);

// ── PVAC wrappers ────────────────────────────────────────────────────────────
typedef _PvacAvailableN = Int32 Function();
typedef _PvacAvailableD = int Function();

typedef _PvacInitN = Int32 Function(Pointer<Uint8>);
typedef _PvacInitD = int Function(Pointer<Uint8>);

typedef _PvacResetN = Void Function();
typedef _PvacResetD = void Function();

typedef _PvacGetPubkeyN = Int32 Function(Pointer<Uint8>, Int32);
typedef _PvacGetPubkeyD = int Function(Pointer<Uint8>, int);

typedef _PvacDecBalN = Int64 Function(Pointer<Uint8>, Int32);
typedef _PvacDecBalD = int Function(Pointer<Uint8>, int);

typedef _PvacEncAmtN = Int32 Function(Uint64, Pointer<Uint8>, Int32,
    Pointer<Uint8>, Pointer<Uint8>, Int32, Pointer<Uint8>);
typedef _PvacEncAmtD = int Function(int, Pointer<Uint8>, int, Pointer<Uint8>,
    Pointer<Uint8>, int, Pointer<Uint8>);

typedef _PvacBuildStealthDeltaN = Int32 Function(
    Uint64,
    Pointer<Uint8>,
    Int32,
    Pointer<Uint8>,
    Int32,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Int32,
    Pointer<Uint8>,
    Int32);
typedef _PvacBuildStealthDeltaD = int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int);

typedef _PvacPedersenN = Int32 Function(Uint64, Pointer<Uint8>, Pointer<Uint8>);
typedef _PvacPedersenD = int Function(int, Pointer<Uint8>, Pointer<Uint8>);

// ── FHE Encryption / Decryption ──────────────────────────────────────────────
typedef _FheEncN = Int32 Function(Uint64, Pointer<Uint8>, Int32, Pointer<Uint8>,
    Int32, Pointer<Uint8>, Int32);
typedef _FheEncD = int Function(
    int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int);

typedef _FheDecN = Int32 Function(Pointer<Uint8>, Int32, Pointer<Int64>);
typedef _FheDecD = int Function(Pointer<Uint8>, int, Pointer<Int64>);

// ── AES-KAT ──────────────────────────────────────────────────────────────────
typedef _AesKatN = Void Function(Pointer<Uint8>);
typedef _AesKatD = void Function(Pointer<Uint8>);

// ── Version ──────────────────────────────────────────────────────────────────
typedef _VersionN = Pointer<Uint8> Function();
typedef _VersionD = Pointer<Uint8> Function();

// ══════════════════════════════════════════════════════════════════════════════
//  NativeCrypto singleton
// ══════════════════════════════════════════════════════════════════════════════

/// Loads liboctra_native.so and exposes the Octra C++ crypto + stealth + PVAC
/// functions to Dart.
///
/// Call [NativeCrypto.init()] once at startup (in main()). Throws [StateError]
/// if the library cannot be loaded — there is no Dart fallback.
class NativeCrypto {
  NativeCrypto._();
  static NativeCrypto? _instance;

  // ── Core crypto ──────────────────────────────────────────────────────────
  late final _KeygenD _keygen;
  late final _KeygenFromSeedD _keygenFromSeed;
  late final _PkFromSkD _pkFromSk;
  late final _DeriveAddrD _deriveAddress;
  late final _SignD _sign;
  late final _VerifyD _verify;
  late final _Sha256D _sha256;
  late final _AesEncD _aesEnc;
  late final _AesDecD _aesDec;
  late final _HexEncD _hexEnc;
  late final _RandBytesD _randBytes;
  late final _VersionD _version;

  // ── Stealth ──────────────────────────────────────────────────────────────
  late final _DeriveViewKpD _deriveViewKp;
  late final _EcdhD _ecdh;
  late final _StealthTagD _stealthTag;
  late final _ClaimSecretD _claimSecret;
  late final _ClaimPubD _claimPub;
  late final _ScalarMultBaseD _scalarMultBase;

  // ── PVAC ─────────────────────────────────────────────────────────────────
  late final _PvacAvailableD _pvacAvailable;
  late final _PvacInitD _pvacInit;
  late final _PvacResetD _pvacReset;
  late final _PvacGetPubkeyD _pvacGetPubkey;
  late final _PvacDecBalD _pvacDecBal;
  late final _PvacEncAmtD _pvacEncAmt;
  late final _PvacBuildStealthDeltaD _pvacBuildStealthDelta;
  late final _PvacPedersenD _pvacPedersen;
  late final _FheEncD _fheEncrypt;
  late final _FheDecD _fheDecrypt;

  // ── AES-KAT ──────────────────────────────────────────────────────────────
  late final _AesKatD _aesKat;
  // ── Cache ──────────────────────────────────────────────────────────────
  late final _CachePutPkD _cachePutPk;
  late final _CacheGetPkD _cacheGetPk;
  late final _CacheFeeD _cacheFee;
  late final _CacheGetFeeD _cacheGetFee;

  // ── Polling ────────────────────────────────────────────────────────────
  late final _IsPollingD _isPolling;
  late final _StartPollingD _startPolling;
  late final _StopPollingD _stopPolling;

  // ── Stealth Scanning ──────────────────────────────────────────────────
  late final _IsStealthScanningD _isStealthScanning;
  late final _StartStealthScanD _startStealthScan;

  /// Resolves and opens the platform-appropriate native library.
  ///
  ///   Android  → liboctra_native.so   (bundled inside the APK)
  ///   iOS      → statically linked into Runner (DynamicLibrary.process())
  ///   Linux    → liboctra_native.so   (installed to bundle/lib/)
  ///   Windows  → octra_native.dll     (installed alongside .exe)
  ///   macOS    → statically linked into Runner (DynamicLibrary.process())
  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('liboctra_native.so');
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('liboctra_native.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('octra_native.dll');
    }
    // iOS, macOS — library is statically linked into the runner binary.
    return DynamicLibrary.process();
  }

  /// Loads the native octra crypto library. Must be called once before any
  /// crypto operation. Throws [StateError] on failure — there is no Dart fallback.
  static void init() {
    if (_instance != null) return;

    final DynamicLibrary lib = _loadLibrary();

    final n = NativeCrypto._();

    // Core crypto
    n._keygen = lib.lookupFunction<_KeygenN, _KeygenD>('octra_keygen');
    n._keygenFromSeed = lib.lookupFunction<_KeygenFromSeedN, _KeygenFromSeedD>(
        'octra_keygen_from_seed');
    n._pkFromSk =
        lib.lookupFunction<_PkFromSkN, _PkFromSkD>('octra_pk_from_sk');
    n._deriveAddress =
        lib.lookupFunction<_DeriveAddrN, _DeriveAddrD>('octra_derive_address');
    n._sign = lib.lookupFunction<_SignN, _SignD>('octra_sign');
    n._verify = lib.lookupFunction<_VerifyN, _VerifyD>('octra_verify');
    n._sha256 = lib.lookupFunction<_Sha256N, _Sha256D>('octra_sha256');
    n._aesEnc =
        lib.lookupFunction<_AesEncN, _AesEncD>('octra_aes256gcm_encrypt');
    n._aesDec =
        lib.lookupFunction<_AesDecN, _AesDecD>('octra_aes256gcm_decrypt');
    n._hexEnc = lib.lookupFunction<_HexEncN, _HexEncD>('octra_hex_encode');
    n._randBytes =
        lib.lookupFunction<_RandBytesN, _RandBytesD>('octra_random_bytes');
    n._version =
        lib.lookupFunction<_VersionN, _VersionD>('octra_native_version');

    // Stealth
    n._deriveViewKp = lib.lookupFunction<_DeriveViewKpN, _DeriveViewKpD>(
        'octra_derive_view_keypair');
    n._ecdh = lib.lookupFunction<_EcdhN, _EcdhD>('octra_ecdh');
    n._stealthTag =
        lib.lookupFunction<_StealthTagN, _StealthTagD>('octra_stealth_tag');
    n._claimSecret =
        lib.lookupFunction<_ClaimSecretN, _ClaimSecretD>('octra_claim_secret');
    n._claimPub = lib.lookupFunction<_ClaimPubN, _ClaimPubD>('octra_claim_pub');
    n._scalarMultBase = lib.lookupFunction<_ScalarMultBaseN, _ScalarMultBaseD>(
        'octra_scalarmult_base');

    // PVAC
    n._pvacAvailable = lib.lookupFunction<_PvacAvailableN, _PvacAvailableD>(
        'octra_pvac_available');
    n._pvacInit = lib.lookupFunction<_PvacInitN, _PvacInitD>('octra_pvac_init');
    n._pvacReset =
        lib.lookupFunction<_PvacResetN, _PvacResetD>('octra_pvac_reset');
    n._pvacGetPubkey = lib.lookupFunction<_PvacGetPubkeyN, _PvacGetPubkeyD>(
        'octra_pvac_get_pubkey_b64');
    n._pvacDecBal = lib.lookupFunction<_PvacDecBalN, _PvacDecBalD>(
        'octra_pvac_decrypt_balance');
    n._pvacEncAmt = lib.lookupFunction<_PvacEncAmtN, _PvacEncAmtD>(
        'octra_pvac_encrypt_amount');
    n._pvacBuildStealthDelta =
        lib.lookupFunction<_PvacBuildStealthDeltaN, _PvacBuildStealthDeltaD>(
            'octra_pvac_build_stealth_delta');
    n._pvacPedersen = lib.lookupFunction<_PvacPedersenN, _PvacPedersenD>(
        'octra_pvac_pedersen_commit');
    n._fheEncrypt = lib.lookupFunction<_FheEncN, _FheEncD>('octra_fhe_encrypt');
    n._fheDecrypt = lib.lookupFunction<_FheDecN, _FheDecD>('octra_fhe_decrypt');

    // AES-KAT
    n._aesKat = lib.lookupFunction<_AesKatN, _AesKatD>('octra_compute_aes_kat');

    // Cache & Stealth
    n._cachePutPk =
        lib.lookupFunction<_CachePutPkN, _CachePutPkD>('octra_cache_put_pk');
    n._cacheGetPk =
        lib.lookupFunction<_CacheGetPkN, _CacheGetPkD>('octra_cache_get_pk');
    n._cacheFee = lib.lookupFunction<_CacheFeeN, _CacheFeeD>('octra_cache_fee');
    n._cacheGetFee =
        lib.lookupFunction<_CacheGetFeeN, _CacheGetFeeD>('octra_cache_get_fee');

    // Polling
    n._isPolling =
        lib.lookupFunction<_IsPollingN, _IsPollingD>('octra_is_polling');
    n._startPolling = lib
        .lookupFunction<_StartPollingN, _StartPollingD>('octra_start_polling');
    n._stopPolling =
        lib.lookupFunction<_StopPollingN, _StopPollingD>('octra_stop_polling');

    // Stealth Scanning
    n._isStealthScanning =
        lib.lookupFunction<_IsStealthScanningN, _IsStealthScanningD>(
            'octra_is_stealth_scanning');
    n._startStealthScan =
        lib.lookupFunction<_StartStealthScanN, _StartStealthScanD>(
            'octra_start_stealth_scan');

    _instance = n;
  }

  static NativeCrypto get _i {
    if (_instance == null) {
      throw StateError(
          'NativeCrypto not initialised — call NativeCrypto.init() in main()');
    }
    return _instance!;
  }

  // ── Helper: copy bytes into native pointer ────────────────────────────────

  static void _copyTo(Pointer<Uint8> dst, Uint8List src) {
    for (int i = 0; i < src.length; i++) {
      dst[i] = src[i];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Core crypto API
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the native library version string.
  static String version() {
    final ptr = _i._version();
    return ptr.cast<Utf8>().toDartString();
  }

  /// Generates a fresh random ed25519 keypair using TweetNaCl + /dev/urandom.
  static Map<String, Uint8List> generateKeyPair() {
    final skPtr = calloc<Uint8>(64);
    final pkPtr = calloc<Uint8>(32);
    try {
      _i._keygen(skPtr, pkPtr);
      return {
        'sk': Uint8List.fromList(skPtr.asTypedList(64)),
        'pk': Uint8List.fromList(pkPtr.asTypedList(32)),
      };
    } finally {
      calloc.free(skPtr);
      calloc.free(pkPtr);
    }
  }

  /// Derives a deterministic ed25519 keypair from a 32-byte [seed] (RFC 8032).
  static Map<String, Uint8List> keygenFromSeed(Uint8List seed) {
    assert(seed.length == 32);
    final seedPtr = calloc<Uint8>(32);
    final skPtr = calloc<Uint8>(64);
    final pkPtr = calloc<Uint8>(32);
    try {
      _copyTo(seedPtr, seed);
      final rc = _i._keygenFromSeed(seedPtr, skPtr, pkPtr);
      if (rc != 0) throw StateError('octra_keygen_from_seed failed ($rc)');
      return {
        'sk': Uint8List.fromList(skPtr.asTypedList(64)),
        'pk': Uint8List.fromList(pkPtr.asTypedList(32)),
      };
    } finally {
      calloc.free(seedPtr);
      calloc.free(skPtr);
      calloc.free(pkPtr);
    }
  }

  /// Extracts the 32-byte public key from a 64-byte TweetNaCl signing key.
  static Uint8List pkFromSk(Uint8List sk) {
    assert(sk.length == 64);
    final skPtr = calloc<Uint8>(64);
    final pkPtr = calloc<Uint8>(32);
    try {
      _copyTo(skPtr, sk);
      _i._pkFromSk(skPtr, pkPtr);
      return Uint8List.fromList(pkPtr.asTypedList(32));
    } finally {
      calloc.free(skPtr);
      calloc.free(pkPtr);
    }
  }

  /// Derives the "oct..." wallet address from a 32-byte public key.
  static String deriveAddress(Uint8List pk) {
    assert(pk.length == 32);
    final pkPtr = calloc<Uint8>(32);
    final addrBuf = calloc<Uint8>(64);
    try {
      _copyTo(pkPtr, pk);
      final n = _i._deriveAddress(pkPtr, addrBuf, 64);
      if (n <= 0) throw StateError('octra_derive_address failed');
      return addrBuf.cast<Utf8>().toDartString();
    } finally {
      calloc.free(pkPtr);
      calloc.free(addrBuf);
    }
  }

  /// Signs [msg] with [sk] (64 bytes). Returns the 64-byte detached signature.
  static Uint8List sign(Uint8List sk, Uint8List msg) {
    assert(sk.length == 64);
    final skPtr = calloc<Uint8>(64);
    final msgPtr = calloc<Uint8>(msg.isEmpty ? 1 : msg.length);
    final sigPtr = calloc<Uint8>(64);
    try {
      _copyTo(skPtr, sk);
      _copyTo(msgPtr, msg);
      final rc = _i._sign(skPtr, msgPtr, msg.length, sigPtr);
      if (rc != 0) throw StateError('octra_sign failed ($rc)');
      return Uint8List.fromList(sigPtr.asTypedList(64));
    } finally {
      calloc.free(skPtr);
      calloc.free(msgPtr);
      calloc.free(sigPtr);
    }
  }

  /// Verifies a detached ed25519 [sig] (64 bytes) over [msg] with [pk] (32 bytes).
  static bool verify(Uint8List pk, Uint8List msg, Uint8List sig) {
    assert(pk.length == 32 && sig.length == 64);
    final pkPtr = calloc<Uint8>(32);
    final msgPtr = calloc<Uint8>(msg.isEmpty ? 1 : msg.length);
    final sigPtr = calloc<Uint8>(64);
    try {
      _copyTo(pkPtr, pk);
      _copyTo(msgPtr, msg);
      _copyTo(sigPtr, sig);
      return _i._verify(pkPtr, msgPtr, msg.length, sigPtr) == 0;
    } finally {
      calloc.free(pkPtr);
      calloc.free(msgPtr);
      calloc.free(sigPtr);
    }
  }

  /// SHA-256 hash.
  static Uint8List sha256(Uint8List data) {
    final inPtr = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final outPtr = calloc<Uint8>(32);
    try {
      _copyTo(inPtr, data);
      _i._sha256(inPtr, data.length, outPtr);
      return Uint8List.fromList(outPtr.asTypedList(32));
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  /// Generates [len] cryptographically secure random bytes.
  static Uint8List randomBytes(int len) {
    final ptr = calloc<Uint8>(len);
    try {
      _i._randBytes(ptr, len);
      return Uint8List.fromList(ptr.asTypedList(len));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Hex-encodes [data] to lowercase hex string.
  static String hexEncode(Uint8List data) {
    final inPtr = calloc<Uint8>(data.length);
    final outPtr = calloc<Uint8>(data.length * 2 + 1);
    try {
      _copyTo(inPtr, data);
      final n = _i._hexEnc(inPtr, data.length, outPtr, data.length * 2 + 1);
      if (n < 0) throw StateError('octra_hex_encode failed');
      return outPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  /// AES-256-GCM encrypt via OpenSSL EVP.
  static ({Uint8List ciphertext, Uint8List tag}) aes256gcmEncrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) {
    assert(key.length == 32 && iv.length == 12);
    final keyPtr = calloc<Uint8>(32);
    final ivPtr = calloc<Uint8>(12);
    final plainPtr = calloc<Uint8>(plaintext.isEmpty ? 1 : plaintext.length);
    final cipherPtr = calloc<Uint8>(plaintext.isEmpty ? 1 : plaintext.length);
    final tagPtr = calloc<Uint8>(16);
    try {
      _copyTo(keyPtr, key);
      _copyTo(ivPtr, iv);
      _copyTo(plainPtr, plaintext);
      final rc = _i._aesEnc(
          keyPtr, ivPtr, plainPtr, plaintext.length, cipherPtr, tagPtr);
      if (rc < 0) throw StateError('octra_aes256gcm_encrypt failed');
      return (
        ciphertext: Uint8List.fromList(cipherPtr.asTypedList(rc)),
        tag: Uint8List.fromList(tagPtr.asTypedList(16)),
      );
    } finally {
      calloc.free(keyPtr);
      calloc.free(ivPtr);
      calloc.free(plainPtr);
      calloc.free(cipherPtr);
      calloc.free(tagPtr);
    }
  }

  /// AES-256-GCM decrypt via OpenSSL EVP.
  static Uint8List aes256gcmDecrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List ciphertext,
    required Uint8List tag,
  }) {
    assert(key.length == 32 && iv.length == 12 && tag.length == 16);
    final keyPtr = calloc<Uint8>(32);
    final ivPtr = calloc<Uint8>(12);
    final cipherPtr = calloc<Uint8>(ciphertext.isEmpty ? 1 : ciphertext.length);
    final tagPtr = calloc<Uint8>(16);
    final plainPtr = calloc<Uint8>(ciphertext.isEmpty ? 1 : ciphertext.length);
    try {
      _copyTo(keyPtr, key);
      _copyTo(ivPtr, iv);
      _copyTo(cipherPtr, ciphertext);
      _copyTo(tagPtr, tag);
      final rc = _i._aesDec(
          keyPtr, ivPtr, cipherPtr, ciphertext.length, tagPtr, plainPtr);
      if (rc < 0) {
        throw StateError('octra_aes256gcm_decrypt: authentication failed');
      }
      return Uint8List.fromList(plainPtr.asTypedList(rc));
    } finally {
      calloc.free(keyPtr);
      calloc.free(ivPtr);
      calloc.free(cipherPtr);
      calloc.free(tagPtr);
      calloc.free(plainPtr);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Stealth transaction API
  // ══════════════════════════════════════════════════════════════════════════

  /// Derives the x25519 view keypair from an ed25519 64-byte signing key.
  /// Returns {'sk': Uint8List(32), 'pk': Uint8List(32)}.
  static Map<String, Uint8List> deriveViewKeypair(Uint8List edSk) {
    assert(edSk.length == 64);
    final skPtr = calloc<Uint8>(64);
    final xskPtr = calloc<Uint8>(32);
    final xpkPtr = calloc<Uint8>(32);
    try {
      _copyTo(skPtr, edSk);
      _i._deriveViewKp(skPtr, xskPtr, xpkPtr);
      return {
        'sk': Uint8List.fromList(xskPtr.asTypedList(32)),
        'pk': Uint8List.fromList(xpkPtr.asTypedList(32)),
      };
    } finally {
      calloc.free(skPtr);
      calloc.free(xskPtr);
      calloc.free(xpkPtr);
    }
  }

  /// x25519 ECDH + SHA-256. Returns 32-byte shared secret.
  /// Throws [StateError] when the peer key is rejected (low-order point),
  /// mirroring upstream webcli behavior.
  static Uint8List ecdh(Uint8List ourXsk, Uint8List theirXpk) {
    // Explicit check: asserts are stripped in release builds, and an
    // oversized key would overflow the 32-byte native buffers below.
    if (ourXsk.length != 32 || theirXpk.length != 32) {
      throw ArgumentError(
          'ECDH keys must be 32 bytes (got ${ourXsk.length}/${theirXpk.length})');
    }
    assert(ourXsk.length == 32 && theirXpk.length == 32);
    final skPtr = calloc<Uint8>(32);
    final pkPtr = calloc<Uint8>(32);
    final sharedPtr = calloc<Uint8>(32);
    try {
      _copyTo(skPtr, ourXsk);
      _copyTo(pkPtr, theirXpk);
      final ok = _i._ecdh(skPtr, pkPtr, sharedPtr);
      if (ok == 0) {
        throw StateError('x25519 low-order public key rejected');
      }
      return Uint8List.fromList(sharedPtr.asTypedList(32));
    } finally {
      calloc.free(skPtr);
      calloc.free(pkPtr);
      calloc.free(sharedPtr);
    }
  }

  /// Computes the 16-byte stealth tag from a shared secret.
  static Uint8List stealthTag(Uint8List sharedSecret) {
    assert(sharedSecret.length == 32);
    final sharedPtr = calloc<Uint8>(32);
    final tagPtr = calloc<Uint8>(16);
    try {
      _copyTo(sharedPtr, sharedSecret);
      _i._stealthTag(sharedPtr, tagPtr);
      return Uint8List.fromList(tagPtr.asTypedList(16));
    } finally {
      calloc.free(sharedPtr);
      calloc.free(tagPtr);
    }
  }

  /// Computes the 32-byte claim secret from a shared secret.
  static Uint8List claimSecret(Uint8List sharedSecret) {
    assert(sharedSecret.length == 32);
    final sharedPtr = calloc<Uint8>(32);
    final outPtr = calloc<Uint8>(32);
    try {
      _copyTo(sharedPtr, sharedSecret);
      _i._claimSecret(sharedPtr, outPtr);
      return Uint8List.fromList(outPtr.asTypedList(32));
    } finally {
      calloc.free(sharedPtr);
      calloc.free(outPtr);
    }
  }

  /// Computes the 32-byte claim pub from claim secret + recipient address.
  static Uint8List claimPub(Uint8List claimSecretBytes, String address) {
    assert(claimSecretBytes.length == 32);
    final secPtr = calloc<Uint8>(32);
    final addrPtr = address.toNativeUtf8().cast<Uint8>();
    final outPtr = calloc<Uint8>(32);
    try {
      _copyTo(secPtr, claimSecretBytes);
      _i._claimPub(secPtr, addrPtr, address.length, outPtr);
      return Uint8List.fromList(outPtr.asTypedList(32));
    } finally {
      calloc.free(secPtr);
      calloc.free(addrPtr);
      calloc.free(outPtr);
    }
  }

  /// Curve25519 scalar mult base (public key from secret key).
  static Uint8List scalarMultBase(Uint8List sk) {
    assert(sk.length == 32);
    final skPtr = calloc<Uint8>(32);
    final pkPtr = calloc<Uint8>(32);
    try {
      _copyTo(skPtr, sk);
      _i._scalarMultBase(skPtr, pkPtr);
      return Uint8List.fromList(pkPtr.asTypedList(32));
    } finally {
      calloc.free(skPtr);
      calloc.free(pkPtr);
    }
  }

  /// Full stealth preparation: generates ephemeral key, performs ECDH,
  /// computes stealth tag, claim secret, claim pub, and blinding.
  /// Mirrors Android's OctraNative.stealthPrepare().
  static Map<String, String> stealthPrepare({
    required Uint8List edSk,
    required Uint8List theirViewPubkey,
    required String recipientAddress,
  }) {
    assert(edSk.length == 64 && theirViewPubkey.length == 32);

    // Generate ephemeral x25519 key
    final ephSk = randomBytes(32);
    final ephPk = scalarMultBase(ephSk);

    // ECDH
    final shared = ecdh(ephSk, theirViewPubkey);

    // Stealth tag + claim key
    final tag = stealthTag(shared);
    final clmSec = claimSecret(shared);
    final clmPub = claimPub(clmSec, recipientAddress);

    // Random blinding
    final blinding = randomBytes(32);

    // Encode to strings
    return {
      'eph_pub_b64': _b64(ephPk),
      'shared_secret_b64': _b64(shared),
      'stealth_tag_hex': hexEncode(tag),
      'claim_pub_hex': hexEncode(clmPub),
      'blinding_b64': _b64(blinding),
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PVAC API
  // ══════════════════════════════════════════════════════════════════════════

  /// Whether PVAC is available on this ABI (arm64 / x86_64 only) and initialised.
  static bool get pvacAvailable => _i._pvacAvailable() != 0;

  /// Initialises PVAC with a 32-byte wallet seed.
  /// Returns 0 on success, -1 if ABI unsupported, -2 if init failed.
  static int pvacInit(Uint8List seed) {
    assert(seed.length == 32);
    final seedPtr = calloc<Uint8>(32);
    try {
      _copyTo(seedPtr, seed);
      return _i._pvacInit(seedPtr);
    } finally {
      calloc.free(seedPtr);
    }
  }

  /// Frees the global PVAC state.
  static void pvacReset() => _i._pvacReset();

  /// Returns the PVAC public key as base64 (for registration), or null.
  static String? pvacGetPubkeyB64() {
    const maxLen = 8192;
    final buf = calloc<Uint8>(maxLen);
    try {
      final n = _i._pvacGetPubkey(buf, maxLen);
      if (n <= 0) return null;
      return buf.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buf);
    }
  }

  /// Decrypts a PVAC encrypted balance cipher string.
  /// Returns the balance as int64.
  static int pvacDecryptBalance(String cipherStr) {
    final ptr = cipherStr.toNativeUtf8().cast<Uint8>();
    try {
      return _i._pvacDecBal(ptr, cipherStr.length);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Encrypts an amount using PVAC FHE and builds Pedersen commitment + zero proof.
  /// Returns null if PVAC is unavailable.
  static ({
    String cipher,
    Uint8List commitment,
    String zeroProof,
    Uint8List blinding
  })? pvacEncryptAmount(int amount) {
    const maxBuf = 65536;
    final cipherBuf = calloc<Uint8>(maxBuf);
    final commitBuf = calloc<Uint8>(32);
    final zpBuf = calloc<Uint8>(maxBuf);
    final blindBuf = calloc<Uint8>(32);
    try {
      final rc = _i._pvacEncAmt(
          amount, cipherBuf, maxBuf, commitBuf, zpBuf, maxBuf, blindBuf);
      if (rc != 0) return null;
      return (
        cipher: cipherBuf.cast<Utf8>().toDartString(),
        commitment: Uint8List.fromList(commitBuf.asTypedList(32)),
        zeroProof: zpBuf.cast<Utf8>().toDartString(),
        blinding: Uint8List.fromList(blindBuf.asTypedList(32)),
      );
    } finally {
      calloc.free(cipherBuf);
      calloc.free(commitBuf);
      calloc.free(zpBuf);
      calloc.free(blindBuf);
    }
  }

  /// Builds the stealth delta data: FHE encrypt, commitment, range proofs.
  /// Returns null if PVAC is unavailable or insufficient balance.
  static ({
    String deltaCipher,
    Uint8List commitment,
    String rpDelta,
    String rpBalance
  })? pvacBuildStealthDelta(int amount, String currentCipher) {
    const maxBuf = 65536;
    final curPtr = currentCipher.toNativeUtf8().cast<Uint8>();
    final dcBuf = calloc<Uint8>(maxBuf);
    final cmtBuf = calloc<Uint8>(32);
    final rpdBuf = calloc<Uint8>(maxBuf);
    final rpbBuf = calloc<Uint8>(maxBuf);
    try {
      final rc = _i._pvacBuildStealthDelta(
        amount,
        curPtr,
        currentCipher.length,
        dcBuf,
        maxBuf,
        cmtBuf,
        rpdBuf,
        maxBuf,
        rpbBuf,
        maxBuf,
      );
      if (rc != 0) return null;
      return (
        deltaCipher: dcBuf.cast<Utf8>().toDartString(),
        commitment: Uint8List.fromList(cmtBuf.asTypedList(32)),
        rpDelta: rpdBuf.cast<Utf8>().toDartString(),
        rpBalance: rpbBuf.cast<Utf8>().toDartString(),
      );
    } finally {
      calloc.free(curPtr);
      calloc.free(dcBuf);
      calloc.free(cmtBuf);
      calloc.free(rpdBuf);
      calloc.free(rpbBuf);
    }
  }

  /// Computes a Pedersen commitment. Returns null if PVAC unavailable.
  static Uint8List? pvacPedersenCommit(int amount, Uint8List blinding) {
    assert(blinding.length == 32);
    final blindPtr = calloc<Uint8>(32);
    final outPtr = calloc<Uint8>(32);
    try {
      _copyTo(blindPtr, blinding);
      final rc = _i._pvacPedersen(amount, blindPtr, outPtr);
      if (rc != 0) return null;
      return Uint8List.fromList(outPtr.asTypedList(32));
    } finally {
      calloc.free(blindPtr);
      calloc.free(outPtr);
    }
  }

  /// Computes AES Known Answer Test (KAT) for PVAC pubkey registration.
  /// Returns 16-byte result as hex string.
  static String computeAesKat() {
    final outPtr = calloc<Uint8>(16);
    try {
      _i._aesKat(outPtr);
      const hex = '0123456789abcdef';
      final buf = StringBuffer();
      for (int i = 0; i < 16; i++) {
        buf.write(hex[(outPtr[i] >> 4) & 0xF]);
        buf.write(hex[outPtr[i] & 0xF]);
      }
      return buf.toString();
    } finally {
      calloc.free(outPtr);
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  static String _b64(Uint8List data) {
    // Use native base64 for consistency — but dart:convert is fine for this.
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final buf = StringBuffer();
    for (int i = 0; i < data.length; i += 3) {
      final b0 = data[i];
      final b1 = (i + 1 < data.length) ? data[i + 1] : 0;
      final b2 = (i + 2 < data.length) ? data[i + 2] : 0;
      buf.write(chars[(b0 >> 2) & 0x3f]);
      buf.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3f]);
      buf.write(
          (i + 1 < data.length) ? chars[((b1 << 2) | (b2 >> 6)) & 0x3f] : '=');
      buf.write((i + 2 < data.length) ? chars[b2 & 0x3f] : '=');
    }
    return buf.toString();
  }

  // ---------- Cache API ----------
  static void cachePutPk(String addr, Uint8List pk) {
    assert(pk.length == 32);
    final addrPtr = addr.toNativeUtf8().cast<Uint8>();
    final pkPtr = calloc<Uint8>(32);
    try {
      _copyTo(pkPtr, pk);
      _i._cachePutPk(addrPtr, pkPtr);
    } finally {
      calloc.free(addrPtr);
      calloc.free(pkPtr);
    }
  }

  static Uint8List? cacheGetPk(String addr) {
    final addrPtr = addr.toNativeUtf8().cast<Uint8>();
    final pkPtr = calloc<Uint8>(32);
    try {
      final rc = _i._cacheGetPk(addrPtr, pkPtr);
      if (rc != 0) return null;
      return Uint8List.fromList(pkPtr.asTypedList(32));
    } finally {
      calloc.free(addrPtr);
      calloc.free(pkPtr);
    }
  }

  static void cacheFee(String feeJson) {
    final ptr = feeJson.toNativeUtf8().cast<Uint8>();
    try {
      _i._cacheFee(ptr, feeJson.length);
    } finally {
      calloc.free(ptr);
    }
  }

  static String? getCachedFee() {
    final ptr = _i._cacheGetFee();
    if (ptr == nullptr) return null;
    return ptr.cast<Utf8>().toDartString();
  }

  // ---------- Polling API ----------
  static bool get isPolling => _i._isPolling() != 0;

  static void startPolling() => _i._startPolling();
  static void stopPolling() => _i._stopPolling();

  // ---------- Stealth Scanning API ----------
  static bool get isStealthScanning => _i._isStealthScanning() != 0;

  static void startStealthScan() => _i._startStealthScan();

  // ---------- FHE API ----------
  static ({String cipher, String commitment, String zeroProof})? fheEncrypt(
      int value) {
    if (!pvacAvailable) return null;
    const maxBuf = 65536;
    final dcBuf = calloc<Uint8>(maxBuf);
    final cmtBuf = calloc<Uint8>(maxBuf);
    final zpBuf = calloc<Uint8>(maxBuf);
    try {
      final rc =
          _i._fheEncrypt(value, dcBuf, maxBuf, cmtBuf, maxBuf, zpBuf, maxBuf);
      if (rc != 0) return null;
      return (
        cipher: dcBuf.cast<Utf8>().toDartString(),
        commitment: cmtBuf.cast<Utf8>().toDartString(),
        zeroProof: zpBuf.cast<Utf8>().toDartString(),
      );
    } finally {
      calloc.free(dcBuf);
      calloc.free(cmtBuf);
      calloc.free(zpBuf);
    }
  }

  static int? fheDecrypt(String cipherStr) {
    if (!pvacAvailable) return null;
    final ptr = cipherStr.toNativeUtf8().cast<Uint8>();
    final valOut = calloc<Int64>();
    try {
      final rc = _i._fheDecrypt(ptr, cipherStr.length, valOut);
      if (rc != 0) return null;
      return valOut.value;
    } finally {
      calloc.free(ptr);
      calloc.free(valOut);
    }
  }
}
