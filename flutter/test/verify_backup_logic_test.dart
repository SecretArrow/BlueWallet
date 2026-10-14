import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:octopus_wallet/services/verify_backup_logic.dart';

void main() {
  group('VerifyBackupLogic.seedFor', () {
    test('stable within a day', () {
      final morning = DateTime(2024, 5, 10, 8);
      final evening = DateTime(2024, 5, 10, 22);
      expect(
        VerifyBackupLogic.seedFor('wallet_1', morning),
        VerifyBackupLogic.seedFor('wallet_1', evening),
      );
    });

    test('varies across days', () {
      final day1 = DateTime(2024, 5, 10);
      final day2 = DateTime(2024, 5, 11);
      expect(
        VerifyBackupLogic.seedFor('wallet_1', day1),
        isNot(VerifyBackupLogic.seedFor('wallet_1', day2)),
      );
    });

    test('varies across wallets', () {
      final day = DateTime(2024, 5, 10);
      expect(
        VerifyBackupLogic.seedFor('wallet_1', day),
        isNot(VerifyBackupLogic.seedFor('wallet_2', day)),
      );
    });

    test('crosses the year boundary (different day-of-year)', () {
      final dec31 = DateTime(2023, 12, 31);
      final jan1 = DateTime(2024, 1, 1);
      expect(
        VerifyBackupLogic.seedFor('w', dec31),
        isNot(VerifyBackupLogic.seedFor('w', jan1)),
      );
    });

    test('seed is a valid non-negative Random seed', () {
      final seed = VerifyBackupLogic.seedFor('wallet_1', DateTime(2024, 5, 10));
      expect(seed, greaterThanOrEqualTo(0));
      expect(() => Random(seed), returnsNormally);
    });
  });

  group('VerifyBackupLogic.pickPositions', () {
    test('deterministic for a given seed', () {
      final a = VerifyBackupLogic.pickPositions(12, Random(1234));
      final b = VerifyBackupLogic.pickPositions(12, Random(1234));
      expect(a, b);
    });

    test('three distinct positions within 1..wordCount, ascending', () {
      final positions = VerifyBackupLogic.pickPositions(12, Random(7));
      expect(positions.length, 3);
      expect(positions.toSet().length, 3);
      for (final p in positions) {
        expect(p, greaterThanOrEqualTo(1));
        expect(p, lessThanOrEqualTo(12));
      }
      expect(positions, equals([...positions]..sort()));
    });

    test('distinct positions for many seeds', () {
      for (var seed = 0; seed < 200; seed++) {
        final positions = VerifyBackupLogic.pickPositions(12, Random(seed));
        expect(positions.toSet().length, positions.length,
            reason: 'seed $seed produced duplicates');
      }
    });

    test('clamps when the phrase is shorter than the quiz length', () {
      expect(VerifyBackupLogic.pickPositions(2, Random(3)), [1, 2]);
      expect(VerifyBackupLogic.pickPositions(1, Random(3)), [1]);
    });

    test('empty for non-positive word counts', () {
      expect(VerifyBackupLogic.pickPositions(0, Random(3)), isEmpty);
      expect(VerifyBackupLogic.pickPositions(-1, Random(3)), isEmpty);
    });
  });

  group('VerifyBackupLogic comparison', () {
    final words = ['rural', 'dad', 'disagree', 'shiver', 'return', 'cereal'];
    final positions = [2, 5];

    test('wordMatches trims and ignores case', () {
      expect(VerifyBackupLogic.wordMatches('rural', '  RURAL '), isTrue);
      expect(VerifyBackupLogic.wordMatches('rural', 'rural'), isTrue);
      expect(VerifyBackupLogic.wordMatches('rural', ' ruraL'), isTrue);
      expect(VerifyBackupLogic.wordMatches('rural', 'urban'), isFalse);
      expect(VerifyBackupLogic.wordMatches('rural', ''), isFalse);
      expect(VerifyBackupLogic.wordMatches('rural', '  '), isFalse);
      expect(VerifyBackupLogic.wordMatches('', 'x'), isFalse);
    });

    test('answersMatch compares the words at the quiz positions', () {
      expect(
          VerifyBackupLogic.answersMatch(words, positions, ['dad', 'return']),
          isTrue);
      expect(
          VerifyBackupLogic.answersMatch(words, positions, [' DAD ', 'Return']),
          isTrue);
      expect(
          VerifyBackupLogic.answersMatch(words, positions, ['dad', 'wrong']),
          isFalse);
      expect(
          VerifyBackupLogic.answersMatch(words, positions, ['wrong', 'return']),
          isFalse);
    });

    test('answersMatch rejects length mismatches and empty quizzes', () {
      expect(VerifyBackupLogic.answersMatch(words, positions, ['dad']),
          isFalse);
      expect(
          VerifyBackupLogic.answersMatch(words, positions, ['dad', 'a', 'b']),
          isFalse);
      expect(VerifyBackupLogic.answersMatch(words, [], []), isFalse);
    });

    test('answersMatch guards out-of-range positions', () {
      expect(VerifyBackupLogic.answersMatch(words, [99], ['x']), isFalse);
      expect(VerifyBackupLogic.answersMatch(words, [0], ['x']), isFalse);
      expect(VerifyBackupLogic.answersMatch(words, [-1], ['x']), isFalse);
    });
  });
}
