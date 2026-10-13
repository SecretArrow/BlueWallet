import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/mnemonic_service.dart';
import 'package:octopus_wallet/services/pin_service.dart';

/// Defensive tests for PIN policy. Rejection paths throw before touching
/// secure storage, so they run without plugins. Success paths need the
/// platform channel (integration-covered).
void main() {
  group('isValidPin (baru: minimal 6 digit, maksimal 16 digit)', () {
    test('accepts 6 digits (legacy) and 12 digits', () {
      expect(PinService.isValidPin('123456'), isTrue);
      expect(PinService.isValidPin('000000'), isTrue);
      expect(PinService.isValidPin('123456789012'), isTrue);
    });

    test('rejects 5-digit PINs', () {
      expect(PinService.isValidPin('12345'), isFalse);
    });

    test('rejects everything else', () {
      for (final bad in [
        '',
        '12345',
        '12345a',
        'abcdef',
        ' 123456 ',
        '12 456',
        '11111111111111111',
      ]) {
        expect(PinService.isValidPin(bad), isFalse, reason: 'for "$bad"');
      }
    });
  });

  group('setPin guards', () {
    test('rejects invalid PINs before touching storage', () {
      for (final bad in ['', '123', '12345', 'abcdef', '12 456']) {
        expect(() => PinService.setPin(bad), throwsArgumentError,
            reason: 'for "$bad"');
      }
    });
  });

  group('PIN hashing (salted + stretched, PBKDF2-HMAC-SHA256)', () {
    // base64 of 16 zero bytes / 16 one-bytes.
    const saltA = 'AAAAAAAAAAAAAAAAAAAAAA==';
    const saltB = 'AQEBAQEBAQEBAQEBAQEBAQ==';

    test('computeHash is deterministic for pin + salt', () {
      expect(PinService.computeHash('123456', saltA),
          PinService.computeHash('123456', saltA));
    });

    test('different salts produce different hashes', () {
      final a = PinService.computeHash('123456', saltA);
      final b = PinService.computeHash('123456', saltB);
      expect(a, isNot(b));
    });

    test('different PINs produce different hashes', () {
      expect(PinService.computeHash('123456', saltA),
          isNot(PinService.computeHash('654321', saltA)));
    });

    test('computeHash output is a SHA-256 hex digest (64 hex chars)', () {
      expect(
        RegExp(r'^[0-9a-f]{64}$')
            .hasMatch(PinService.computeHash('123456', saltA)),
        isTrue,
      );
    });

    test('legacyHash equals the old unsalted formula', () {
      final expected =
          sha256.convert(utf8.encode('octra_pin_123456')).toString();
      expect(PinService.legacyHash('123456'), expected);
      // And differs from the salted scheme.
      expect(PinService.legacyHash('123456'),
          isNot(PinService.computeHash('123456', saltA)));
    });
  });

  group('BIP-39 vectors (official test vectors, both apps implement)', () {
    // Vector 1: entropy 0x00000000000000000000000000000000.
    const valid = 'abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon abandon about';

    test('accepts the official vector', () {
      expect(MnemonicService.validate(valid), isTrue);
    });

    test('rejects bad checksum (all-abandon)', () {
      expect(MnemonicService.validate(List.filled(12, 'abandon').join(' ')),
          isFalse);
    });

    test('rejects unknown words', () {
      expect(MnemonicService.validate(valid.replaceFirst('about', 'xyzzy')),
          isFalse);
    });

    test('accepts pasted phrases (case + whitespace normalized)', () {
      expect(
          MnemonicService.validate(
              '  ABANDON\nabandon\tabandon abandon abandon abandon abandon abandon abandon abandon abandon ABOUT  '),
          isTrue);
    });

    test('rejects wrong word counts', () {
      final words = valid.split(' ');
      expect(MnemonicService.validate(words.sublist(0, 11).join(' ')), isFalse);
      expect(MnemonicService.validate('$valid abandon'), isFalse);
      expect(MnemonicService.validate(''), isFalse);
    });
  });
}
