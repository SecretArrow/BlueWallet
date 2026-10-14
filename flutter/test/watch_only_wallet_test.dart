import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/models/wallet_profile.dart';
import 'package:octopus_wallet/services/oct_address.dart';
import 'package:octopus_wallet/services/wallet_service.dart';

/// Watch-only wallet tests: address validation, model persistence, the
/// send decision helper, and import flow (mocked SharedPreferences —
/// watch-only persistence deliberately never touches secure storage).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Field-real address (AboutActivity donation address shape: 47 chars).
  const goodAddress = 'oct5ZPf49ZYNnA1hopXe9EcDbiBPhgwJyudxLaLhHefEmFt';

  group('OctAddress.isValid (mirrors native 47-char oct rule)', () {
    test('accepts well-formed addresses (trim tolerant)', () {
      expect(OctAddress.isValid(goodAddress), isTrue);
      expect(OctAddress.isValid('  $goodAddress  '), isTrue);
    });

    test('rejects wrong prefix', () {
      expect(OctAddress.isValid('xc' + goodAddress.substring(2)), isFalse);
      expect(OctAddress.isValid('OCT' + goodAddress.substring(3)), isFalse);
    });

    test('rejects wrong length', () {
      expect(OctAddress.isValid(goodAddress.substring(0, 46)), isFalse);
      expect(OctAddress.isValid('${goodAddress}x'), isFalse);
      expect(OctAddress.isValid('oct'), isFalse);
    });

    test('rejects empty / null / whitespace-only', () {
      expect(OctAddress.isValid(''), isFalse);
      expect(OctAddress.isValid(null), isFalse);
      expect(OctAddress.isValid('   '), isFalse);
    });
  });

  group('WalletProfile watchOnly persistence', () {
    test('round-trips the flag through toJson/fromJson', () {
      final w = WalletProfile(
        id: 'wallet_1',
        name: 'Vault Watch',
        address: goodAddress,
        walletType: 'watch_only',
        watchOnly: true,
      );
      final restored = WalletProfile.fromJson(
          jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>);
      expect(restored.watchOnly, isTrue);
      expect(restored.isWatchOnly, isTrue);
      expect(restored.address, goodAddress);
      expect(restored.walletType, 'watch_only');
    });

    test('omits the flag when false (legacy JSON stays identical)', () {
      final w = WalletProfile(
        id: 'wallet_1',
        name: 'Main',
        address: goodAddress,
      );
      expect(w.toJson().containsKey('watchOnly'), isFalse);
      expect(w.watchOnly, isFalse);
    });

    test('legacy / garbage JSON never flags watch-only', () {
      final legacy = WalletProfile.fromJson({
        'id': 'wallet_1',
        'name': 'Main',
        'address': goodAddress,
      });
      expect(legacy.watchOnly, isFalse);
      final garbage = WalletProfile.fromJson({
        'id': 'wallet_2',
        'name': 'X',
        'address': goodAddress,
        'watchOnly': 'yes', // non-bool must not flip the flag
      });
      expect(garbage.watchOnly, isFalse);
    });
  });

  group('WalletService send decision (canSend)', () {
    final spendable = WalletProfile(
        id: 'wallet_1', name: 'Main', address: goodAddress);
    final watchOnly = WalletProfile(
        id: 'wallet_2', name: 'Watch', address: goodAddress, watchOnly: true);

    test('walletCanSend is false for watch-only, true otherwise', () {
      expect(WalletService.walletCanSend(watchOnly), isFalse);
      expect(WalletService.walletCanSend(spendable), isTrue);
      expect(WalletService.walletCanSend(null), isFalse);
    });

    test('assertCanSend throws for watch-only with the block message', () {
      expect(
        () => WalletService.assertCanSend(watchOnly),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', WalletService.watchOnlySendBlockMessage)),
      );
    });

    test('assertCanSend is a no-op for spendable and null wallets', () {
      // Must not throw.
      WalletService.assertCanSend(spendable);
      WalletService.assertCanSend(null);
    });
  });

  group('importWatchOnlyWallet (persistence round-trip)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<WalletService> freshService() async {
      final ws = WalletService();
      // Let the async _init() settle before driving the service.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return ws;
    }

    test('persists a watch-only profile without any secret key', () async {
      final ws = await freshService();
      final profile =
          await ws.importWatchOnlyWallet(name: 'Vault Watch', address: goodAddress);

      expect(ws.wallets, hasLength(1));
      expect(profile.watchOnly, isTrue);
      expect(profile.address, goodAddress);
      expect(profile.name, 'Vault Watch');
      expect(ws.activeWallet?.id, profile.id);
      expect(ws.canSend, isFalse, reason: 'watch-only active wallet cannot send');

      // Storage schema mirrors the regular wallet list: wallet_ids +
      // wallet_profile_<id> JSON with the extra watchOnly flag.
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList('wallet_ids') ?? [];
      expect(ids, [profile.id]);
      final raw = prefs.getString('wallet_profile_${profile.id}');
      expect(raw, isNotNull);
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['watchOnly'], isTrue);
      expect(json['address'], goodAddress);
      // No secret material is stored anywhere for watch-only wallets.
      expect(json.containsKey('sk'), isFalse);
    });

    test('rejects invalid addresses with ArgumentError', () async {
      final ws = await freshService();
      for (final bad in [
        '',
        'oct',
        'notanaddress',
        'oct123', // right prefix, wrong length
        goodAddress.substring(0, 46),
        '$goodAddress!',
      ]) {
        expect(
          () => ws.importWatchOnlyWallet(name: 'X', address: bad),
          throwsArgumentError,
          reason: 'for "$bad"',
        );
      }
      expect(ws.wallets, isEmpty, reason: 'no wallet persisted on rejection');
    });

    test('rejects empty names', () async {
      final ws = await freshService();
      expect(
        () => ws.importWatchOnlyWallet(name: '   ', address: goodAddress),
        throwsArgumentError,
      );
    });

    test('deep guard: signing methods throw for the watch-only wallet',
        () async {
      final ws = await freshService();
      await ws.importWatchOnlyWallet(name: 'Vault Watch', address: goodAddress);

      // Signing paths hard-block watch-only wallets BEFORE touching
      // network or key material. Amount/address args are irrelevant —
      // the guard fires first.
      expect(
        () => ws.sendTransaction(
            nodeUrl: 'https://node.example', toAddress: goodAddress, amount: '1'),
        throwsStateError,
      );
      expect(
        () => ws.sendStealthTx(
            nodeUrl: 'https://node.example', toAddress: goodAddress, amount: 1),
        throwsStateError,
      );
      expect(
        () => ws.sendEncryptTx(nodeUrl: 'https://node.example', amount: 1),
        throwsStateError,
      );
    });
  });
}
