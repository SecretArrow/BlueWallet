import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:octopus_wallet/services/local_web_server_service.dart';
import 'package:octopus_wallet/services/network_service.dart';
import 'package:octopus_wallet/services/wallet_service.dart';

/// E2E layer 1: the real [LocalWebServerService] serving the adapter pages.
///
/// Everything here is loopback-only (no devnet), so it is deterministic and
/// runs in seconds — this is the file a pull request runs. The WebView layer
/// (adapter_webview_test.dart) needs the emulator for minutes and runs on the
/// nightly.
///
/// What it catches: MIME types (Chromium *refuses* a `.mjs` served as
/// `application/octet-stream`), a missing or drifted adapter module, a page
/// that stopped being a module script, a lost token prompt, the fail-closed
/// Bearer path those prompts depend on, and the `/api/transaction` route the
/// bridge epoch lookup needs.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final server = LocalWebServerService.instance;
  final base = 'http://127.0.0.1:${LocalWebServerService.port}';

  setUpAll(() async {
    // WalletService/NetworkService are lazily created singletons and the
    // wallet-aware routes (plus the pages themselves) need them to exist
    // before anything hits the server. Constructing them here mirrors app
    // startup order; the assertions prove registration, not just construction.
    final wallet = WalletService();
    final network = NetworkService();
    expect(WalletService.instance, same(wallet));
    expect(NetworkService.instance, same(network));
    await server.start();
    // Without this the assertions below fail with a confusing connection error.
    final probe = await http.get(Uri.parse('$base/api/status'));
    expect(probe.statusCode, 200,
        reason: 'local server must be listening on $base');

    // The token is minted asynchronously when the service loads its settings;
    // reading it too early yields '' and would make the auth test fail for the
    // wrong reason.
    for (var i = 0; i < 20 && server.authToken.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(server.authToken, isNotEmpty,
        reason: 'the local server must have minted an auth token');
  });

  tearDownAll(() async {
    await server.stop();
  });

  group('served assets (real HTTP)', () {
    test('modules are served with a script content type', () async {
      for (final path in [
        '/adapter/index.mjs',
        '/adapter/boot.mjs',
        '/adapter/adapter.mjs',
        '/adapter/protocol.mjs',
        '/adapter/errors.mjs',
        '/adapter/units.mjs',
        '/adapter/transports.mjs',
      ]) {
        final resp = await http.get(Uri.parse('$base$path'));
        expect(resp.statusCode, 200, reason: '$path must be served');
        expect(
          resp.headers['content-type'] ?? '',
          startsWith('application/javascript'),
          reason: '$path must be a script type or Chromium refuses the import',
        );
        expect(resp.body, isNotEmpty, reason: '$path must not be empty');
      }
    });

    test('migrated pages are module scripts that import the adapter', () async {
      for (final page in ['swap', 'bridge']) {
        final html = await http.get(Uri.parse('$base/$page.html'));
        expect(html.statusCode, 200, reason: '$page.html must be served');
        expect(html.body, contains('type="module"'),
            reason: '$page.html must load its script as a module');
        expect(html.body, contains('id="token-modal"'),
            reason: '$page.html must carry the 401 token prompt');

        final js = await http.get(Uri.parse('$base/$page.js'));
        expect(js.statusCode, 200);
        expect(js.body, contains("from './adapter/boot.mjs'"),
            reason: '$page.js must import the adapter boot');
      }
    });

    test('circles stays a classic script with a lazy adapter import', () async {
      final html = await http.get(Uri.parse('$base/circles.html'));
      expect(html.statusCode, 200);
      // A module script would hide the top-level `const` bindings of
      // circle_bridge_policy.js / circle_asset_chunks.js (13 references).
      expect(html.body, isNot(contains('type="module"')));
      expect(html.body, contains('id="runtime-note"'));

      final js = await http.get(Uri.parse('$base/circles.js'));
      expect(js.statusCode, 200);
      expect(js.body, contains("import('./adapter/boot.mjs')"),
          reason: 'circles.js must pull the adapter in lazily');
      expect(
        js.body,
        isNot(RegExp(r'^\s*import\s+\{', multiLine: true)),
        reason: 'a static import in a classic script would fail at runtime',
      );
    });

    test('auth is fail-closed and the configured token opens it', () async {
      final anon = await http.get(Uri.parse('$base/api/balance'));
      expect(anon.statusCode, 401,
          reason: 'an authed endpoint must reject a missing token');

      final wrong = await http.get(Uri.parse('$base/api/balance'),
          headers: {'Authorization': 'Bearer definitely-not-the-token'});
      expect(wrong.statusCode, 401);

      // The real token must get past auth. The endpoint can still refuse for
      // having no wallet loaded — anything but 401 proves the gate opened,
      // which is what the in-page token prompts depend on.
      final authed = await http.get(Uri.parse('$base/api/balance'),
          headers: {'Authorization': 'Bearer ${server.authToken}'});
      expect(authed.statusCode, isNot(401),
          reason: 'the configured token must open authed routes');
    });

    test('the bridge epoch route answers instead of 404', () async {
      final resp = await http.get(Uri.parse(
          '$base/api/transaction?hash=${Uri.encodeQueryComponent('0xdead')}'));
      expect(resp.statusCode, 200,
          reason: 'an unknown hash is "not mined yet", not a missing route');
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      expect(body.containsKey('found'), isTrue);
      expect(body.containsKey('hash'), isTrue);

      final missing = await http.get(Uri.parse('$base/api/transaction'));
      expect(missing.statusCode, 400, reason: 'a missing hash is a 400');
    });
  });
}
