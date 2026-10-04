import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _kPinHashKey = 'pin_hash';
const _kPinSet = 'pin_set';

class PinService {
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
    final hash = _hash(pin);
    try {
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
      return stored == _hash(pin);
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
      await _storage.delete(key: _kPinSet);
    } catch (e) {
      debugPrint('PinService.clearPin error: $e');
    }
  }

  static String _hash(String pin) {
    final bytes = utf8.encode('octra_pin_$pin');
    return sha256.convert(bytes).toString();
  }
}
