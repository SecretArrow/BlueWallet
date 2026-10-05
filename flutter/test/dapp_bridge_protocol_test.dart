import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/dapp_bridge_protocol.dart';

/// Defensive tests for the dApp bridge wire registry (RFC-O-1 dual-stack).
/// Pure Dart — no WebView, no network.
void main() {
  group('error codes (RFC-O-1)', () {
    test('match the 0xio guide', () {
      expect(DappBridgeProtocol.noCode, 0);
      expect(DappBridgeProtocol.userRejected, 4001);
      expect(DappBridgeProtocol.unauthorized, 4100);
      expect(DappBridgeProtocol.unsupportedMethod, 4200);
      expect(DappBridgeProtocol.disconnected, 4900);
      expect(DappBridgeProtocol.networkUnavailable, 4901);
    });
  });

  group('canonicalize', () {
    test('trims and null-guards', () {
      expect(DappBridgeProtocol.canonicalize('  octra_requestAccounts  '),
          'octra_requestAccounts');
      expect(DappBridgeProtocol.canonicalize(null), '');
      expect(DappBridgeProtocol.canonicalize('   '), '');
    });
  });

  group('isSupported (both dialects)', () {
    test('legacy dialect keeps working', () {
      for (final m in [
        'octra_accounts',
        'octra_chainId',
        'octra_getBalance',
        'octra_sendTransaction',
        'octra_callContract',
        'octra_callView',
      ]) {
        expect(DappBridgeProtocol.isSupported(m), isTrue, reason: m);
      }
    });

    test('RFC-O-1 aliases dispatch', () {
      expect(DappBridgeProtocol.isSupported('octra_requestAccounts'), isTrue);
      expect(
          DappBridgeProtocol.isSupported('octra_getEncryptedBalance'), isTrue);
    });

    test('unknown stays unknown', () {
      expect(DappBridgeProtocol.isSupported('octra_broadcast'), isFalse);
      expect(DappBridgeProtocol.isSupported(''), isFalse);
      expect(DappBridgeProtocol.isSupported(null), isFalse);
      expect(DappBridgeProtocol.isSupported('eth_sendTransaction'), isFalse);
    });
  });
}
