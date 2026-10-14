import 'dart:math';

/// Pure helpers for the seed-phrase backup verification quiz.
///
/// Deliberately free of Flutter imports so the quiz logic stays
/// unit-testable in isolation (mirrors the pure native
/// `BackupReminderLogic` quiz helpers).
class VerifyBackupLogic {
  /// Number of words the quiz asks for.
  static const int kQuizWordCount = 3;

  /// Deterministic quiz seed derived from the wallet id and the
  /// day-of-year of [now]: stable within a day, different across days.
  static int seedFor(String walletId, DateTime now) {
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final key = '$walletId#$dayOfYear';
    // FNV-1a over the code units, masked to 31 bits so the result is a
    // portable [Random] seed on every platform.
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  /// [count] distinct quiz positions in `1..wordCount`, ascending.
  ///
  /// Asks for fewer positions when the phrase is shorter than [count];
  /// returns an empty list for non-positive word counts.
  static List<int> pickPositions(
    int wordCount,
    Random random, {
    int count = kQuizWordCount,
  }) {
    if (wordCount <= 0) return const [];
    final wanted = count > wordCount ? wordCount : count;
    final positions = <int>[];
    while (positions.length < wanted) {
      final candidate = random.nextInt(wordCount) + 1;
      if (!positions.contains(candidate)) positions.add(candidate);
    }
    positions.sort();
    return positions;
  }

  /// Single-word comparison: trimmed and case-insensitive.
  static bool wordMatches(String expected, String actual) {
    final trimmed = expected.trim().toLowerCase();
    return trimmed.isNotEmpty && trimmed == actual.trim().toLowerCase();
  }

  /// Whether every entry in [answers] matches the mnemonic word at the
  /// corresponding position in [positions]. The comparison happens in
  /// memory only — nothing is logged or persisted.
  static bool answersMatch(
    List<String> words,
    List<int> positions,
    List<String> answers,
  ) {
    if (positions.length != answers.length || positions.isEmpty) {
      return false;
    }
    for (var i = 0; i < positions.length; i++) {
      final index = positions[i] - 1;
      if (index < 0 || index >= words.length) return false;
      if (!wordMatches(words[index], answers[i])) return false;
    }
    return true;
  }
}
