import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _kPinHashKey = 'pin_hash';
const _kPinSaltKey = 'pin_salt';
const _kPinSet = 'pin_set';

/// PBKDF2-HMAC-SHA256 iteration count (key stretching).
const _kPbkdf2Iterations = 100000;

/// PIN storage with salted + stretched hashing.
///
/// New scheme (setPin): a random 16-byte salt (base64, key `pin_salt`) and
/// a PBKDF2-HMAC-SHA256 hash (100k iterations over `octra_pin_<pin>` with
/// the salt as HMAC key, hex, key `pin_hash`).
///
/// Transparent upgrade: hashes written by the old unsalted scheme (no
/// `pin_salt` present) are verified against the legacy formula and
/// re-written in the salted form on the first successful verifyPin — no
/// user action, nothing sensitive logged.
class PinService {
  /// Wallet PIN policy: minimal 6 digit, maksimal 16 digit (mirrors Android
  /// WalletPinVerifier and both apps' PIN screens). verifyPin intentionally
  /// does NOT enforce this — previously stored PINs must always remain
  /// verifiable.
  static bool isValidPin(String pin) => RegExp(r'^\d{6,16}$').hasMatch(pin);

  /// Salted + stretched hash of [pin] using [saltB64] (base64, 16 bytes)
  /// as the HMAC key.
  @visibleForTesting
  static String computeHash(String pin, String saltB64) {
    final salt = base64Decode(saltB64);
    return _pbkdf2(utf8.encode('octra_pin_$pin'), salt);
  }

  /// The old (pre-salt) formula: a single unsalted SHA-256. Kept only to
  /// verify — and transparently upgrade — legacy stored hashes.
  @visibleForTesting
  static String legacyHash(String pin) =>
      sha256.convert(utf8.encode('octra_pin_$pin')).toString();

  static Future<bool> isPinSet() async {
    try {
      final val = await _storage.read(key: _kPinSet);
      return val == 'true';
    } catch (e) {
      debugPrint('PinService.isPinSet error (secure storage unavailable): $e');
      return false;
    }
  }

  static Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('PIN minimal 6 digit (at least 6 digits, max 16)');
    }
    final salt = _generateSalt();
    final hash = computeHash(pin, salt);
    try {
      await _storage.write(key: _kPinSaltKey, value: salt);
      await _storage.write(key: _kPinHashKey, value: hash);
      await _storage.write(key: _kPinSet, value: 'true');
    } catch (e) {
      debugPrint('PinService.setPin error (secure storage unavailable): $e');
      rethrow;
    }
  }

  static Future<bool> verifyPin(String pin) async {
    try {
      final stored = await _storage.read(key: _kPinHashKey);
      if (stored == null) return false;
      final salt = await _storage.read(key: _kPinSaltKey);
      if (salt == null) {
        // Legacy unsalted hash.
        if (stored != legacyHash(pin)) return false;
        // Correct PIN: transparently upgrade to the salted scheme. A failed
        // write keeps the legacy hash verifiable; the next verify retries.
        try {
          final newSalt = _generateSalt();
          await _storage.write(key: _kPinSaltKey, value: newSalt);
          await _storage.write(
            key: _kPinHashKey,
            value: computeHash(pin, newSalt),
          );
        } catch (e) {
          debugPrint('PinService.verifyPin upgrade write failed: $e');
        }
        return true;
      }
      return stored == computeHash(pin, salt);
    } catch (e) {
      debugPrint('PinService.verifyPin error (secure storage unavailable): $e');
      return false;
    }
  }

  static Future<void> changePin(String newPin) async {
    await setPin(newPin);
  }

  static Future<void> clearPin() async {
    try {
      await _storage.delete(key: _kPinHashKey);
      await _storage.delete(key: _kPinSaltKey);
      await _storage.delete(key: _kPinSet);
    } catch (e) {
      debugPrint('PinService.clearPin error: $e');
    }
  }

  /// Random 16-byte salt, base64-encoded.
  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// PBKDF2-HMAC-SHA256 (single 32-byte block, [salt] as the HMAC key):
  /// iteration 1 hashes the message; each later iteration hashes the
  /// previous output. Returns the final digest as hex.
  static String _pbkdf2(List<int> message, List<int> salt) {
    final hmac = Hmac(sha256, salt);
    var block = hmac.convert(message);
    for (var i = 1; i < _kPbkdf2Iterations; i++) {
      block = hmac.convert(block.bytes);
    }
    return block.toString();
  }
}
