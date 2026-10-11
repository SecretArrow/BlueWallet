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

  group('third-party surface (0xio OctraProviderAdapter)', () {
    test('connect reads + session calls dispatch', () {
      for (final m in [
        'octra_networkInfo',
        'octra_permissions',
        'disconnect',
        'getBalance',
        'getPublicKey',
        'octra_sendContractTransaction',
        'octra_switchNetwork',
        // View/submit share octra_callContract (shape-dispatched downstream).
        'octra_callContract',
      ]) {
        expect(DappBridgeProtocol.isSupported(m), isTrue, reason: m);
      }
    });

    test('unserved methods are named, never silent', () {
      for (final m in [
        'octra_signTransaction',
        'octra_submitTransaction',
        'octra_signMessage',
        'octra_encryptBalance',
        'octra_decryptBalance',
        'octra_sendPrivateTransfer',
        'octra_claimStealth',
        'octra_getPrivateCapabilities',
        'octra_getPrivateBalance',
        'octra_encryptValue',
        'octra_decryptValue',
        'octra_makeZeroProof',
        'octra_makeRangeProof',
        'octra_registerPrivateViewKey',
        'octra_sendContractTransactionSequence',
        'octra_submitBatch',
      ]) {
        expect(DappBridgeProtocol.isKnownUnsupported(m), isTrue, reason: m);
        expect(DappBridgeProtocol.isSupported(m), isFalse, reason: m);
      }
      expect(DappBridgeProtocol.isKnownUnsupported('octra_broadcast'), isFalse);
      expect(DappBridgeProtocol.isKnownUnsupported(null), isFalse);
      expect(DappBridgeProtocol.isKnownUnsupported('  octra_signMessage  '),
          isTrue);
    });

    test('requestedPermissions defaults safely', () {
      expect(DappBridgeProtocol.requestedPermissions(null), ['accounts']);
      expect(DappBridgeProtocol.requestedPermissions([]), ['accounts']);
      expect(DappBridgeProtocol.requestedPermissions([{}]), ['accounts']);
      expect(DappBridgeProtocol.requestedPermissions('nope'), ['accounts']);
      expect(
        DappBridgeProtocol.requestedPermissions([
          {
            'permissions': ['accounts', 'public_transactions', 'accounts', ' ']
          }
        ]),
        ['accounts', 'public_transactions'],
      );
    });

    test('txObject accepts both shapes', () {
      expect(
          DappBridgeProtocol.txObject([
            {'to': 'octX', 'amount': '1'}
          ])['to'],
          'octX');
      expect(DappBridgeProtocol.txObject({'to': 'octY', 'amount': '2'})['to'],
          'octY');
      for (final bad in [
        null,
        [],
        [42],
        42,
        's'
      ]) {
        expect(() => DappBridgeProtocol.txObject(bad),
            throwsA(isA<FormatException>()),
            reason: '$bad');
      }
    });

    test('resolveTxAmount is exact-arithmetic only', () {
      expect(DappBridgeProtocol.resolveTxAmount({'amount': '10500000'}),
          '10500000');
      expect(DappBridgeProtocol.resolveTxAmount({'amountOct': '10.5'}),
          '10500000');
      expect(DappBridgeProtocol.resolveTxAmount({'amount': '000'}), '0');
      for (final bad in [
        {'amount': '1', 'amountOct': '1'},
        <String, dynamic>{},
        {'amount': '-5'},
        {'amount': '1.5'},
        {'amountOct': '0.30000000000000004'},
        {'amountOct': 'abc'},
        {'amountOct': '1.2345678'},
      ]) {
        expect(() => DappBridgeProtocol.resolveTxAmount(bad),
            throwsA(isA<FormatException>()),
            reason: '$bad');
      }
    });

    test('octToMicro converts exactly', () {
      expect(DappBridgeProtocol.octToMicro('0.000001'), '1');
      expect(DappBridgeProtocol.octToMicro('2'), '2000000');
      expect(DappBridgeProtocol.octToMicro('0.000000'), '0');
      expect(() => DappBridgeProtocol.octToMicro(''),
          throwsA(isA<FormatException>()));
    });

    test('window.wallet facade dispatches reads', () {
      for (final m in [
        'wallet_connect',
        'wallet_disconnect',
        'wallet_getAccounts',
        'wallet_getAddress',
        'wallet_getBalance',
        'wallet_getNetwork',
        'wallet_getNetworkInfo',
        'wallet_getNetworks',
        'wallet_getChainId',
        'wallet_getPermissions',
        'wallet_ping',
      ]) {
        expect(DappBridgeProtocol.isSupported(m), isTrue, reason: m);
        // orion_wallet_* is the same operation under the brand prefix.
        expect(DappBridgeProtocol.isSupported('orion_$m'), isTrue,
            reason: 'orion_$m');
      }
      for (final m in [
        'wallet_signMessage',
        'wallet_signTypedData',
        'wallet_approveContract',
        'wallet_signContract',
        'wallet_signTransfer',
      ]) {
        expect(DappBridgeProtocol.isKnownUnsupported(m), isTrue, reason: m);
        expect(DappBridgeProtocol.isSupported(m), isFalse, reason: m);
      }
    });

    test('canonicalize folds the orion_ alias', () {
      expect(DappBridgeProtocol.canonicalize('orion_wallet_getAccounts'),
          'wallet_getAccounts');
      expect(DappBridgeProtocol.canonicalize('  orion_wallet_ping  '),
          'wallet_ping');
      expect(DappBridgeProtocol.canonicalize('octra_broadcast'),
          'octra_broadcast');
    });

    test('networkIdForChain maps both networks', () {
      expect(
          DappBridgeProtocol.networkIdForChain('octra-mainnet-1'), 'mainnet');
      expect(DappBridgeProtocol.networkIdForChain('octra-devnet-1'), 'devnet');
      expect(DappBridgeProtocol.networkIdForChain(''), 'devnet');
      expect(DappBridgeProtocol.networkIdForChain(null), 'devnet');
    });

    test('buildPing answers without side effects', () {
      final ping = DappBridgeProtocol.buildPing(
        connected: true,
        locked: false,
        origin: 'https://dapp.example',
        tsMs: 123,
      );
      expect(ping['pong'], isTrue);
      expect(ping['v'], 1);
      expect(ping['connected'], isTrue);
      expect(ping['locked'], isFalse);
      expect(ping['origin'], 'https://dapp.example');
      expect(ping['ts'], 123);
      expect((ping['capabilities'] as List).first, 'ping');
      expect(
        DappBridgeProtocol.buildPing(
            connected: false, locked: true, origin: '', tsMs: 0)['origin'],
        '',
      );
    });

    test('isViewCall splits by attached value', () {
      expect(
          DappBridgeProtocol.isViewCall(
              {'contract': 'c', 'method': 'm', 'params': []}),
          isTrue);
      expect(
          DappBridgeProtocol.isViewCall(
              {'contract': 'c', 'method': 'm', 'params': [], 'caller': 'x'}),
          isTrue);
      expect(
          DappBridgeProtocol.isViewCall(
              {'contract': 'c', 'method': 'm', 'amount': '0'}),
          isFalse);
      expect(
          DappBridgeProtocol.isViewCall(
              {'contract': 'c', 'method': 'm', 'ou': '10000'}),
          isFalse);
    });
  });
}
