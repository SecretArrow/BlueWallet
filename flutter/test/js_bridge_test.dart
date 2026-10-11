import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/dapp/adapter_registry.dart';
import 'package:octopus_wallet/services/dapp/dapp_session_store.dart';
import 'package:octopus_wallet/services/dapp/js_bridge.dart';
import 'package:octopus_wallet/services/dapp/wallet_adapter.dart';
import 'package:octopus_wallet/services/dapp_bridge_protocol.dart';

class _OkAdapter implements WalletAdapter {
  @override
  String get id => 'ok';
  @override
  String get chainType => 'Ok';
  @override
  Set<String> get supportedMethods => {'octra_chainId'};
  @override
  bool supports(String m) => supportedMethods.contains(m);
  @override
  Future<AdapterResult> handle(DappRequest r, AdapterContext ctx) async =>
      'chain-ok';
}

/// Never-completing adapter: lets tests observe timeout/cancel behaviour
/// through the pending map without waiting real durations.
class _HangAdapter implements WalletAdapter {
  final Completer<AdapterResult> gate = Completer<AdapterResult>();
  @override
  String get id => 'hang';
  @override
  String get chainType => 'Hang';
  @override
  Set<String> get supportedMethods => {'octra_chainId'};
  @override
  bool supports(String m) => supportedMethods.contains(m);
  @override
  Future<AdapterResult> handle(DappRequest r, AdapterContext ctx) =>
      gate.future;
}

class _Resp {
  final int id;
  final String? result;
  final String? error;
  final int code;
  _Resp(this.id, this.result, this.error, this.code);
}

void main() {
  AdapterContext ctx() => AdapterContext(
        requestApproval: (
                {required String title,
                required String body,
                required String confirmLabel,
                String? origin}) async =>
            true,
        requestTxApproval: (
                {required String title,
                required String to,
                required String amount,
                String? extra,
                String? origin}) async =>
            true,
        currentOrigin: () => 'https://app.example.com',
      );

  JsBridge makeBridge({
    required List<_Resp> out,
    required WalletAdapter adapter,
    String origin = 'https://app.example.com',
    DappSessionStore? sessions,
  }) {
    final store = sessions ?? DappSessionStore.instance;
    final registry = AdapterRegistry([adapter]);
    final bridge = JsBridge(
      registry: registry,
      sessions: store,
      respond: (id, result, error, code) =>
          out.add(_Resp(id, result, error, code)),
      currentOrigin: () => origin,
    );
    bridge.setDispatchHook((req, completer) {
      (() async {
        try {
          final v = await registry.dispatch(req, ctx());
          if (!completer.isCompleted) completer.complete(v);
          if (req.method == 'octra_requestAccounts') {
            await store.grant(req.origin, address: 'oct1test');
          }
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      })();
    });
    bridge.setConnectHook((id, completer) async {
      completer.complete('oct1test');
    });
    return bridge;
  }

  String req(int id, String method, [dynamic params]) => jsonEncode({
        'type': 'request',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      });

  group('JsBridge validation', () {
    test('unknown message type is rejected with a code', () async {
      final out = <_Resp>[];
      final b = makeBridge(out: out, adapter: _OkAdapter());
      await b.onMessage(jsonEncode({'type': 'nope', 'id': 1}));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(out.length, 1);
      expect(out.first.error, contains('Unknown bridge message type'));
      expect(out.first.code, DappBridgeProtocol.unsupportedMethod);
      b.dispose();
    });

    test('untrusted origin is rejected', () async {
      final out = <_Resp>[];
      final b = makeBridge(
          out: out, adapter: _OkAdapter(), origin: 'javascript:alert(1)');
      // octra_accounts is pre-connect; origin check runs first.
      await b.onMessage(req(1, 'octra_accounts', []));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(out.length, 1);
      expect(out.first.code, DappBridgeProtocol.unauthorized);
      b.dispose();
    });

    test('connected-only method without session is unauthorized', () async {
      final out = <_Resp>[];
      final b = makeBridge(out: out, adapter: _OkAdapter());
      await b.onMessage(req(1, 'octra_getBalance', []));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(out.length, 1);
      expect(out.first.error, 'Not connected');
      expect(out.first.code, DappBridgeProtocol.unauthorized);
      b.dispose();
    });

    test('pre-connect read dispatches and answers', () async {
      final out = <_Resp>[];
      final b = makeBridge(out: out, adapter: _OkAdapter());
      await b.onMessage(req(7, 'octra_chainId', []));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(out.length, 1);
      expect(out.first.error, isNull);
      expect(jsonDecode(out.first.result!), 'chain-ok');
      b.dispose();
    });

    test('duplicate js id is rejected, never answered twice', () async {
      final out = <_Resp>[];
      final hang = _HangAdapter();
      final b = makeBridge(out: out, adapter: hang);
      await b.onMessage(req(3, 'octra_chainId', []));
      expect(b.pendingCount, 1);
      await b.onMessage(req(3, 'octra_chainId', []));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(out.any((r) => (r.error ?? '').contains('Duplicate')), isTrue);
      // Complete the original: the duplicate consumed the id, so the late
      // result must NOT produce a second answer (never answered twice).
      hang.gate.complete('late');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(out.where((r) => r.error == null).length, 0);
      expect(out.length, 1);
      b.dispose();
    });

    test('oversized payload is rejected', () async {
      final out = <_Resp>[];
      final b = makeBridge(out: out, adapter: _OkAdapter());
      final big = 'x' * (70 * 1024);
      await b.onMessage(req(9, 'octra_chainId', [
        {'blob': big}
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(out.length, 1);
      expect(out.first.error, contains('too large'));
      b.dispose();
    });
  });

  group('JsBridge lifecycle', () {
    test('cancelForOrigin rejects pending with userRejected', () async {
      final out = <_Resp>[];
      final hang = _HangAdapter();
      final b = makeBridge(out: out, adapter: hang);
      await b.onMessage(req(11, 'octra_chainId', []));
      expect(b.pendingCount, 1);
      b.cancelForOrigin('https://app.example.com');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(b.pendingCount, 0);
      expect(out.length, 1);
      expect(out.first.code, DappBridgeProtocol.userRejected);
      b.dispose();
    });

    test('dispose cancels everything (WebView destroy)', () async {
      final out = <_Resp>[];
      final hang = _HangAdapter();
      final b = makeBridge(out: out, adapter: hang);
      await b.onMessage(req(21, 'octra_chainId', []));
      await b.onMessage(req(22, 'octra_chainId', []));
      expect(b.pendingCount, 2);
      b.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(b.pendingCount, 0);
      expect(out.length, 2);
      expect(b.isDisposed, isTrue);
    });
  });
}
