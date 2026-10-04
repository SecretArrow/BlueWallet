import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/services/crypto_service.dart';
import 'package:octopus_wallet/services/native_crypto.dart';

/// Defensive tests for tx input validation. Pure Dart — validation runs
/// before any native call, so no native library is needed.
void main() {
  Map<String, dynamic> valid({
    String sk = 'c2s=',
    String from = 'octA',
    String? to = 'octB',
    String? recipient,
    int? amountInt,
    String? amountStr,
    int nonce = 1,
    String? ou,
  }) =>
      {
        'sk': sk,
        'from': from,
        'to': to,
        'recipient': recipient,
        'amountInt': amountInt,
        'amountStr': amountStr,
        'nonce': nonce,
        'ou': ou,
      };

  void check(Map<String, dynamic> v) => CryptoService.requireTxInputs(
        skBase64: v['sk'] as String,
        fromAddress: v['from'] as String,
        toAddress: v['to'] as String?,
        recipientAddress: v['recipient'] as String?,
        amountInt: v['amountInt'] as int?,
        amountStr: v['amountStr'] as String?,
        nonce: v['nonce'] as int,
        ou: v['ou'] as String?,
      );

  group('requireTxInputs', () {
    test('accepts a fully valid set', () {
      check(valid(to: 'octB', amountInt: 5));
      check(valid(amountStr: '0')); // legit for self/circle/key_switch txs
      check(valid(to: null, amountInt: 5)); // to not applicable
    });

    test('rejects empty keys and addresses', () {
      expect(() => check(valid(sk: '')), throwsArgumentError);
      expect(() => check(valid(from: '')), throwsArgumentError);
      expect(() => check(valid(to: '')), throwsArgumentError);
      expect(
          () => check(valid(to: 'octB', recipient: '')),
          throwsArgumentError);
    });

    test('rejects non-positive int amounts', () {
      expect(() => check(valid(amountInt: 0)), throwsArgumentError);
      expect(() => check(valid(amountInt: -7)), throwsArgumentError);
    });

    test('rejects malformed string amounts, allows zero', () {
      for (final bad in ['', '   ', 'abc', '1.5', '-3']) {
        expect(() => check(valid(amountStr: bad)), throwsArgumentError,
            reason: 'for "$bad"');
      }
    });

    test('rejects non-positive nonces', () {
      expect(() => check(valid(amountInt: 1, nonce: 0)), throwsArgumentError);
      expect(() => check(valid(amountInt: 1, nonce: -2)), throwsArgumentError);
    });

    test('rejects empty ou when fixed', () {
      expect(() => check(valid(amountInt: 1, ou: '')), throwsArgumentError);
    });
  });

  group('ecdh key sizes', () {
    test('rejects wrong-sized keys before touching FFI', () {
      final ok32 = Uint8List(32);
      expect(() => NativeCrypto.ecdh(Uint8List(16), ok32),
          throwsArgumentError);
      expect(() => NativeCrypto.ecdh(ok32, Uint8List(64)),
          throwsArgumentError);
      expect(() => NativeCrypto.ecdh(Uint8List(0), Uint8List(0)),
          throwsArgumentError);
    });
  });
}
