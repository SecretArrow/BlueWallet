import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/oct_url.dart';

/// Defensive tests for oct:// URL handling. Pure Dart, no network.
/// Includes the exact production URL from the field report.
void main() {
  const fieldUrl =
      'oct://oct99BWHFpV5r54DXKc2FhsBmZEaS6Q8zvCQrHRgXUcK4Fk/index.html';
  const fieldId = 'oct99BWHFpV5r54DXKc2FhsBmZEaS6Q8zvCQrHRgXUcK4Fk';

  group('isOctUrl', () {
    test('matches case-insensitively', () {
      expect(OctUrl.isOctUrl(fieldUrl), isTrue);
      expect(OctUrl.isOctUrl('OCT://abc/'), isTrue);
      expect(OctUrl.isOctUrl('https://x'), isFalse);
      expect(OctUrl.isOctUrl(''), isFalse);
    });
  });

  group('parse (field URL)', () {
    test('splits the reported URL, preserving base58 case', () {
      final ref = OctUrl.parse(fieldUrl);
      expect(ref.circleId, fieldId);
      expect(ref.path, '/index.html');
    });

    test('bare ID defaults to /index.html', () {
      final ref = OctUrl.parse('oct://$fieldId');
      expect(ref.circleId, fieldId);
      expect(ref.path, '/index.html');
    });

    test('strips query and fragment', () {
      final ref = OctUrl.parse('oct://abc/page.html?x=1#frag');
      expect(ref.circleId, 'abc');
      expect(ref.path, '/page.html');
    });

    test('rejects empty ID and non-oct URLs', () {
      expect(() => OctUrl.parse('oct://'), throwsArgumentError);
      expect(() => OctUrl.parse('oct:///x'), throwsArgumentError);
      expect(() => OctUrl.parse('https://x'), throwsArgumentError);
    });
  });

  group('gatewayHttpUrl', () {
    test('builds the local gateway URL', () {
      expect(OctUrl.gatewayHttpUrl(fieldId, '/index.html'),
          'http://127.0.0.1:8420/oct/$fieldId/index.html');
      expect(OctUrl.gatewayHttpUrl('a', '', port: 9000),
          'http://127.0.0.1:9000/oct/a/index.html');
      expect(() => OctUrl.gatewayHttpUrl('', '/x'), throwsArgumentError);
    });
  });

  group('cleanMime / isTextMime', () {
    test('strips parameters and falls back safely', () {
      expect(OctUrl.cleanMime('text/html; charset=utf-8'), 'text/html');
      expect(OctUrl.cleanMime(''), 'application/octet-stream');
      expect(OctUrl.cleanMime(null), 'application/octet-stream');
    });

    test('classifies correctly', () {
      expect(OctUrl.isTextMime('text/html'), isTrue);
      expect(OctUrl.isTextMime('application/javascript'), isTrue);
      expect(OctUrl.isTextMime('image/svg+xml'), isTrue);
      expect(OctUrl.isTextMime('image/png'), isFalse);
      expect(OctUrl.isTextMime('font/woff2'), isFalse);
    });
  });
}
