import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/mnemonic_service.dart';
import 'package:octopus_wallet/services/pin_service.dart';

/// Defensive tests for PIN policy. Rejection paths throw before touching
/// secure storage, so they run without plugins. Success paths need the
/// platform channel (integration-covered).
void main() {
  group('isValidPin (mirrors Android WalletPinVerifier: exactly 6 digits)',
      () {
    test('accepts 6 digits', () {
      expect(PinService.isValidPin('123456'), isTrue);
      expect(PinService.isValidPin('000000'), isTrue);
    });

    test('rejects everything else', () {
      for (final bad in [
        '',
        '12345',
        '1234567',
        '12345a',
        'abcdef',
        ' 123456 ',
        '12 456',
      ]) {
        expect(PinService.isValidPin(bad), isFalse, reason: 'for "$bad"');
      }
    });
  });

  group('setPin guards', () {
    test('rejects invalid PINs before touching storage', () {
      for (final bad in ['', '123', '1234567', 'abcdef', '12 456']) {
        expect(() => PinService.setPin(bad), throwsArgumentError,
            reason: 'for "$bad"');
      }
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
      expect(
          MnemonicService.validate(
              List.filled(12, 'abandon').join(' ')),
          isFalse);
    });

    test('rejects unknown words', () {
      expect(
          MnemonicService.validate(valid.replaceFirst('about', 'xyzzy')),
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
      expect(
          MnemonicService.validate(words.sublist(0, 11).join(' ')), isFalse);
      expect(
          MnemonicService.validate('${valid} abandon'), isFalse);
      expect(MnemonicService.validate(''), isFalse);
    });
  });
}
