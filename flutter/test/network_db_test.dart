import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/models/network_profile.dart';
import 'package:octopus_wallet/services/database_service.dart';
import 'package:octopus_wallet/services/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Defensive tests for network profiles + timestamp parsing.
/// Pure statics — no storage, no network.
void main() {
  group('dedupeName', () {
    test('dedupes like Android uniqueName', () {
      expect(NetworkService.dedupeName([], 'X'), 'X');
      expect(NetworkService.dedupeName(['X'], 'X'), 'X 2');
      expect(NetworkService.dedupeName(['X', 'X 2'], 'X'), 'X 3');
      expect(NetworkService.dedupeName(['X'], 'Y'), 'Y');
    });
  });

  group('addProfile guards', () {
    NetworkProfile p(String id, String name, String url) =>
        NetworkProfile(id: id, name: name, nodeUrl: url, explorerUrl: '');

    // Fresh instance on a fresh mock store; double-settle + reset defeats
    // the fire-and-forget _load() race deterministically.
    Future<NetworkService> freshService() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final ns = NetworkService();
      await Future.delayed(const Duration(milliseconds: 100));
      ns.debugResetForTest();
      await Future.delayed(const Duration(milliseconds: 100));
      ns.debugResetForTest();
      return ns;
    }

    test('rejects empty id and nodeUrl before storage', () async {
      final ns = await freshService();
      await expectLater(
          ns.addProfile(p('', 'N', 'https://x/rpc')), throwsArgumentError);
      await expectLater(
          ns.addProfile(p('id', 'N', '   ')), throwsArgumentError);
      expect(ns.profiles, isEmpty);
    });

    test('trims, dedupes and activates first profile', () async {
      final ns = await freshService();
      await ns.addProfile(p('a', '  Net  ', 'https://a/rpc'));
      await ns.addProfile(p('b', 'Net', 'https://b/rpc'));
      expect(ns.profiles.length, 2);
      expect(ns.profiles[0].name, 'Net');
      expect(ns.profiles[0].nodeUrl, 'https://a/rpc');
      expect(ns.profiles[1].name, 'Net 2');
      expect(ns.profiles[0].isActive, isTrue);
    });

    test('updateProfile reports found/missing', () async {
      final ns = await freshService();
      await ns.addProfile(p('a', 'A', 'https://a/rpc'));
      expect(
          await ns.updateProfile('a',
              nodeUrl: 'https://x/rpc', explorerUrl: ''),
          isTrue);
      expect(
          await ns.updateProfile('missing',
              nodeUrl: 'https://x/rpc', explorerUrl: ''),
          isFalse);
    });
  });

  group('parseTimestamp', () {
    test('null and garbage yield 0', () {
      expect(DatabaseService.parseTimestamp(null), 0);
      expect(DatabaseService.parseTimestamp('abc'), 0);
      expect(DatabaseService.parseTimestamp(''), 0);
      expect(DatabaseService.parseTimestamp([]), 0);
    });

    test('ints pass through', () {
      expect(DatabaseService.parseTimestamp(1700000000000), 1700000000000);
      expect(DatabaseService.parseTimestamp(0), 0);
    });

    test('seconds become millis, millis stay', () {
      expect(DatabaseService.parseTimestamp(1700000000), 1700000000000);
      expect(DatabaseService.parseTimestamp(1700000000.0), 1700000000000);
      expect(DatabaseService.parseTimestamp('1700000000'), 1700000000000);
      expect(DatabaseService.parseTimestamp('1700000000000'), 1700000000000);
    });
  });
}
