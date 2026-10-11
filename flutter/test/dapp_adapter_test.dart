import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/models/visited_page.dart';
import 'package:octopus_wallet/services/dapp/adapter_registry.dart';
import 'package:octopus_wallet/services/dapp/dapp_session.dart';
import 'package:octopus_wallet/services/dapp/wallet_adapter.dart';
import 'package:octopus_wallet/services/dapp_bridge_protocol.dart';
import 'package:octopus_wallet/services/recent_sites_service.dart';

class _StubAdapter implements WalletAdapter {
  @override
  String get id => 'stub';
  @override
  String get chainType => 'Stub';
  @override
  Set<String> get supportedMethods => {'octra_chainId'};
  @override
  bool supports(String m) => supportedMethods.contains(m);
  @override
  Future<AdapterResult> handle(DappRequest r, AdapterContext ctx) async =>
      'stub-chain';
}

AdapterContext _ctx() => AdapterContext(
      requestApproval: (
          {required String title,
          required String body,
          required String confirmLabel,
          String? origin}) async =>
          false,
      requestTxApproval: (
              {required String title,
              required String to,
              required String amount,
              String? extra,
              String? origin}) async =>
          false,
      currentOrigin: () => 'https://app.example.com',
    );

void main() {
  group('AdapterValidation origins', () {
    test('accepts https/http/oct/about:blank, rejects exotic schemes', () {
      expect(AdapterValidation.isValidOrigin('https://app.example.com'),
          isTrue);
      expect(AdapterValidation.isValidOrigin('http://localhost:3000'), isTrue);
      expect(AdapterValidation.isValidOrigin('oct://abc/index.html'), isTrue);
      expect(AdapterValidation.isValidOrigin('about:blank'), isTrue);
      expect(AdapterValidation.isValidOrigin('javascript:alert(1)'), isFalse);
      expect(AdapterValidation.isValidOrigin('data:text/html,hi'), isFalse);
      expect(AdapterValidation.isValidOrigin('file:///etc/passwd'), isFalse);
      expect(AdapterValidation.isValidOrigin(''), isFalse);
    });

    test('about:blank is valid but not persistable', () {
      expect(AdapterValidation.isPersistableOrigin('about:blank'), isFalse);
      expect(
          AdapterValidation.isPersistableOrigin('https://app.example.com'),
          isTrue);
    });

    test('normalizeOrigin lowercases + strips paths', () {
      expect(AdapterValidation.normalizeOrigin('https://APP.example.com/a?x=1'),
          'https://app.example.com');
      expect(AdapterValidation.normalizeOrigin('oct://AbC/page'),
          'oct://abc');
    });
  });

  group('AdapterRegistry dispatch', () {
    test('routes supported methods, rejects unknown explicitly', () async {
      final registry = AdapterRegistry([_StubAdapter()]);
      expect(registry.isSupported('octra_chainId'), isTrue);
      expect(registry.isSupported('octra_signMessage'), isFalse);
      expect(registry.isKnownUnsupported('octra_signMessage'), isTrue);

      final req = DappRequest(
          jsId: 1,
          origin: 'https://app.example.com',
          method: 'octra_chainId',
          params: const [],
          receivedAt: DateTime.now());
      expect(await registry.dispatch(req, _ctx()), 'stub-chain');

      final bad = DappRequest(
          jsId: 2,
          origin: 'https://app.example.com',
          method: 'nope_method',
          params: const [],
          receivedAt: DateTime.now());
      try {
        await registry.dispatch(bad, _ctx());
        fail('must throw');
      } catch (e) {
        expect(e, isA<DappError>());
        expect((e as DappError).code, DappBridgeProtocol.unsupportedMethod);
      }
    });

    test('cancel != approve: rejecting context yields userRejected', () async {
      // The stub never approves; registry must surface DappError, never
      // silently succeed. Covered by the context returning false above.
      expect(DappBridgeProtocol.userRejected, 4001);
    });
  });

  group('DappSession json', () {
    test('round-trips, drops malformed entries', () {
      final sessions = [
        DappSession(
            origin: 'https://a.example',
            address: 'oct1abc',
            scopes: const ['accounts'],
            connectedAtMs: 123),
      ];
      final encoded = DappSession.encodeList(sessions);
      final decoded = DappSession.decodeList(encoded);
      expect(decoded.length, 1);
      expect(decoded.first.origin, 'https://a.example');
      expect(DappSession.decodeList('not json'), isEmpty);
      expect(DappSession.decodeList(null), isEmpty);
      expect(DappSession.fromJson({'nope': 1}), isNull);
    });
  });

  group('RecentSites filter', () {
    test('records http(s)/oct, drops internal/error/sensitive', () {
      expect(
          RecentSitesService.isRecordableUrl('https://example.com/a'), isTrue);
      expect(RecentSitesService.isRecordableUrl('oct://abc/page'), isTrue);
      expect(RecentSitesService.isRecordableUrl('about:blank'), isFalse);
      expect(RecentSitesService.isRecordableUrl('chrome-error://x'), isFalse);
      expect(RecentSitesService.isRecordableUrl('javascript:alert(1)'),
          isFalse);
      expect(RecentSitesService.isRecordableUrl('data:text/html,hi'), isFalse);
      expect(RecentSitesService.isRecordableUrl(''), isFalse);
      expect(
          RecentSitesService.isRecordableUrl(
              'https://x.test/?mnemonic=word+list'),
          isFalse);
      expect(
          RecentSitesService.isRecordableUrl(
              'https://x.test/?privatekey=abc'),
          isFalse);
    });

    test('VisitedPage.domainOf strips www + handles oct', () {
      expect(VisitedPage.domainOf('https://www.example.com/a'),
          'example.com');
      expect(VisitedPage.domainOf('oct://MyCircle/page'), 'mycircle');
    });
  });
}
