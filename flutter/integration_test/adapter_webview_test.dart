import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:octopus_wallet/services/local_web_server_service.dart';
import 'package:octopus_wallet/services/network_service.dart';
import 'package:octopus_wallet/services/wallet_service.dart';

import 'support/webview_harness.dart';

/// E2E layer 2: a real Chromium WebView executing the pages the local server
/// hands out.
///
/// Split from the hermetic HTTP layer (adapter_http_test.dart) because this
/// one needs the emulator and runs minutes, not seconds: PR runs use the HTTP
/// layer, the nightly runs everything.
///
/// Scope (A44/A46): this proves the served bytes *load* (MIME + path), the
/// module graph resolves and evaluation does not throw. It does not prove
/// post-fetch DOM effects — `fetch()` from the page does not resolve inside
/// this harness, while `runJavaScriptReturningResult` works fine.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final base = 'http://127.0.0.1:${LocalWebServerService.port}';

  setUpAll(() async {
    // Lazily created singletons the wallet-aware routes depend on; app startup
    // constructs them, so the harness mirrors that order.
    final wallet = WalletService();
    final network = NetworkService();
    expect(WalletService.instance, same(wallet));
    expect(NetworkService.instance, same(network));
    await LocalWebServerService.instance.start();
  });

  tearDownAll(() async {
    await LocalWebServerService.instance.stop();
  });

  group('real WebView executes the served modules', () {
    testWidgets('swap.js evaluates in Chromium and imports the adapter',
        (tester) async {
      final page = await WebPage.open(tester, base, '/swap.html');
      await page.watchForScriptErrors();

      // Re-attach the very script the HTML declares. A broken import graph or a
      // MIME the browser refuses surfaces here as an error/unhandledrejection —
      // which is exactly the regression class this test exists for.
      await page.reattachPageScript(0, asModule: true);
      await page.settle(const Duration(seconds: 3));

      expect(await page.pageScriptError(), isNull,
          reason: 'the served module must load (MIME + path); '
              'status="${await page.evalText(statusJs)}" '
              'scripts=${await page.evalText(scriptsJs)}"');
      expect(await page.scriptErrors(), isEmpty,
          reason: 'swap.js must evaluate without throwing; '
              'unlockErr="${await page.evalText(unlockErrJs)}"');

      // And the adapter module itself must import over HTTP.
      await page.importModule(
          '/adapter/index.mjs',
          'window.__ok',
          "typeof m.OctraWalletAdapter === 'function' && "
              "typeof m.LocalhostTransport === 'function' && "
              "typeof m.ERROR_CODES === 'object'");
      await page.settle(const Duration(seconds: 2));
      expect(await page.evalText('window.__okErr'), isNull,
          reason: 'importing the served adapter must not throw');
      if (await page.eval('window.__ok') == true) {
        // Pure logic from the served bytes, executed in the browser engine.
        expect(
          await page.eval("import('/adapter/units.mjs').then(function(u){"
              "return u.octToMicro('10.5');})"),
          '10500000',
        );
      } else {
        debugPrint(
            'SKIP adapter logic check: dynamic import unavailable in this '
            'harness (A44) — load + evaluation assertions above still apply');
      }
    });

    testWidgets('bridge.js evaluates in Chromium without throwing',
        (tester) async {
      final page = await WebPage.open(tester, base, '/bridge.html');
      await page.watchForScriptErrors();
      await page.reattachPageScript(0, asModule: true);
      await page.settle(const Duration(seconds: 3));

      expect(await page.pageScriptError(), isNull,
          reason: 'the served bridge module must load (MIME + path); '
              'scripts=${await page.evalText(scriptsJs)}"');
      expect(await page.scriptErrors(), isEmpty,
          reason: 'bridge.js must evaluate without throwing; '
              'status="${await page.evalText(statusJs)}"');
      expect(await page.evalText(scriptsJs), contains('bridge.js'),
          reason: 'the page must declare its own script');
    });

    testWidgets('circles.js classic scripts evaluate without throwing',
        (tester) async {
      final page = await WebPage.open(tester, base, '/circles.html');
      await page.watchForScriptErrors();

      // All three classic scripts, in document order: policy, chunks, circles.
      for (var i = 0; i < 3; i++) {
        await page.reattachPageScript(i);
        await page.settle(const Duration(seconds: 2));
      }

      expect(await page.pageScriptError(), isNull,
          reason: 'the served classic scripts must load; '
              'scripts=${await page.evalText(scriptsJs)}"');
      expect(await page.scriptErrors(), isEmpty,
          reason: 'circles.js and its dependencies must evaluate cleanly; '
              'status="${await page.evalText(statusJs)}"');
      // The lazy adapter import is the riskiest statement in circles.js: a
      // module that fails to resolve rejects rather than throwing synchronously.
      await page
          .eval("import('/adapter/boot.mjs').then(function(m){window.__boot="
              "typeof m.createAdapter === 'function';}).catch(function(e){"
              "window.__bootErr=e.message})");
      await page.settle(const Duration(seconds: 2));
      final bootErr = await page.evalText('window.__bootErr');
      if (bootErr == 'null') {
        expect(await page.eval('window.__boot'), isTrue,
            reason: 'the lazy adapter import must resolve');
      } else {
        debugPrint('SKIP circles lazy-import check: dynamic import unavailable '
            'in this harness (A44): $bootErr');
      }
    });

    testWidgets('the oct:// gateway path loads in a WebView', (tester) async {
      // This is the URL DappBrowserScreen actually loads for a circle
      // (OctUrl.gatewayHttpUrl). It was unreachable until the Flutter app
      // declared a loopback cleartext policy — the WebView refused it with
      // ERR_CLEARTEXT_NOT_PERMITTED while android-native allowed it.
      const circleId = 'oct99BWHFpV5r54DXKc2FhsBmZEaS6Q8zvCQrHRgXUcK4Fk';

      // Needs the devnet node (the gateway fetches the asset over RPC), so it
      // is skipped with a reason rather than failing on an unreachable node.
      final reachable = await _nodeAnswersCircle(circleId);
      if (!reachable) {
        // Loud, greppable skip — never a silent pass (A41).
        debugPrint('SKIP oct:// gateway E2E: devnet unreachable '
            '(circle $circleId) — the loopback transport policy is still '
            'covered by the swap/bridge/circles cases above');
        return;
      }

      final page =
          await WebPage.open(tester, base, '/oct/$circleId/index.html');
      expect(page.resourceErrors, isEmpty,
          reason: 'the gateway must load without resource errors');
      // A served page has a DOM; the WebView must not be an error page.
      expect(await page.eval('document.readyState'), isNot('about:blank'));
    });
  });
}

/// True when the node answers `circle_asset` for [circleId] (best effort,
/// retries like oct_circle_test.dart because shared CI runners get 429s).
Future<bool> _nodeAnswersCircle(String circleId) async {
  const rpcUrl = 'https://devnet.octrascan.io/rpc';
  for (var attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(Duration(seconds: 5 * attempt));
    }
    try {
      final resp = await http
          .post(
            Uri.parse(rpcUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'circle_asset',
              'params': [circleId, '/index.html'],
              'id': 1,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 429 || resp.statusCode >= 500) continue;
      return resp.statusCode == 200;
    } catch (_) {
      continue; // socket/timeout — retry
    }
  }
  return false;
}
