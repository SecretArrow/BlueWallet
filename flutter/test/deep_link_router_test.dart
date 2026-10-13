import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/deep_link_router.dart';

/// Full parse matrix for the wallet's external deep-link schemes.
void main() {
  group('DeepLinkRoute.parse — send links', () {
    test('parses to + amount', () {
      final r = DeepLinkRoute.parse('octra://send?to=oct1qabcdef&amount=1.5');
      expect(r, isNotNull);
      expect(r!.type, DeepLinkRouteType.send);
      expect(r.to, 'oct1qabcdef');
      expect(r.amount, 1.5);
      expect(r.raw, 'octra://send?to=oct1qabcdef&amount=1.5');
    });

    test('amount is optional', () {
      final r = DeepLinkRoute.parse('octra://send?to=oct1qabcdef');
      expect(r!.type, DeepLinkRouteType.send);
      expect(r.to, 'oct1qabcdef');
      expect(r.amount, isNull);
    });

    test('amount parse errors degrade to null amount (link stays valid)', () {
      final r = DeepLinkRoute.parse('octra://send?to=oct1qabcdef&amount=abc');
      expect(r!.type, DeepLinkRouteType.send);
      expect(r.to, 'oct1qabcdef');
      expect(r.amount, isNull);
    });

    test('missing to → null', () {
      expect(DeepLinkRoute.parse('octra://send'), isNull);
      expect(DeepLinkRoute.parse('octra://send?amount=1'), isNull);
      expect(DeepLinkRoute.parse('octra://send?to='), isNull);
    });

    test('to not starting with oct → null', () {
      expect(DeepLinkRoute.parse('octra://send?to=btc1xyz'), isNull);
      expect(DeepLinkRoute.parse('octra://send?to=0xdeadbeef'), isNull);
    });

    test('percent-encoded to is decoded', () {
      final r = DeepLinkRoute.parse('octra://send?to=oct1%71abc');
      expect(r!.to, 'oct1qabc');
    });

    test('uppercase send host still routes to send, not a circle page', () {
      final r = DeepLinkRoute.parse('octra://SEND?to=oct1qabc');
      expect(r!.type, DeepLinkRouteType.send);
    });
  });

  group('DeepLinkRoute.parse — circle pages', () {
    test('octra://<circleId> → octPage with raw preserved', () {
      final r = DeepLinkRoute.parse('octra://AbC123XyZ');
      expect(r!.type, DeepLinkRouteType.octPage);
      expect(r.raw, 'octra://AbC123XyZ');
      expect(r.to, isNull);
      expect(r.amount, isNull);
    });

    test('octra://<circleId>/path → octPage', () {
      final r = DeepLinkRoute.parse('octra://AbC123XyZ/page.html');
      expect(r!.type, DeepLinkRouteType.octPage);
      expect(r.raw, 'octra://AbC123XyZ/page.html');
    });

    test('bare octra:// → null', () {
      expect(DeepLinkRoute.parse('octra://'), isNull);
    });
  });

  group('DeepLinkRoute.parse — wallet connect', () {
    test('octra-wallet://connect → walletConnect', () {
      final r = DeepLinkRoute.parse('octra-wallet://connect');
      expect(r!.type, DeepLinkRouteType.walletConnect);
      expect(r.raw, 'octra-wallet://connect');
    });

    test('octra-wallet:// action with query → walletConnect', () {
      final r =
          DeepLinkRoute.parse('octra-wallet://sign-tx?to=oct1abc&amount=1');
      expect(r!.type, DeepLinkRouteType.walletConnect);
    });

    test('bare octra-wallet:// → null', () {
      expect(DeepLinkRoute.parse('octra-wallet://'), isNull);
    });
  });

  group('DeepLinkRoute.parse — rejections', () {
    test('non-wallet schemes → null', () {
      expect(DeepLinkRoute.parse('https://octra.example'), isNull);
      expect(DeepLinkRoute.parse('http://example.com'), isNull);
      // oct:// is the *internal* browser scheme, not an external deep link.
      expect(DeepLinkRoute.parse('oct://circle'), isNull);
    });

    test('empty / whitespace / garbage → null', () {
      expect(DeepLinkRoute.parse(''), isNull);
      expect(DeepLinkRoute.parse('   '), isNull);
      expect(DeepLinkRoute.parse('octra'), isNull);
      expect(DeepLinkRoute.parse('wallet-octra://x'), isNull);
      expect(DeepLinkRoute.parse('not a url at all'), isNull);
    });

    test('scheme matching is case-insensitive, circle IDs keep case', () {
      final r = DeepLinkRoute.parse('OCTRA://AbC');
      expect(r!.type, DeepLinkRouteType.octPage);
      expect(r.raw, 'OCTRA://AbC');
      expect(
        DeepLinkRoute.parse('OCTRA-WALLET://connect')!.type,
        DeepLinkRouteType.walletConnect,
      );
    });

    test('surrounding whitespace is trimmed', () {
      final r = DeepLinkRoute.parse('  octra://send?to=oct1q  ');
      expect(r!.to, 'oct1q');
    });
  });
}
