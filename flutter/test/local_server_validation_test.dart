import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/local_web_server_service.dart';

/// Defensive tests for local-server auth + parameter validation.
/// Pure statics — no server is started, no network is touched.
void main() {
  group('isAuthorizedToken', () {
    test('accepts the exact Bearer token', () {
      expect(LocalWebServerService.isAuthorizedToken('abc123', 'Bearer abc123'),
          isTrue);
      expect(
          LocalWebServerService.isAuthorizedToken(
              'abc123', 'Bearer   abc123  '),
          isTrue);
    });

    test('rejects mismatch and malformed headers', () {
      expect(LocalWebServerService.isAuthorizedToken('abc123', 'Bearer wrong'),
          isFalse);
      expect(LocalWebServerService.isAuthorizedToken('abc123', 'Bearer '),
          isFalse);
      expect(
          LocalWebServerService.isAuthorizedToken('abc123', 'Bearer'), isFalse);
      expect(LocalWebServerService.isAuthorizedToken('abc123', 'Basic abc123'),
          isFalse);
      expect(LocalWebServerService.isAuthorizedToken('abc123', null), isFalse);
      expect(LocalWebServerService.isAuthorizedToken('abc123', ''), isFalse);
    });

    test('fails closed without a configured token', () {
      expect(LocalWebServerService.isAuthorizedToken('', 'Bearer abc123'),
          isFalse);
      expect(LocalWebServerService.isAuthorizedToken('', ''), isFalse);
    });
  });

  group('parseBoundedQueryInt', () {
    test('defaults, parses and clamps', () {
      expect(
          LocalWebServerService.parseBoundedQueryInt({}, 'limit', 20, 1, 200),
          20);
      expect(
          LocalWebServerService.parseBoundedQueryInt(
              {'limit': '50'}, 'limit', 20, 1, 200),
          50);
      expect(
          LocalWebServerService.parseBoundedQueryInt(
              {'limit': 'abc'}, 'limit', 20, 1, 200),
          20);
      expect(
          LocalWebServerService.parseBoundedQueryInt(
              {'limit': '-5'}, 'limit', 20, 1, 200),
          1);
      expect(
          LocalWebServerService.parseBoundedQueryInt(
              {'limit': '99999'}, 'limit', 20, 1, 200),
          200);
      expect(
          LocalWebServerService.parseBoundedQueryInt(
              {'offset': '-1'}, 'offset', 0, 0, 1000000),
          0);
    });
  });

  group('mimeTypeFor', () {
    test('.mjs is served as a script type (ES modules need it)', () {
      expect(LocalWebServerService.mimeTypeFor('adapter/index.mjs'),
          startsWith('application/javascript'));
      expect(LocalWebServerService.mimeTypeFor('adapter/boot.mjs'),
          startsWith('application/javascript'));
      expect(LocalWebServerService.mimeTypeFor('swap.js'),
          startsWith('application/javascript'));
      expect(LocalWebServerService.mimeTypeFor('swap.html'),
          startsWith('text/html'));
      expect(LocalWebServerService.mimeTypeFor('style.css'),
          startsWith('text/css'));
      expect(LocalWebServerService.mimeTypeFor('logo.svg'),
          startsWith('image/svg'));
    });

    test('unknown and empty paths fall back to octet-stream', () {
      expect(LocalWebServerService.mimeTypeFor('notes.txt'),
          'application/octet-stream');
      expect(LocalWebServerService.mimeTypeFor(''), 'application/octet-stream');
      expect(
          LocalWebServerService.mimeTypeFor('mjs'), 'application/octet-stream');
    });
  });

  group('isUintString', () {
    test('accepts only digit strings', () {
      expect(LocalWebServerService.isUintString('0'), isTrue);
      expect(LocalWebServerService.isUintString('1000000'), isTrue);
    });

    test('rejects everything else', () {
      for (final bad in ['', '  ', '-5', '1.5', '1e3', '0x10', '12a']) {
        expect(LocalWebServerService.isUintString(bad), isFalse,
            reason: 'for "$bad"');
      }
    });
  });
}
