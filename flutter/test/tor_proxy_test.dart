import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/tor_proxy_service.dart';

/// Defensive tests for Tor proxy validation. Pure statics — no storage.
void main() {
  group('validateProxy', () {
    test('accepts sane values', () {
      TorProxyService.validateProxy('127.0.0.1', 9050, 'SOCKS');
      TorProxyService.validateProxy('example.onion', 8118, 'http');
      TorProxyService.validateProxy('h', 1, 'socks');
      TorProxyService.validateProxy('h', 65535, 'HTTP');
    });

    test('rejects garbage', () {
      expect(() => TorProxyService.validateProxy('', 9050, 'SOCKS'),
          throwsArgumentError);
      expect(() => TorProxyService.validateProxy('   ', 9050, 'SOCKS'),
          throwsArgumentError);
      expect(() => TorProxyService.validateProxy('h', 0, 'SOCKS'),
          throwsArgumentError);
      expect(() => TorProxyService.validateProxy('h', 99999, 'SOCKS'),
          throwsArgumentError);
      expect(() => TorProxyService.validateProxy('h', 9050, ''),
          throwsArgumentError);
      expect(() => TorProxyService.validateProxy('h', 9050, 'FTP'),
          throwsArgumentError);
    });

    test('canonicalType normalizes', () {
      expect(TorProxyService.canonicalType('socks'), 'SOCKS');
      expect(TorProxyService.canonicalType('http'), 'HTTP');
      expect(TorProxyService.canonicalType('anything'), 'SOCKS');
    });
  });

  group('ProxyConfig.tryFromJson', () {
    test('parses valid entries, normalizes type', () {
      final c = ProxyConfig.tryFromJson({
        'name': 'X',
        'host': 'h',
        'port': 9050,
        'type': 'socks',
        'isDefault': true,
      });
      expect(c, isNotNull);
      expect(c!.type, 'SOCKS');
      expect(c.isDefault, isTrue);
    });

    test('skips garbage entries', () {
      expect(ProxyConfig.tryFromJson(null), isNull);
      expect(ProxyConfig.tryFromJson('nope'), isNull);
      expect(ProxyConfig.tryFromJson({}), isNull);
      expect(
          ProxyConfig.tryFromJson(
              {'name': 'X', 'host': '', 'port': 9050, 'type': 'SOCKS'}),
          isNull);
      expect(
          ProxyConfig.tryFromJson(
              {'name': 'X', 'host': 'h', 'port': 0, 'type': 'SOCKS'}),
          isNull);
      expect(
          ProxyConfig.tryFromJson(
              {'name': 'X', 'host': 'h', 'port': 9050, 'type': 'FTP'}),
          isNull);
      // String port is coerced when valid.
      final c = ProxyConfig.tryFromJson(
          {'name': 'X', 'host': 'h', 'port': '9050', 'type': 'HTTP'});
      expect(c, isNotNull);
      expect(c!.port, 9050);
    });
  });
}
