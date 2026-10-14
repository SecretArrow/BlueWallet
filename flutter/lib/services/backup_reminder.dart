import 'package:shared_preferences/shared_preferences.dart';

/// Backup reminder + seed-verification bookkeeping.
///
/// Semantics (mirrors the native `BackupReminderLogic` helper):
///  * never verified AND tracking started ≥ [kInitialGraceDays] ago → due;
///  * last verification ≥ [kRemindEveryDays] ago → due;
///  * a snooze suppresses the reminder until it expires.
///
/// The reminder state is GLOBAL (not per wallet): native wallet ids are
/// human-readable names that change on rename, so no wallet id is stable on
/// both sides of the app pair — the native helper stores the same global
/// keys in its `backup_reminder_prefs` file.
class BackupReminder {
  /// Grace window before the first reminder for a wallet that was never
  /// verified.
  static const int kInitialGraceDays = 3;

  /// Re-reminder interval once a backup has been verified.
  static const int kRemindEveryDays = 30;

  /// How long [snooze] hides the reminder.
  static const int kSnoozeDays = 7;

  static const String _kFirstTrackedAtKey = 'backup_reminder_first_tracked_at';
  static const String _kLastVerifiedAtKey = 'backup_reminder_last_verified_at';
  static const String _kSnoozeUntilKey = 'backup_reminder_snooze_until';

  // ── Pure logic ───────────────────────────────────────────────────────────

  /// Whether the reminder is due at [now].
  ///
  /// Boundary convention: the reminder fires once the full interval has
  /// elapsed — a wallet created exactly [kInitialGraceDays] ago is due, and
  /// a verification exactly [kRemindEveryDays] ago is due.
  static bool isDue(
    DateTime now, {
    DateTime? createdAt,
    DateTime? lastVerifiedAt,
  }) {
    final verified = lastVerifiedAt;
    if (verified != null) {
      return now.difference(verified).inDays >= kRemindEveryDays;
    }
    final created = createdAt;
    if (created != null) {
      return now.difference(created).inDays >= kInitialGraceDays;
    }
    return false;
  }

  /// Remaining snooze time at [now], or null when no unexpired snooze is
  /// set. The boundary is exclusive: at exactly [snoozeUntil] the snooze
  /// has expired.
  static Duration? snoozeRemaining(DateTime now, {DateTime? snoozeUntil}) {
    final until = snoozeUntil;
    if (until == null) return null;
    final remaining = until.difference(now);
    if (remaining.isNegative || remaining == Duration.zero) return null;
    return remaining;
  }

  /// First instant at which the reminder can become due, or null while
  /// tracking has not started (nothing verified and no creation time known).
  static DateTime? nextDueAt({DateTime? createdAt, DateTime? lastVerifiedAt}) {
    if (lastVerifiedAt != null) {
      return lastVerifiedAt.add(const Duration(days: kRemindEveryDays));
    }
    if (createdAt != null) {
      return createdAt.add(const Duration(days: kInitialGraceDays));
    }
    return null;
  }

  /// Creation timestamp encoded in wallet ids (`wallet_<epoch ms>`),
  /// or null when the id does not encode a timestamp.
  static DateTime? walletCreatedAt(String walletId) {
    const prefix = 'wallet_';
    if (!walletId.startsWith(prefix)) return null;
    final ms = int.tryParse(walletId.substring(prefix.length));
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // ── Persistence (SharedPreferences) ──────────────────────────────────────

  static Future<DateTime?> _readDate(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// When backup tracking began (null until [ensureTracked] ran).
  static Future<DateTime?> firstTrackedAt() => _readDate(_kFirstTrackedAtKey);

  /// When the backup was last verified, or null if never.
  static Future<DateTime?> lastVerifiedAt() => _readDate(_kLastVerifiedAtKey);

  /// When the current snooze expires, or null when not snoozed.
  static Future<DateTime?> snoozeUntil() => _readDate(_kSnoozeUntilKey);

  /// Records [now] as the moment backup tracking began (idempotent).
  /// Legacy installs without timestamped wallet ids adopt the grace window
  /// from their first run with this feature.
  static Future<void> ensureTracked(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kFirstTrackedAtKey)) {
      await prefs.setString(_kFirstTrackedAtKey, now.toIso8601String());
    }
  }

  /// Marks the backup verified at [now]; clears any active snooze.
  static Future<void> markVerified(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastVerifiedAtKey, now.toIso8601String());
    await prefs.remove(_kSnoozeUntilKey);
  }

  /// Hides the reminder until [kSnoozeDays] after [now].
  static Future<void> snooze(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kSnoozeUntilKey,
      now.add(const Duration(days: kSnoozeDays)).toIso8601String(),
    );
  }

  /// Removes all reminder state (test/debug hook).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFirstTrackedAtKey);
    await prefs.remove(_kLastVerifiedAtKey);
    await prefs.remove(_kSnoozeUntilKey);
  }

  // ── Composite check for UI ───────────────────────────────────────────────

  /// Whether the reminder banner should be visible at [now].
  ///
  /// [mnemonicWalletIds] are the mnemonic ROOT wallet ids (parent ids for
  /// derived children); an empty list means there is nothing to back up.
  /// The newest wallet creation time anchors the grace window; ids without
  /// an embedded timestamp fall back to the persisted first-tracked time.
  static Future<bool> shouldRemind(
    DateTime now, {
    List<String> mnemonicWalletIds = const [],
  }) async {
    if (mnemonicWalletIds.isEmpty) return false;

    DateTime? createdAt;
    for (final id in mnemonicWalletIds) {
      final created = walletCreatedAt(id);
      if (created != null && (createdAt == null || created.isAfter(createdAt))) {
        createdAt = created;
      }
    }
    if (createdAt == null) {
      await ensureTracked(now);
      createdAt = await firstTrackedAt();
    }

    if (snoozeRemaining(now, snoozeUntil: await snoozeUntil()) != null) {
      return false;
    }
    return isDue(
      now,
      createdAt: createdAt,
      lastVerifiedAt: await lastVerifiedAt(),
    );
  }
}
