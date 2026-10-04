import 'dart:convert';
import 'dart:typed_data';
import 'native_crypto.dart';

/// Full cryptographic service backed entirely by the native C++ library.
///
/// All operations delegate to [NativeCrypto] (liboctra_native.so).
/// Ed25519 key operations use TweetNaCl; AES-256-GCM uses OpenSSL EVP.
/// Stealth + PVAC operations use the corresponding C++ wrappers.
///
/// Key format (Ed25519 / TweetNaCl):
///   Seed    = 32 random bytes
///   Secret key (sk) = 64 bytes: seed[32] ++ pubkey[32]
///   Public key (pk) = 32 bytes
///   Address = "oct" + base58(sha256(pubkey))
class CryptoService {

  // ══════════════════════════════════════════════════════════════════════════
  //  Address derivation
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the wallet address for a 32-byte ed25519 public key.
  static String deriveAddress(Uint8List pubkey) {
    return NativeCrypto.deriveAddress(pubkey);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Key generation
  // ══════════════════════════════════════════════════════════════════════════

  /// Generates a new random ed25519 keypair via TweetNaCl + /dev/urandom.
  /// Returns {'sk': base64(sk[64]), 'pk': base64(pk[32]), 'address': '...'}.
  static Future<Map<String, String>> generateKeyPair() async {
    final kp      = NativeCrypto.generateKeyPair();
    final sk      = kp['sk']!;
    final pk      = kp['pk']!;
    final address = NativeCrypto.deriveAddress(pk);
    return {
      'sk': base64.encode(sk),
      'pk': base64.encode(pk),
      'address': address,
    };
  }

  /// Imports a wallet from a private key (base64- or hex-encoded).
  ///
  /// Accepts:
  ///  - 64-byte NaCl secret key (seed[32] ++ pubkey[32]) encoded as base64
  ///  - 32-byte raw seed encoded as base64
  ///  - Hex string (64 or 128 hex chars)
  ///
  /// Returns {'sk': base64(sk64), 'pk': base64(pk32), 'address': '...'}.
  static Future<Map<String, String>> importFromPrivateKey(String raw) async {
    final trimmed = raw.trim();
    Uint8List keyBytes;

    if (_isHex(trimmed)) {
      keyBytes = Uint8List.fromList(_hexDecode(trimmed));
    } else {
      keyBytes = Uint8List.fromList(base64.decode(_padBase64(trimmed)));
    }

    // 64-byte NaCl sk (seed[32] || pk[32]) — extract pk directly
    if (keyBytes.length == 64) {
      final pk      = NativeCrypto.pkFromSk(keyBytes);
      final address = NativeCrypto.deriveAddress(pk);
      return {
        'sk': base64.encode(keyBytes),
        'pk': base64.encode(pk),
        'address': address,
      };
    }

    // 32-byte seed — derive full keypair via OpenSSL Ed25519
    if (keyBytes.length == 32) {
      return _keypairFromSeed(keyBytes);
    }

    throw Exception('Invalid key length: ${keyBytes.length} bytes');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  View keypair (stealth)
  // ══════════════════════════════════════════════════════════════════════════

  /// Derives the x25519 view public key from the ed25519 signing key.
  /// Used for PVAC registration and stealth receives.
  static Uint8List getViewPublicKey(Uint8List sk) {
    final kp = NativeCrypto.deriveViewKeypair(sk);
    return kp['pk']!;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PVAC lifecycle
  // ══════════════════════════════════════════════════════════════════════════

  /// Whether PVAC (FHE) is available on this device / ABI.
  static bool get pvacAvailable => NativeCrypto.pvacAvailable;

  /// Initialises PVAC with the first 32 bytes of the signing key (seed).
  /// Returns true on success. Must be called after wallet unlock.
  static bool pvacInit(Uint8List sk) {
    if (sk.length < 32) return false;
    final seed = Uint8List.sublistView(sk, 0, 32);
    return NativeCrypto.pvacInit(seed) == 0;
  }

  /// Frees PVAC state. Call on wallet lock / app close.
  static void pvacReset() => NativeCrypto.pvacReset();

  /// Returns the PVAC public key base64 for registration, or null.
  static String? pvacGetPubkeyB64() => NativeCrypto.pvacGetPubkeyB64();

  /// Decrypts a PVAC-encrypted balance cipher string.
  static int pvacDecryptBalance(String cipherStr) =>
      NativeCrypto.pvacDecryptBalance(cipherStr);

  /// Encrypts an arbitrary value using FHE.
  static Map<String, String>? fheEncrypt(int value) {
    final res = NativeCrypto.fheEncrypt(value);
    if (res == null) return null;
    return {
      'ciphertext': res.cipher,
      'amount_commitment': res.commitment,
      'zero_proof': res.zeroProof,
    };
  }

  /// Decrypts an arbitrary FHE ciphertext.
  static int? fheDecrypt(String cipherStr) => NativeCrypto.fheDecrypt(cipherStr);

  // ══════════════════════════════════════════════════════════════════════════
  //  Transaction signing
  // ══════════════════════════════════════════════════════════════════════════

  /// Signs a canonical transaction JSON string using the given 64-byte NaCl
  /// secret key (base64-encoded). Returns base64-encoded 64-byte signature.
  static Future<String> signMessage(String message, String skBase64) async {
    final sk       = Uint8List.fromList(base64.decode(_padBase64(skBase64)));
    final msgBytes = Uint8List.fromList(utf8.encode(message));
    if (sk.length != 64) throw ArgumentError('sk must be 64 bytes');
    final sig = NativeCrypto.sign(sk, msgBytes);
    return base64.encode(sig);
  }

  /// Returns the ed25519 public key (base64) for a base64-encoded 64-byte sk.
  static Future<String> publicKeyFromSk(String skBase64) async {
    final sk = Uint8List.fromList(base64.decode(_padBase64(skBase64)));
    if (sk.length != 64) throw ArgumentError('sk must be 64 bytes');
    final pk = NativeCrypto.pkFromSk(sk);
    return base64.encode(pk);
  }

  /// Builds the canonical JSON for a standard OCT transfer, signs it, and
  /// returns the fully signed transaction as a [Map] ready for submission.
  static Future<Map<String, dynamic>> buildSignedTransfer({
    required String skBase64,
    required String fromAddress,
    required String toAddress,
    required String amount,
    required int nonce,
    String message = '',
    String opType = 'standard',
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // ou (operation units) mirrors webcli: < 1 000 OCT → "10000", ≥ 1 000 OCT → "30000"
    final amountRawInt = int.tryParse(amount) ?? 0;
    final ou = amountRawInt < 1000000000 ? '10000' : '30000';

    final tx = <String, dynamic>{
      'from': fromAddress,
      'to_': toAddress,
      'amount': amount,
      'nonce': nonce,
      'ou': ou,
      'timestamp': timestamp,
      'op_type': opType,
    };
    if (message.isNotEmpty) tx['message'] = message;

    final canonical  = canonicalJson(tx);
    final signature  = await signMessage(canonical, skBase64);
    final pubKeyB64  = await publicKeyFromSk(skBase64);

    tx['signature']  = signature;
    tx['public_key'] = pubKeyB64;
    return tx;
  }

  /// Builds and signs a **contract call** transaction (e.g., token transfer).
  /// Mirrors Android's `signContractCallTx`.
  ///
  /// - [tokenAddress]: the token contract address (goes into `to_`)
  /// - [toAddress]: the actual recipient
  /// - [amount]: the token amount (integer string)
  /// - [ou]: operation units (default "1000")
  static Future<Map<String, dynamic>> buildSignedContractCall({
    required String skBase64,
    required String fromAddress,
    required String tokenAddress,
    required String toAddress,
    required String amount,
    required int nonce,
    String ou = '1000',
  }) async {
    final amountVal = int.tryParse(amount);
    if (amountVal == null || amountVal < 0) {
      throw ArgumentError('amount must be a non-negative integer');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // message = JSON array: [toAddress, amountValue]
    final params = jsonEncode([toAddress, amountVal]);

    final tx = <String, dynamic>{
      'from': fromAddress,
      'to_': tokenAddress,
      'amount': '0',
      'nonce': nonce,
      'ou': ou,
      'timestamp': timestamp,
      'op_type': 'call',
      'encrypted_data': 'transfer',
      'message': params,
    };

    final canonical = canonicalJson(tx);
    final signature = await signMessage(canonical, skBase64);
    final pubKeyB64 = await publicKeyFromSk(skBase64);

    tx['signature']  = signature;
    tx['public_key'] = pubKeyB64;
    return tx;
  }

  /// Builds and signs an **encrypt-balance** transaction.
  /// Mirrors Android's `signEncryptTx`.
  ///
  /// The PVAC FHE encryption, Pedersen commitment, and zero-knowledge proof
  /// are computed by the native layer via [NativeCrypto.pvacEncryptAmount].
  static Future<Map<String, dynamic>> buildSignedEncryptTx({
    required String skBase64,
    required String fromAddress,
    required int amount,
    required int nonce,
  }) async {
    if (!pvacAvailable) throw StateError('PVAC not available on this device');

    final enc = NativeCrypto.pvacEncryptAmount(amount);
    if (enc == null) throw StateError('Failed to encrypt amount via PVAC');

    final encData = jsonEncode({
      'cipher': enc.cipher,
      'amount_commitment': base64.encode(enc.commitment),
      'zero_proof': enc.zeroProof,
      'blinding': base64.encode(enc.blinding),
    });

    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

    final tx = <String, dynamic>{
      'from': fromAddress,
      'to_': fromAddress, // self
      'amount': amount.toString(),
      'nonce': nonce,
      'ou': '10000',
      'timestamp': timestamp,
      'op_type': 'encrypt',
      'encrypted_data': encData,
    };

    final canonical = canonicalJson(tx);
    final signature = await signMessage(canonical, skBase64);
    final pubKeyB64 = await publicKeyFromSk(skBase64);

    tx['signature']  = signature;
    tx['public_key'] = pubKeyB64;
    return tx;
  }

  /// Builds and signs a **decrypt-balance** transaction.
  /// Mirrors Android's `signDecryptTx`.
  static Future<Map<String, dynamic>> buildSignedDecryptTx({
    required String skBase64,
    required String fromAddress,
    required int amount,
    required int nonce,
  }) async {
    if (!pvacAvailable) throw StateError('PVAC not available on this device');

    final enc = NativeCrypto.pvacEncryptAmount(amount);
    if (enc == null) throw StateError('Failed to encrypt amount via PVAC');

    final encData = jsonEncode({
      'cipher': enc.cipher,
      'amount_commitment': base64.encode(enc.commitment),
      'zero_proof': enc.zeroProof,
      'blinding': base64.encode(enc.blinding),
    });

    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

    final tx = <String, dynamic>{
      'from': fromAddress,
      'to_': fromAddress, // self
      'amount': amount.toString(),
      'nonce': nonce,
      'ou': '10000',
      'timestamp': timestamp,
      'op_type': 'decrypt',
      'encrypted_data': encData,
    };

    final canonical = canonicalJson(tx);
    final signature = await signMessage(canonical, skBase64);
    final pubKeyB64 = await publicKeyFromSk(skBase64);

    tx['signature']  = signature;
    tx['public_key'] = pubKeyB64;
    return tx;
  }

  /// Builds and signs a **stealth send** transaction.
  /// Mirrors Android's `stealthPrepare` + `signStealthSendTx`.
  ///
  /// Performs ECDH, FHE encrypt delta, range proofs, and builds stealth_data v5.
  static Future<Map<String, dynamic>> buildSignedStealthTx({
    required String skBase64,
    required String fromAddress,
    required int amount,
    required int nonce,
    required String currentEncCipher,
    required Uint8List theirViewPubkey,
    required String recipientAddress,
  }) async {
    if (!pvacAvailable) throw StateError('PVAC not available on this device');

    final sk = Uint8List.fromList(base64.decode(_padBase64(skBase64)));

    // Stealth prepare: ECDH + stealth tag + claim key + blinding
    final prep = NativeCrypto.stealthPrepare(
      edSk: sk,
      theirViewPubkey: theirViewPubkey,
      recipientAddress: recipientAddress,
    );

    // FHE: build delta cipher, commitment, range proofs
    final delta = NativeCrypto.pvacBuildStealthDelta(amount, currentEncCipher);
    if (delta == null) throw StateError('Failed to build stealth delta (insufficient balance?)');

    // Pedersen commitment for the stealth amount
    final blinding = base64.decode(prep['blinding_b64']!);
    final amtCommit = NativeCrypto.pvacPedersenCommit(amount, Uint8List.fromList(blinding));

    // encrypted amount (FHE cipher of the send amount for recipient)
    final encAmtResult = NativeCrypto.pvacEncryptAmount(amount);
    final encAmountB64 = encAmtResult != null ? encAmtResult.cipher : '';

    final stealthData = jsonEncode({
      'version': 5,
      'delta_cipher': delta.deltaCipher,
      'commitment': base64.encode(delta.commitment),
      'range_proof_delta': delta.rpDelta,
      'range_proof_balance': delta.rpBalance,
      'eph_pub': prep['eph_pub_b64'],
      'stealth_tag': prep['stealth_tag_hex'],
      'enc_amount': encAmountB64,
      'claim_pub': prep['claim_pub_hex'],
      'amount_commitment': amtCommit != null ? base64.encode(amtCommit) : '',
    });

    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

    final tx = <String, dynamic>{
      'from': fromAddress,
      'to_': 'stealth',
      'amount': '0',
      'nonce': nonce,
      'ou': '5000',
      'timestamp': timestamp,
      'op_type': 'stealth',
      'encrypted_data': stealthData,
    };

    final canonical = canonicalJson(tx);
    final signature = await signMessage(canonical, skBase64);
    final pubKeyB64 = await publicKeyFromSk(skBase64);

    tx['signature']  = signature;
    tx['public_key'] = pubKeyB64;
    return tx;
  }

  /// Builds and signs a general transaction with custom opType and optional message/encryptedData.
  /// Mirrors Android's JNI signGeneralTransaction.
  static Future<Map<String, dynamic>> buildSignedGeneralTransaction({
    required String skBase64,
    required String fromAddress,
    required String toAddress,
    required String amount,
    required int nonce,
    required String ou,
    required String opType,
    String? message,
    String? encryptedData,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

    final tx = <String, dynamic>{
      'from': fromAddress,
      'to_': toAddress,
      'amount': amount,
      'nonce': nonce,
      'ou': ou,
      'timestamp': timestamp,
      'op_type': opType,
    };
    if (message != null && message.isNotEmpty) tx['message'] = message;
    if (encryptedData != null && encryptedData.isNotEmpty) {
      tx['encrypted_data'] = encryptedData;
    }

    final canonical = canonicalJson(tx);
    final signature = await signMessage(canonical, skBase64);
    final pubKeyB64 = await publicKeyFromSk(skBase64);

    tx['signature']  = signature;
    tx['public_key'] = pubKeyB64;
    return tx;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Request signing helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Signs the encrypted-balance request:  "octra_encryptedBalance|{address}"
  static Future<String> signBalanceRequest(
      String address, String skBase64) async {
    return signMessage('octra_encryptedBalance|$address', skBase64);
  }

  /// Signs the pvac-registration request:  "register_pvac|{address}"
  static Future<String> signPvacRegister(
      String address, String skBase64) async {
    return signMessage('register_pvac|$address', skBase64);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Internal helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Derives a full keypair from a 32-byte seed using OpenSSL EVP Ed25519.
  static Future<Map<String, String>> _keypairFromSeed(Uint8List seed) async {
    final kp      = NativeCrypto.keygenFromSeed(seed);
    final sk      = kp['sk']!;
    final pk      = kp['pk']!;
    final address = NativeCrypto.deriveAddress(pk);
    return {
      'sk': base64.encode(sk),
      'pk': base64.encode(pk),
      'address': address,
    };
  }

  /// Produces the canonical JSON for signing — exact same logic as the C++ code.
  /// Made accessible for services that build custom transactions.
  static String canonicalJson(Map<String, dynamic> tx) {
    final buf = StringBuffer('{');
    buf.write('"from":"${_jsonEscape(tx['from']!.toString())}"');
    buf.write(',"to_":"${_jsonEscape(tx['to_']!.toString())}"');
    buf.write(',"amount":"${_jsonEscape(tx['amount']!.toString())}"');
    buf.write(',"nonce":${tx['nonce']}');
    buf.write(',"ou":"${_jsonEscape(tx['ou']?.toString() ?? '')}"');
    buf.write(',"timestamp":${_formatTimestamp(tx['timestamp'] as double)}');
    buf.write(',"op_type":"${_jsonEscape(tx['op_type']?.toString() ?? 'standard')}"');
    if (tx.containsKey('encrypted_data') && tx['encrypted_data'] != null) {
      buf.write(',"encrypted_data":"${_jsonEscape(tx['encrypted_data'].toString())}"');
    }
    if (tx.containsKey('message') &&
        tx['message'] != null &&
        tx['message'].toString().isNotEmpty) {
      buf.write(',"message":"${_jsonEscape(tx['message'].toString())}"');
    }
    buf.write('}');
    return buf.toString();
  }

  static String _formatTimestamp(double ts) {
    if (ts == ts.truncateToDouble()) return ts.toInt().toString();
    return ts.toString();
  }

  static String _jsonEscape(String s) {
    final buf = StringBuffer();
    for (final c in s.runes) {
      switch (c) {
        case 0x22: buf.write(r'\"'); break;
        case 0x5c: buf.write(r'\\'); break;
        case 0x08: buf.write(r'\b'); break;
        case 0x0c: buf.write(r'\f'); break;
        case 0x0a: buf.write(r'\n'); break;
        case 0x0d: buf.write(r'\r'); break;
        case 0x09: buf.write(r'\t'); break;
        default:   buf.writeCharCode(c);
      }
    }
    return buf.toString();
  }

  static bool _isHex(String s) =>
      RegExp(r'^[0-9a-fA-F]+$').hasMatch(s) &&
      (s.length == 64 || s.length == 128);

  static List<int> _hexDecode(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  static String _padBase64(String s) {
    final rem = s.length % 4;
    if (rem == 0) return s;
    return s + '=' * (4 - rem);
  }
}
