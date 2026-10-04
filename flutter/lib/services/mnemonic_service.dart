import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'native_crypto.dart';
import 'bip39_wordlist.dart';

/// BIP-39 mnemonic generation + validation, and SLIP-0010 Ed25519
/// hierarchical-deterministic key derivation.
///
/// Mnemonic → seed (PBKDF2-HMAC-SHA512, 2048 rounds)
/// Seed     → SLIP-0010 master key pair
/// Path     → hardened child key at each component (Ed25519 SLIP-0010
///            only supports fully hardened derivation)
///
/// Resulting 32-byte child seed is fed into [NativeCrypto.keygenFromSeed]
/// to produce the Ed25519 sk+pk used by the Octra wallet.
class MnemonicService {
  MnemonicService._();

  // ── Word-list helpers ─────────────────────────────────────────────────────

  static final Map<String, int> _wordIndex = () {
    final m = <String, int>{};
    for (int i = 0; i < kBip39English.length; i++) m[kBip39English[i]] = i;
    return m;
  }();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generates a random 12-word BIP-39 mnemonic phrase (128 bits entropy).
  static String generate() {
    // 128 bits = 16 bytes
    final entropy = NativeCrypto.randomBytes(16);
    return _entropyToMnemonic(entropy);
  }

  /// Validates a mnemonic (checksum + word list check).
  static bool validate(String mnemonic) {
    try {
      _mnemonicToEntropy(mnemonic);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Derives a wallet keypair from [mnemonic] at [path] (SLIP-0010 Ed25519).
  ///
  /// Returns a map with:
  ///   'sk'      → base64(64-byte TweetNaCl secret key)
  ///   'pk'      → base64(32-byte public key)
  ///   'address' → octra address string
  ///   'seed32'  → base64(32-byte child seed — not stored, only returned for
  ///               display / verification)
  static Map<String, String> deriveKeypair({
    required String mnemonic,
    required String path,
    String passphrase = '',
  }) {
    final bip39Seed = _mnemonicToSeed(mnemonic, passphrase: passphrase);
    final childSeed = _slip0010DeriveKey(bip39Seed, path);
    final kp = NativeCrypto.keygenFromSeed(childSeed);
    final address = NativeCrypto.deriveAddress(kp['pk']!);
    return {
      'sk': base64.encode(kp['sk']!),
      'pk': base64.encode(kp['pk']!),
      'address': address,
      'seed32': base64.encode(childSeed),
    };
  }

  /// Parses a derivation path string and returns the clean path.
  /// Throws [FormatException] on invalid input.
  static String normalizePath(String raw) {
    final clean = raw.trim();
    _parsePath(clean); // will throw if invalid
    return clean;
  }

  // ── BIP-39 internal ───────────────────────────────────────────────────────

  static String _entropyToMnemonic(Uint8List entropy) {
    assert(entropy.length == 16); // 128 bits
    // checksum = first (len/32) bits of SHA-256(entropy) → 4 bits for 128-bit
    final checkHash = sha256.convert(entropy).bytes;
    final checksumBits = entropy.length * 8 ~/ 32; // = 4
    // Build a bit string: entropy bits + checksum bits
    final totalBits = entropy.length * 8 + checksumBits;
    final bits = _Bits(totalBits);
    for (int byteIdx = 0; byteIdx < entropy.length; byteIdx++) {
      for (int bit = 7; bit >= 0; bit--) {
        bits.set(byteIdx * 8 + (7 - bit), (entropy[byteIdx] >> bit) & 1);
      }
    }
    for (int bit = 0; bit < checksumBits; bit++) {
      final b = (checkHash[0] >> (7 - bit)) & 1;
      bits.set(entropy.length * 8 + bit, b);
    }
    final wordCount = totalBits ~/ 11; // = 12
    final words = <String>[];
    for (int w = 0; w < wordCount; w++) {
      int idx = 0;
      for (int b = 0; b < 11; b++) {
        idx = (idx << 1) | bits.get(w * 11 + b);
      }
      words.add(kBip39English[idx]);
    }
    return words.join(' ');
  }

  static Uint8List _mnemonicToEntropy(String mnemonic) {
    final words = _normalizeWords(mnemonic);
    if (words.length != 12) throw FormatException('Expected 12 words');
    for (final w in words) {
      if (!_wordIndex.containsKey(w)) throw FormatException('Unknown word: $w');
    }
    final totalBits = words.length * 11; // 132
    final bits = _Bits(totalBits);
    for (int w = 0; w < words.length; w++) {
      final idx = _wordIndex[words[w]]!;
      for (int b = 10; b >= 0; b--) {
        bits.set(w * 11 + (10 - b), (idx >> b) & 1);
      }
    }
    // entropy = first 128 bits, checksum = last 4 bits
    final entropy = Uint8List(16);
    for (int byteIdx = 0; byteIdx < 16; byteIdx++) {
      int val = 0;
      for (int b = 0; b < 8; b++) {
        val = (val << 1) | bits.get(byteIdx * 8 + b);
      }
      entropy[byteIdx] = val;
    }
    // Verify checksum
    final checkHash = sha256.convert(entropy).bytes;
    final checksumBits = 4;
    for (int b = 0; b < checksumBits; b++) {
      final expected = (checkHash[0] >> (7 - b)) & 1;
      final actual = bits.get(128 + b);
      if (expected != actual) throw FormatException('Checksum mismatch');
    }
    return entropy;
  }

  /// BIP-39 seed derivation: PBKDF2(mnemonic, "mnemonic"+passphrase, 2048, 512).
  static Uint8List _mnemonicToSeed(String mnemonic, {String passphrase = ''}) {
    final password = utf8.encode(mnemonic.trim());
    final salt = utf8.encode('mnemonic$passphrase');
    return _pbkdf2HmacSha512(password, salt, 2048, 64);
  }

  // ── SLIP-0010 Ed25519 ─────────────────────────────────────────────────────

  static Uint8List _slip0010DeriveKey(Uint8List seed, String path) {
    // Master key
    final masterI = _hmacSha512(utf8.encode('ed25519 seed'), seed);
    var key = Uint8List.fromList(masterI.sublist(0, 32));
    var cc  = Uint8List.fromList(masterI.sublist(32));

    final components = _parsePath(path);
    for (final index in components) {
      final data = Uint8List(37);
      data[0] = 0x00;
      data.setRange(1, 33, key);
      data[33] = (index >> 24) & 0xff;
      data[34] = (index >> 16) & 0xff;
      data[35] = (index >> 8) & 0xff;
      data[36] = index & 0xff;
      final childI = _hmacSha512(cc, data);
      key = Uint8List.fromList(childI.sublist(0, 32));
      cc  = Uint8List.fromList(childI.sublist(32));
    }
    return key;
  }

  /// Parses a derivation path like "m/44'/540'/0'/0'/0'" into a list of
  /// uint32 index values (with hardened bit set where applicable).
  static List<int> _parsePath(String path) {
    var p = path.trim();
    if (p.startsWith('m/') || p.startsWith('M/')) {
      p = p.substring(2);
    } else if (p == 'm' || p == 'M') {
      return [];
    }
    final parts = p.split('/');
    final result = <int>[];
    for (final part in parts) {
      if (part.isEmpty) throw FormatException('Empty path component');
      final hardened = part.endsWith("'");
      final numStr = hardened ? part.substring(0, part.length - 1) : part;
      final n = int.tryParse(numStr);
      if (n == null || n < 0) throw FormatException('Invalid index: $part');
      // SLIP-0010 Ed25519 requires all components to be hardened
      result.add(n | 0x80000000);
    }
    return result;
  }

  // ── Crypto helpers ────────────────────────────────────────────────────────

  static Uint8List _hmacSha512(List<int> key, List<int> data) {
    final hmac = Hmac(sha512, key);
    return Uint8List.fromList(hmac.convert(data).bytes);
  }

  /// PBKDF2-HMAC-SHA512.
  static Uint8List _pbkdf2HmacSha512(
      List<int> password, List<int> salt, int iterations, int dkLen) {
    const hLen = 64; // SHA-512 output bytes
    final blocks = (dkLen / hLen).ceil();
    final dk = <int>[];
    for (int i = 1; i <= blocks; i++) {
      // U1 = HMAC(password, salt || INT(i))
      final saltBlock = Uint8List(salt.length + 4);
      saltBlock.setRange(0, salt.length, salt);
      saltBlock[salt.length]     = (i >> 24) & 0xff;
      saltBlock[salt.length + 1] = (i >> 16) & 0xff;
      saltBlock[salt.length + 2] = (i >> 8) & 0xff;
      saltBlock[salt.length + 3] = i & 0xff;

      var u = _hmacSha512(password, saltBlock);
      final block = List<int>.from(u);
      for (int j = 1; j < iterations; j++) {
        u = _hmacSha512(password, u);
        for (int k = 0; k < hLen; k++) block[k] ^= u[k];
      }
      dk.addAll(block);
    }
    return Uint8List.fromList(dk.sublist(0, dkLen));
  }

  static List<String> _normalizeWords(String mnemonic) => mnemonic
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
}

// ── Bitfield helper ───────────────────────────────────────────────────────────

class _Bits {
  final List<int> _data;
  _Bits(int count) : _data = List.filled(count, 0);
  void set(int pos, int bit) => _data[pos] = bit;
  int get(int pos) => _data[pos];
}
