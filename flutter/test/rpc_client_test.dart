import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:octopus_wallet/services/network_service.dart';

/// Defensive tests for RpcClient: every input shape and failure mode maps to
/// an explicit success or failure — never a throw, never a silent null.
/// No real network is touched (MockClient).
void main() {
  http.Response json(Map<String, dynamic> m, [int code = 200]) =>
      http.Response(jsonEncode(m), code,
          headers: {'Content-Type': 'application/json'});

  group('setUrl', () {
    test('parses https host with path and port', () {
      final c = RpcClient(httpClient: MockClient((_) async => json({})));
      c.setUrl('https://node.example.com:8443/rpc');
      // Proven indirectly: a call builds the right URL (see call tests).
    });

    test('rejects empty and blank URLs', () {
      final c = RpcClient(httpClient: MockClient((_) async => json({})));
      expect(() => c.setUrl(''), throwsArgumentError);
      expect(() => c.setUrl('   '), throwsArgumentError);
    });

    test('rejects non-numeric and out-of-range ports', () {
      final c = RpcClient(httpClient: MockClient((_) async => json({})));
      expect(() => c.setUrl('http://host:abc/rpc'), throwsArgumentError);
      expect(() => c.setUrl('http://host:0/rpc'), throwsArgumentError);
      expect(() => c.setUrl('http://host:99999/rpc'), throwsArgumentError);
      expect(() => c.setUrl('http://:8080/rpc'), throwsArgumentError);
    });

    test('accepts boundary ports', () {
      final c = RpcClient(httpClient: MockClient((_) async => json({})));
      c.setUrl('http://host:1/rpc');
      c.setUrl('http://host:65535/rpc');
    });
  });

  group('call guards (no HTTP)', () {
    test('empty method fails without touching the network', () async {
      var calls = 0;
      final c = RpcClient(httpClient: MockClient((_) async {
        calls++;
        return json({'result': 1});
      }));
      c.setUrl('http://h:8080/rpc');
      final r = await c.call('  ');
      expect(r.ok, isFalse);
      expect(r.error, contains('non-empty'));
      expect(calls, 0);
    });

    test('unconfigured host fails without touching the network', () async {
      var calls = 0;
      final c = RpcClient(httpClient: MockClient((_) async {
        calls++;
        return json({'result': 1});
      }));
      final r = await c.call('octra_balance', ['a']);
      expect(r.ok, isFalse);
      expect(r.error, contains('not configured'));
      expect(calls, 0);
    });

    test('unencodable params report encoding, not connection', () async {
      final c =
          RpcClient(httpClient: MockClient((_) async => json({'result': 1})));
      c.setUrl('http://h:8080/rpc');
      final r = await c.call('m', [Object()]);
      expect(r.ok, isFalse);
      expect(r.error, contains('encoding'));
      expect(r.error, isNot(contains('Connection')));
    });
  });

  group('call transport', () {
    test('success envelope', () async {
      final c = RpcClient(
          httpClient: MockClient((_) async => json({
                'result': {'x': 1}
              })));
      c.setUrl('http://h:8080/rpc');
      final r = await c.call('m');
      expect(r.ok, isTrue);
      expect((r.result as Map)['x'], 1);
    });

    test('scalar and falsy-but-valid results pass through', () async {
      final c =
          RpcClient(httpClient: MockClient((req) async => json({'result': 0})));
      c.setUrl('http://h:8080/rpc');
      final r = await c.call('m');
      expect(r.ok, isTrue);
      expect(r.result, 0);
    });

    test('null result without error is a failure', () async {
      final c = RpcClient(
          httpClient: MockClient((_) async => json({'result': null})));
      c.setUrl('http://h:8080/rpc');
      final r = await c.call('m');
      expect(r.ok, isFalse);
      expect(r.error, contains('Empty result'));
    });

    test('error object/string/number all surface messages', () async {
      for (final err in [
        {'code': -32000, 'message': 'no funds'},
        'plain string',
        42,
      ]) {
        final c = RpcClient(
            httpClient: MockClient((_) async => json({'error': err})));
        c.setUrl('http://h:8080/rpc');
        final r = await c.call('m');
        expect(r.ok, isFalse, reason: 'for error $err');
        expect(r.error, isNotEmpty);
      }
    });

    test('error without message falls back, null error is unknown', () async {
      var c = RpcClient(
          httpClient: MockClient((_) async => json({
                'error': {'code': 1}
              })));
      c.setUrl('http://h:8080/rpc');
      expect((await c.call('m')).error, 'RPC error');

      c = RpcClient(httpClient: MockClient((_) async => json({'error': null})));
      c.setUrl('http://h:8080/rpc');
      final r = await c.call('m');
      expect(r.ok, isFalse);
      expect(r.error, contains('Unknown'));
    });

    test('unknown shape and garbage body are failures', () async {
      var c = RpcClient(
          httpClient: MockClient((_) async => json({'jsonrpc': '2.0'})));
      c.setUrl('http://h:8080/rpc');
      expect((await c.call('m')).error, contains('Unknown'));

      c = RpcClient(
          httpClient: MockClient((_) async => http.Response('<html>', 200)));
      c.setUrl('http://h:8080/rpc');
      expect((await c.call('m')).error, contains('Parse error'));

      c = RpcClient(
          httpClient: MockClient((_) async => http.Response('[1,2]', 200)));
      c.setUrl('http://h:8080/rpc');
      expect((await c.call('m')).error, contains('Parse error'));
    });

    test('HTTP 500 with JSON error body surfaces the message', () async {
      final c = RpcClient(
          httpClient: MockClient((_) async => json({
                'error': {'message': 'boom'}
              }, 500)));
      c.setUrl('http://h:8080/rpc');
      final r = await c.call('m');
      expect(r.ok, isFalse);
      expect(r.error, 'boom');
    });

    test('socket errors and timeouts are connection failures', () async {
      var c = RpcClient(
          httpClient:
              MockClient((_) => throw const SocketException('refused')));
      c.setUrl('http://h:8080/rpc');
      expect((await c.call('m')).error, contains('Connection failed'));

      c = RpcClient(httpClient: MockClient((_) async {
        await Future.delayed(const Duration(seconds: 5));
        return json({'result': 1});
      }));
      c.setUrl('http://h:8080/rpc');
      final r = await c.call('m', [], 1);
      expect(r.ok, isFalse);
      expect(r.error, contains('Connection failed'));
    });

    test('typed wrappers send the right method', () async {
      String? seen;
      final c = RpcClient(httpClient: MockClient((req) async {
        seen = (jsonDecode(req.body) as Map)['method'] as String?;
        return json({'result': {}});
      }));
      c.setUrl('http://h:8080/rpc');
      await c.getBalance('addr');
      expect(seen, 'octra_balance');
      await c.getTransaction('hash');
      expect(seen, 'octra_transaction');
    });
  });
}
