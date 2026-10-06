import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Shared harness for the page E2E: a real Chromium WebView
/// Diagnostics read out of the page when a predicate never becomes true.
// swap/bridge use #status-area, circles uses #status.
const statusJs = "(function(){var a=document.getElementById('status-area')"
    "||document.getElementById('status');return a?String(a.textContent).trim():'';})()";
const unlockErrJs =
    "(document.getElementById('unlock-err')||{textContent:''}).textContent.trim()";
const scriptsJs = "Array.prototype.map.call(document.scripts,"
    "function(s){return s.src||'[inline]';}).join(',')";

/// A real WebView with a JavaScript eval channel, real-time waiting and
/// failure diagnostics. Shared by the page E2E tests.
class WebPage {
  WebPage(this._controller, this._tester, this.url);

  final WebViewController _controller;
  final WidgetTester _tester;
  final String url;

  /// Subresource failures seen while the page was opening (e.g. an imported
  /// module that 404'd).
  final List<String> resourceErrors = <String>[];

  static Future<WebPage> open(
      WidgetTester tester, String base, String path) async {
    final pageFinished = Completer<void>();
    final resourceError = Completer<String>();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (!pageFinished.isCompleted) pageFinished.complete();
        },
        onWebResourceError: (e) {
          if (!resourceError.isCompleted) resourceError.complete(e.description);
        },
      ));

    await tester.pumpWidget(MaterialApp(
      home: WebViewWidget(controller: controller),
    ));
    await controller.loadRequest(Uri.parse('$base$path'));

    // A failed subresource (e.g. a 404 on an imported module) must not be
    // mistaken for a slow page.
    await Future.any<void>([
      pageFinished.future,
      resourceError.future.then((e) => throw StateError('$path: $e')),
    ]).timeout(const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('no page finish for $path'));
    // Let the page's own scripts run and its first fetches settle.
    await tester.pump();
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump();
    final page = WebPage(controller, tester, '$base$path');
    // Surface a failed subresource immediately: a 404 on an imported module
    // otherwise shows up much later as "never executed".
    page.resourceErrors.addAll(await _drainErrors(resourceError));
    return page;
  }

  static Future<List<String>> _drainErrors(Completer<String> c) async {
    if (!c.isCompleted) return const [];
    return [await c.future];
  }

  Future<Object?> eval(String js) =>
      _controller.runJavaScriptReturningResult(js);

  /// Wait for the browser and the network for real. `tester.pump(duration)`
  /// only advances the test clock — a module import plus its fetch needs wall
  /// time, and polling on the fake clock burns the budget in milliseconds.
  Future<void> settle([Duration d = const Duration(milliseconds: 500)]) async {
    await Future<void>.delayed(d);
    await _tester.pump();
  }

  Future<String> evalText(String js) async {
    final v = await eval("String($js)");
    return v is String ? v : v.toString();
  }

  /// `import(url)` in the page, storing a boolean at [slot].
  Future<void> importModule(String url, String slot, String condition) async {
    await eval(
      "import('$url').then(function(m){$slot=($condition);})"
      ".catch(function(e){$slot=false;window.__aErr=e.message})",
    );
  }

  /// Re-attach the page's own `<script>` src so the served bytes actually
  /// execute in the browser.
  ///
  /// Parser-inserted scripts do not run in this harness: the tag is present in
  /// `document.scripts`, the DOM is parsed, and `runJavaScriptReturningResult`
  /// works — while the app's own webcli UI proves page scripts do run in
  /// production, so this is a harness limitation (A44), not a product bug.
  /// Re-attaching the very same src exercises the same URL, the same MIME
  /// decision and the same module graph, which is what the risk depends on.
  ///
  /// [index] picks the script out of `document.scripts`, so the test follows
  /// the HTML instead of hardcoding a URL that could drift.
  Future<void> reattachPageScript(int index, {bool asModule = false}) async {
    final src = await eval('document.scripts[$index].src');
    expect(src, isA<String>(), reason: 'script #$index must have a src');
    await eval(
      "window.__pageErr=null;(function(){"
      "var s=document.createElement('script');"
      "${asModule ? "s.type='module';" : ''}"
      "s.src=$src;"
      "s.onerror=function(){window.__pageErr='load error: '+(s.src||'')};"
      "document.head.appendChild(s);})();'appended'",
    );
  }

  /// Error reported by the re-attached script, if any (load-time only).
  Future<String> pageScriptError() => evalText('window.__pageErr');

  /// Collect runtime errors and unhandled rejections from this point on.
  ///
  /// A module whose import graph is broken throws while evaluating, which no
  /// `onerror` on the element reports — only a window `error` event does.
  Future<void> watchForScriptErrors() async {
    await eval(
      "window.__errs=[];"
      "window.addEventListener('error',function(e){"
      "window.__errs.push('error: '+String(e.message||(e.error&&e.error.message)||'?'))});"
      "window.addEventListener('unhandledrejection',function(e){"
      "var r=e.reason;"
      "window.__errs.push('rejection: '+String(r&&r.message?r.message:r))});"
      "1",
    );
  }

  Future<List<String>> scriptErrors() async {
    final raw = await evalText('JSON.stringify(window.__errs||[])');
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => e.toString()).toList();
  }
}
