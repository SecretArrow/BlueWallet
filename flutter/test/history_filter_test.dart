import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/models/tx_record.dart';
import 'package:octopus_wallet/utils/history_filter.dart';

/// Pure-function tests for the history search + direction filter chips.
///
/// Composition rule: search query ∩ direction chip. Empty (or whitespace)
/// queries match everything.
void main() {
  const me = 'oct_me';
  const alice = 'oct_alice';
  const bob = 'oct_bob';

  TxRecord rec({
    String hash = 'h0',
    String type = 'sent',
    String amount = '1000000',
    String from = me,
    String to = alice,
    int timestamp = 1770000000000,
    String status = 'confirmed',
    String? memo,
    String? opType = 'standard',
  }) {
    return TxRecord(
      hash: hash,
      type: type,
      amount: amount,
      fromAddress: from,
      toAddress: to,
      timestamp: timestamp,
      status: status,
      memo: memo,
      opType: opType,
    );
  }

  final txs = <TxRecord>[
    rec(
        hash: 't1',
        type: 'sent',
        from: me,
        to: alice,
        amount: '1500000',
        memo: 'lunch'),
    rec(
        hash: 't2',
        type: 'received',
        from: bob,
        to: me,
        amount: '2500000',
        memo: 'thanks!'),
    rec(
        hash: 't3',
        type: 'sent',
        from: me,
        to: bob,
        amount: '500000',
        memo: null,
        opType: 'stealth'),
    rec(hash: 't4', type: 'encrypted', from: me, to: me, amount: '0'),
  ];

  group('isOutgoingTx', () {
    test("type 'sent' is outgoing even without an address", () {
      expect(isOutgoingTx(rec(type: 'sent'), ''), isTrue);
    });

    test('from == myAddress marks outgoing regardless of type', () {
      expect(isOutgoingTx(rec(type: 'encrypted', from: me), me), isTrue);
      expect(isOutgoingTx(rec(type: 'standard', from: me), me), isTrue);
    });

    test('received from someone else is incoming', () {
      expect(isOutgoingTx(rec(type: 'received', from: bob), me), isFalse);
    });
  });

  group('search query', () {
    test('empty and whitespace-only queries return everything', () {
      expect(filterTxHistory(txs, query: ''), hasLength(4));
      expect(filterTxHistory(txs, query: '   '), hasLength(4));
      expect(filterTxHistory(txs), hasLength(4));
    });

    test('substring match on counterparty addresses is case-insensitive', () {
      expect(
        filterTxHistory(txs, query: 'OCT_AL').map((t) => t.hash),
        ['t1'],
      );
      // t2 and t3 involve bob; searching bob's address matches both.
      expect(
        filterTxHistory(txs, query: bob).map((t) => t.hash),
        ['t2', 't3'],
      );
    });

    test('substring match on memo', () {
      expect(
        filterTxHistory(txs, query: 'LUNCH').map((t) => t.hash),
        ['t1'],
      );
    });

    test('amount matches raw microcoins and OCT display form', () {
      // Raw amount string.
      expect(
        filterTxHistory(txs, query: '2500000').map((t) => t.hash),
        ['t2'],
      );
      // Formatted OCT display: 1500000 → "1.50", so "1.5" must match.
      expect(
        filterTxHistory(txs, query: '1.5').map((t) => t.hash),
        ['t1'],
      );
    });

    test('no match returns an empty list', () {
      expect(filterTxHistory(txs, query: 'zzz-not-there'), isEmpty);
    });
  });

  group('direction chips', () {
    test('all keeps every record', () {
      expect(
        filterTxHistory(txs,
            direction: TxHistoryDirectionFilter.all, myAddress: me),
        hasLength(4),
      );
    });

    test('incoming keeps only non-sent rows', () {
      expect(
        filterTxHistory(txs,
                direction: TxHistoryDirectionFilter.incoming,
                myAddress: me)
            .map((t) => t.hash),
        ['t2'],
      );
    });

    test('outgoing keeps only sent rows', () {
      expect(
        filterTxHistory(txs,
                direction: TxHistoryDirectionFilter.outgoing,
                myAddress: me)
            .map((t) => t.hash),
        ['t1', 't3', 't4'],
      );
    });

    test('stealth chip matches opType == stealth', () {
      expect(
        filterTxHistory(txs,
                direction: TxHistoryDirectionFilter.stealth,
                myAddress: me)
            .map((t) => t.hash),
        ['t3'],
      );
    });
  });

  group('composition (search ∩ chip)', () {
    test('query narrows the chip-filtered result', () {
      // Outgoing ∩ "bob": only the stealth send to bob.
      expect(
        filterTxHistory(txs,
                query: bob,
                direction: TxHistoryDirectionFilter.outgoing,
                myAddress: me)
            .map((t) => t.hash),
        ['t3'],
      );
    });

    test('chip narrows the query result', () {
      expect(
        filterTxHistory(txs,
                query: 'oct_',
                direction: TxHistoryDirectionFilter.incoming,
                myAddress: me)
            .map((t) => t.hash),
        ['t2'],
      );
    });

    test('query and chip that share no records produce an empty list', () {
      expect(
        filterTxHistory(txs,
            query: 'lunch',
            direction: TxHistoryDirectionFilter.incoming,
            myAddress: me),
        isEmpty,
      );
    });
  });
}
