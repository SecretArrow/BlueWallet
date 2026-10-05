import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/wallet_service.dart';

/// Defensive tests for token display formatting. Pure statics.
void main() {
  group('formatTokenBalance', () {
    test('basic shapes', () {
      expect(WalletService.formatTokenBalance('', 6), '0');
      expect(WalletService.formatTokenBalance('0', 6), '0');
      expect(WalletService.formatTokenBalance('1000000', 6), '1');
      expect(WalletService.formatTokenBalance('1500000', 6), '1.5');
      expect(WalletService.formatTokenBalance('1234567', 6), '1.234567');
      expect(WalletService.formatTokenBalance('42', 0), '42');
    });

    test('out-of-range decimals render raw (no hang/OOM)', () {
      expect(WalletService.formatTokenBalance('123', -1), '123');
      expect(WalletService.formatTokenBalance('123', 37), '123');
      expect(
          WalletService.formatTokenBalance('123', 1000000000), '123');
    });

    test('garbage renders raw', () {
      expect(WalletService.formatTokenBalance('abc', 6), 'abc');
    });
  });
}
