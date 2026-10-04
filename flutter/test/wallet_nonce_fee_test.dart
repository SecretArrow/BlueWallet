import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/wallet_service.dart';

/// Defensive tests for nonce/fee/hash helpers. Pure logic, no wallet
/// instance, no network.
void main() {
  group('parseNonceValue', () {
    test('accepts ints and numeric strings', () {
      expect(WalletService.parseNonceValue(5), 5);
      expect(WalletService.parseNonceValue(5.0), 5);
      expect(WalletService.parseNonceValue('9'), 9);
      expect(WalletService.parseNonceValue('  12  '), 12);
    });

    test('pending_nonce precedence is decided by callers (map lookup)', () {
      // Mirrors refresh(): pending_nonce ?? nonce.
      Map<String, dynamic> r = {'pending_nonce': 8, 'nonce': 5};
      expect(
          WalletService.parseNonceValue(r['pending_nonce'] ?? r['nonce']), 8);
      r = {'nonce': 5};
      expect(
          WalletService.parseNonceValue(r['pending_nonce'] ?? r['nonce']), 5);
    });

    test('rejects null, garbage and negatives', () {
      expect(WalletService.parseNonceValue(null), 0);
      expect(WalletService.parseNonceValue('abc'), 0);
      expect(WalletService.parseNonceValue(''), 0);
      expect(WalletService.parseNonceValue(-3), 0);
      expect(WalletService.parseNonceValue('-3'), 0);
      expect(WalletService.parseNonceValue([1]), 0);
      expect(WalletService.parseNonceValue(true), 0);
    });

    test('clamps huge values', () {
      expect(WalletService.parseNonceValue(9999999999999), 2147483647);
    });
  });

  group('parseRecommendedFee', () {
    test('valid bucket', () {
      expect(
          WalletService.parseRecommendedFee(
              {'recommended': '1500', 'minimum': '1000'}, 1000),
          1500);
      expect(
          WalletService.parseRecommendedFee({'recommended': 2000}, 1000), 2000);
    });

    test('fallbacks', () {
      expect(WalletService.parseRecommendedFee({}, 1000), 1000);
      expect(
          WalletService.parseRecommendedFee({'recommended': '0'}, 1000), 1000);
      expect(
          WalletService.parseRecommendedFee({'recommended': '-5'}, 1000), 1000);
      expect(WalletService.parseRecommendedFee({'recommended': 'lots'}, 1000),
          1000);
      expect(WalletService.parseRecommendedFee('nope', 1000), 1000);
      expect(WalletService.parseRecommendedFee(null, 1000), 1000);
    });
  });

  group('requireTxHash', () {
    test('returns trimmed hash', () {
      expect(WalletService.requireTxHash({'tx_hash': 'abc'}), 'abc');
      expect(WalletService.requireTxHash({'tx_hash': '  abc  '}), 'abc');
    });

    test('throws on missing/empty hash', () {
      expect(() => WalletService.requireTxHash({}), throwsException);
      expect(
          () => WalletService.requireTxHash({'tx_hash': ''}), throwsException);
      expect(() => WalletService.requireTxHash({'tx_hash': '   '}),
          throwsException);
      expect(() => WalletService.requireTxHash({'tx_hash': null}),
          throwsException);
    });
  });
}
