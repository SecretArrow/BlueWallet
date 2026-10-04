import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

const _storage = FlutterSecureStorage();
const _kBiometricEnabled = 'biometric_enabled';
const _kBiometricPin = 'biometric_pin'; // encrypted PIN for biometric unlock

/// Service for biometric (fingerprint / face) authentication.
/// Only supported on Android and iOS; all methods return safe defaults
/// on desktop platforms.
///
/// Flow:
///   Enable  → user enters PIN → biometric auth → PIN stored encrypted
///   Unlock  → biometric auth → stored PIN retrieved → PinService.verifyPin
///   Disable → clears stored PIN
class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Biometrics are only meaningful on mobile.
  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// Returns true if device hardware supports biometrics AND at least one
  /// biometric is enrolled.
  static Future<bool> isAvailable() async {
    if (!_isMobile) return false;
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final deviceSupported = await _auth.isDeviceSupported();
      return canCheck && deviceSupported;
    } catch (e) {
      debugPrint('BiometricService.isAvailable: $e');
      return false;
    }
  }

  /// Returns true if the user has opted into biometric unlock.
  static Future<bool> isEnabled() async {
    try {
      final val = await _storage.read(key: _kBiometricEnabled);
      return val == 'true';
    } catch (e) {
      return false;
    }
  }

  /// Enables biometric unlock: stores the user's PIN encrypted in secure
  /// storage (protected by the platform keystore / keychain) and sets the
  /// enabled flag. The caller must verify the PIN beforehand.
  static Future<bool> enable(String verifiedPin) async {
    try {
      // First confirm biometric hardware works
      final ok = await authenticate(
        reason: 'Confirm biometric to enable unlock',
      );
      if (!ok) return false;

      // Store PIN in platform-encrypted secure storage
      await _storage.write(key: _kBiometricPin, value: verifiedPin);
      await _storage.write(key: _kBiometricEnabled, value: 'true');
      return true;
    } catch (e) {
      debugPrint('BiometricService.enable: $e');
      return false;
    }
  }

  /// Disables biometric unlock and removes the stored PIN.
  static Future<void> disable() async {
    try {
      await _storage.delete(key: _kBiometricPin);
      await _storage.write(key: _kBiometricEnabled, value: 'false');
    } catch (e) {
      debugPrint('BiometricService.disable: $e');
    }
  }

  /// Authenticates via biometric and returns the stored PIN on success.
  /// Returns null if biometric fails or no PIN is stored.
  static Future<String?> authenticateAndGetPin({
    String reason = 'Authenticate to access your wallet',
  }) async {
    if (!_isMobile) return null;
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (!ok) return null;
      return await _storage.read(key: _kBiometricPin);
    } on PlatformException catch (e) {
      debugPrint(
          'BiometricService.authenticateAndGetPin PlatformException: $e');
      return null;
    } catch (e) {
      debugPrint('BiometricService.authenticateAndGetPin: $e');
      return null;
    }
  }

  /// Prompts the user to authenticate via biometric or device PIN/pattern.
  /// Returns true on success, false on failure or cancelled.
  static Future<bool> authenticate({
    String reason = 'Authenticate to access your wallet',
  }) async {
    if (!_isMobile) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // allow fallback to device PIN/pattern
          stickyAuth: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('BiometricService.authenticate PlatformException: $e');
      return false;
    } catch (e) {
      debugPrint('BiometricService.authenticate: $e');
      return false;
    }
  }
}
