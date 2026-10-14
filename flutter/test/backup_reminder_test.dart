import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/services/backup_reminder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = DateTime(2024, 1, 1);

  group('BackupReminder.isDue', () {
    test('fresh wallet is not due within the 3-day grace', () {
      expect(BackupReminder.isDue(created, createdAt: created), isFalse);
      expect(
        BackupReminder.isDue(created.add(const Duration(days: 1)),
            createdAt: created),
        isFalse,
      );
      expect(
        BackupReminder.isDue(
            created.add(const Duration(days: 2, hours: 23)),
            createdAt: created),
        isFalse,
      );
    });

    test('never-verified wallet is due once 3 days old', () {
      expect(
        BackupReminder.isDue(created.add(const Duration(days: 3)),
            createdAt: created),
        isTrue,
      );
      expect(
        BackupReminder.isDue(created.add(const Duration(days: 4)),
            createdAt: created),
        isTrue,
      );
    });

    test('no tracking info is never due', () {
      expect(BackupReminder.isDue(created.add(const Duration(days: 90))),
          isFalse);
    });

    test('verified wallet is due 30 days after last verification', () {
      final verified = DateTime(2024, 1, 1);
      expect(
        BackupReminder.isDue(verified.add(const Duration(days: 29)),
            lastVerifiedAt: verified),
        isFalse,
      );
      expect(
        BackupReminder.isDue(verified.add(const Duration(days: 30)),
            lastVerifiedAt: verified),
        isTrue,
      );
      expect(
        BackupReminder.isDue(verified.add(const Duration(days: 31)),
            lastVerifiedAt: verified),
        isTrue,
      );
    });

    test('recent verification beats an old createdAt', () {
      expect(
        BackupReminder.isDue(DateTime(2024, 1, 10),
            createdAt: created, lastVerifiedAt: DateTime(2024, 1, 8)),
        isFalse,
      );
    });
  });

  group('BackupReminder.snoozeRemaining', () {
    final now = DateTime(2024, 1, 10);

    test('null when no snooze is set', () {
      expect(BackupReminder.snoozeRemaining(now), isNull);
    });

    test('positive while the snooze is active', () {
      final until = now.add(const Duration(days: 7));
      expect(BackupReminder.snoozeRemaining(now, snoozeUntil: until),
          const Duration(days: 7));
      expect(
        BackupReminder.snoozeRemaining(
            until.subtract(const Duration(hours: 1)),
            snoozeUntil: until),
        const Duration(hours: 1),
      );
    });

    test('null once the snooze expires (boundary is exclusive)', () {
      final until = now.add(const Duration(days: 7));
      expect(BackupReminder.snoozeRemaining(until, snoozeUntil: until),
          isNull);
      expect(
        BackupReminder.snoozeRemaining(
            until.add(const Duration(seconds: 1)),
            snoozeUntil: until),
        isNull,
      );
    });
  });

  group('BackupReminder.nextDueAt', () {
    test('grace anchor before the first verification', () {
      expect(
        BackupReminder.nextDueAt(createdAt: created),
        created.add(const Duration(days: 3)),
      );
    });

    test('30-day cadence after a verification', () {
      final verified = DateTime(2024, 1, 1);
      expect(
        BackupReminder.nextDueAt(lastVerifiedAt: verified),
        verified.add(const Duration(days: 30)),
      );
      expect(BackupReminder.nextDueAt(), isNull);
    });
  });

  group('BackupReminder.walletCreatedAt', () {
    test('parses wallet_<epochMs> ids and rejects others', () {
      final ms = DateTime(2024, 1, 1).millisecondsSinceEpoch;
      expect(BackupReminder.walletCreatedAt('wallet_$ms'),
          DateTime(2024, 1, 1));
      expect(BackupReminder.walletCreatedAt('wallet_abc'), isNull);
      expect(BackupReminder.walletCreatedAt('wallet_'), isNull);
      expect(BackupReminder.walletCreatedAt('wallet_0'), isNull);
      expect(BackupReminder.walletCreatedAt('wallet_-5'), isNull);
      expect(BackupReminder.walletCreatedAt('other'), isNull);
    });
  });

  group('BackupReminder persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('markVerified round-trips and clears the snooze', () async {
      final at = DateTime(2024, 2, 1, 12);
      await BackupReminder.snooze(at);
      expect(await BackupReminder.snoozeUntil(),
          at.add(const Duration(days: 7)));

      await BackupReminder.markVerified(at);
      expect(await BackupReminder.lastVerifiedAt(), at);
      expect(await BackupReminder.snoozeUntil(), isNull);
    });

    test('snooze stores a 7-day window', () async {
      await BackupReminder.snooze(DateTime(2024, 2, 1));
      expect(await BackupReminder.snoozeUntil(), DateTime(2024, 2, 8));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('backup_reminder_snooze_until'), isNotNull);
    });

    test('ensureTracked is idempotent', () async {
      final first = DateTime(2024, 2, 1);
      await BackupReminder.ensureTracked(first);
      await BackupReminder.ensureTracked(first.add(const Duration(days: 10)));
      expect(await BackupReminder.firstTrackedAt(), first);
    });

    test('clear resets all reminder state', () async {
      await BackupReminder.ensureTracked(DateTime(2024, 2, 1));
      await BackupReminder.markVerified(DateTime(2024, 2, 2));
      await BackupReminder.snooze(DateTime(2024, 2, 3));
      await BackupReminder.clear();
      expect(await BackupReminder.firstTrackedAt(), isNull);
      expect(await BackupReminder.lastVerifiedAt(), isNull);
      expect(await BackupReminder.snoozeUntil(), isNull);
    });

    test('shouldRemind honours wallet age, snooze and verification',
        () async {
      final walletId = 'wallet_${DateTime(2024, 1, 1).millisecondsSinceEpoch}';

      // 10-day-old wallet, never verified → due.
      expect(
        await BackupReminder.shouldRemind(DateTime(2024, 1, 11),
            mnemonicWalletIds: [walletId]),
        isTrue,
      );

      // No mnemonic wallets → never.
      expect(
        await BackupReminder.shouldRemind(DateTime(2024, 1, 11)),
        isFalse,
      );

      // Snooze suppresses for 7 days…
      await BackupReminder.snooze(DateTime(2024, 1, 11));
      expect(
        await BackupReminder.shouldRemind(DateTime(2024, 1, 12),
            mnemonicWalletIds: [walletId]),
        isFalse,
      );
      // …and expiry makes it due again.
      expect(
        await BackupReminder.shouldRemind(DateTime(2024, 1, 19),
            mnemonicWalletIds: [walletId]),
        isTrue,
      );
    });

    test('shouldRemind uses the newest mnemonic wallet for the grace',
        () async {
      final old = 'wallet_${DateTime(2024, 1, 1).millisecondsSinceEpoch}';
      final fresh = 'wallet_${DateTime(2024, 1, 10).millisecondsSinceEpoch}';
      // A freshly created mnemonic wallet resets the grace window.
      expect(
        await BackupReminder.shouldRemind(DateTime(2024, 1, 11),
            mnemonicWalletIds: [old, fresh]),
        isFalse,
      );
      expect(
        await BackupReminder.shouldRemind(DateTime(2024, 1, 14),
            mnemonicWalletIds: [old, fresh]),
        isTrue,
      );
    });

    test('shouldRemind falls back to the first-tracked grace for legacy ids',
        () async {
      // Legacy ids without timestamps adopt the grace window at first check.
      expect(
        await BackupReminder.shouldRemind(DateTime(2024, 1, 11),
            mnemonicWalletIds: ['legacy']),
        isFalse,
      );
      expect(
        await BackupReminder.shouldRemind(DateTime(2024, 1, 12),
            mnemonicWalletIds: ['legacy']),
        isFalse,
      );
      expect(
        await BackupReminder.shouldRemind(DateTime(2024, 1, 15),
            mnemonicWalletIds: ['legacy']),
        isTrue,
      );
    });
  });
}
