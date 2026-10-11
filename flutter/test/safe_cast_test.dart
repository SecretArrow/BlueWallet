import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/utils/safe_cast.dart';

void main() {
  group('safeStringMap', () {
    test('passes through Map<String, dynamic>', () {
      expect(safeStringMap({'a': 1}), {'a': 1});
    });
    test('falls back when keys are not strings', () {
      expect(safeStringMap({1: 'x'}), isEmpty);
    });
    test('falls back on non-map', () {
      expect(safeStringMap('oops'), isEmpty);
      expect(safeStringMap(null), isEmpty);
      expect(safeStringMap(42, {'d': 1}), {'d': 1});
    });
  });

  group('safeMapString', () {
    test('trims and falls back', () {
      expect(safeMapString({'k': '  v '}, 'k'), 'v');
      expect(safeMapString({}, 'k'), '');
      expect(safeMapString({'k': ''}, 'k', 'fb'), 'fb');
      expect(safeMapString({'k': null}, 'k', 'fb'), 'fb');
    });
  });

  group('tryInt', () {
    test('parses without throwing', () {
      expect(tryInt('42'), 42);
      expect(tryInt(' 7 '), 7);
      expect(tryInt('abc'), isNull);
      expect(tryInt(''), isNull);
      expect(tryInt(null), isNull);
    });
  });

  group('extractStatusText + containsAny', () {
    test('aggregates and lowercases', () {
      final s = extractStatusText({'status': 'Confirmed', 'state': 'FINAL'});
      expect(s, contains('confirmed'));
      expect(containsAny(s, ['confirmed', 'success']), isTrue);
      expect(containsAny(s, ['reject']), isFalse);
    });
    test('handles boolean flags and empty map', () {
      expect(extractStatusText({'confirmed': true}), 'confirmed');
      expect(extractStatusText({}), isEmpty);
    });
  });

  group('unwrapTransactionEnvelope', () {
    test('unwraps nested transaction map', () {
      final inner = {'status': 'ok'};
      expect(unwrapTransactionEnvelope({'transaction': inner}), inner);
    });
    test('accepts Map<dynamic, dynamic> inner', () {
      final out = unwrapTransactionEnvelope({
        'transaction': <dynamic, dynamic>{'a': 1},
      });
      expect(out['a'], 1);
    });
    test('returns outer when no envelope', () {
      final outer = {'status': 'ok'};
      expect(unwrapTransactionEnvelope(outer), outer);
    });
  });
}
