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

  group('/api/transaction normalization', () {
    Map<String, dynamic> normalize(String hash, Map<String, dynamic>? tx) {
      return LocalWebServerService.normalizeTransaction(hash, tx);
    }

    test('reports found with epoch', () {
      final out = normalize('0xabc', <String, dynamic>{
        'tx_hash': '0xabc',
        'epoch': 42,
        'status': 'confirmed',
        'block_height': 9,
      });
      expect(out['found'], isTrue);
      expect(out['hash'], '0xabc');
      expect(out['epoch'], 42);
      expect(out['status'], 'confirmed');
      expect(out['block_height'], 9);
    });

    test('accepts the epoch_id spelling', () {
      expect(normalize('0xa', <String, dynamic>{'epoch_id': 7})['epoch'], 7);
      expect(normalize('0xa', <String, dynamic>{'epoch_id': '7'})['epoch'], 7);
    });

    test('missing epoch is zero, not absent', () {
      final out = normalize('0xa', <String, dynamic>{'status': 'pending'});
      expect(out['found'], isTrue);
      expect(out['epoch'], 0);
      expect(out['status'], 'pending');
    });

    test('null or empty result is not found and fakes no epoch', () {
      for (final tx in <Map<String, dynamic>?>[null, <String, dynamic>{}]) {
        final out = normalize('0xdead', tx);
        expect(out['found'], isFalse);
        expect(out['hash'], '0xdead');
        expect(out.containsKey('epoch'), isFalse);
      }
    });

    test('surfaces a rejection reason without crashing on null', () {
      final out = normalize('0x1', <String, dynamic>{
        'epoch': 3,
        'error': 'nonce too low',
      });
      expect(out['error_detail'], 'nonce too low');
      // A null error must not be stringified into a bogus reason.
      final withNull = normalize('0x2', <String, dynamic>{
        'epoch': 1,
        'error': null,
      });
      expect(withNull['epoch'], 1);
      expect(withNull.containsKey('error_detail'), isFalse);
    });
  });

  group('isWalletLoadedSafely', () {
    test('never throws — a liveness probe must not report a 500', () {
      // WalletService.instance is a null-check on a lazy singleton: reading it
      // before the first WalletService() throws. /api/status is what the
      // adapter transport probes to decide a wallet is reachable, so it has to
      // answer "no wallet" instead of failing the request.
      expect(LocalWebServerService.isWalletLoadedSafely(), isA<bool>());
      expect(LocalWebServerService.isWalletLoadedSafely(), isFalse,
          reason: 'no wallet is loaded in a unit test');
      // Repeat: it must stay non-throwing across calls (no cached failure).
      expect(LocalWebServerService.isWalletLoadedSafely(), isFalse);
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
