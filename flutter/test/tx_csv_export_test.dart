import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/models/tx_record.dart';
import 'package:octopus_wallet/utils/tx_csv_export.dart';

/// RFC 4180 compliance tests for the transaction history CSV export.
///
/// TxRecord has a public const constructor, so records are built directly.
void main() {
  const header =
      'date,direction,type,op_type,amount,from,to,memo,fee,status,tx_hash,'
      'block_hash\r\n';

  TxRecord rec({
    String hash = 'h0',
    String type = 'sent',
    String amount = '1000000',
    String from = 'oct_from',
    String to = 'oct_to',
    int timestamp = 0,
    String status = 'confirmed',
    String? memo,
    String? opType = 'standard',
    String? fee,
    String? blockHash,
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
      fee: fee,
      blockHash: blockHash,
    );
  }

  group('buildTxHistoryCsv', () {
    test('empty list → header row only', () {
      expect(buildTxHistoryCsv(const []), header);
    });

    test('header row matches TxRecord fields and ends with CRLF', () {
      final csv = buildTxHistoryCsv([rec()]);
      final firstLine = csv.substring(0, csv.indexOf('\r\n'));
      expect(
        firstLine,
        'date,direction,type,op_type,amount,from,to,memo,fee,status,'
        'tx_hash,block_hash',
      );
      expect(csv.startsWith('date,'), isTrue);
    });

    test('every record (incl. header) is terminated with CRLF, no bare LF', () {
      // Records without embedded newlines: after removing the CRLF
      // terminators no CR/LF may remain anywhere.
      final csv = buildTxHistoryCsv([
        rec(hash: 'a', memo: 'no special chars'),
        rec(hash: 'b', memo: 'has, comma'),
      ]);
      expect(csv.endsWith('\r\n'), isTrue);
      expect('\r\n'.allMatches(csv).length, 3); // header + 2 rows
      final stripped = csv.replaceAll('\r\n', '');
      expect(stripped.contains('\n'), isFalse);
      expect(stripped.contains('\r'), isFalse);
    });

    test('rows preserve input order', () {
      final csv = buildTxHistoryCsv([
        rec(hash: 'tx-1'),
        rec(hash: 'tx-2'),
        rec(hash: 'tx-3'),
      ]);
      expect(csv.indexOf('tx-1'), lessThan(csv.indexOf('tx-2')));
      expect(csv.indexOf('tx-2'), lessThan(csv.indexOf('tx-3')));
    });

    test('date column is ISO 8601 UTC; unknown timestamp stays empty', () {
      final ts = DateTime.utc(2026, 2, 2, 2, 40).millisecondsSinceEpoch;
      final csv = buildTxHistoryCsv([
        rec(hash: 'dated', timestamp: ts),
        rec(hash: 'undated', timestamp: 0),
      ]);
      expect(csv, contains('2026-02-02T02:40:00.000Z'));
      // The undated row starts with an empty date field.
      expect(csv, contains('\r\n,'));
    });

    test('direction follows type / myAddress semantics', () {
      final me = 'my_addr';
      final csv = buildTxHistoryCsv([
        rec(hash: 'a', type: 'sent'),
        rec(hash: 'b', type: 'received'),
        rec(hash: 'c', type: 'encrypted'),
        rec(hash: 'd', type: 'standard', from: me, to: 'other'),
      ], myAddress: me);
      // With myAddress: sent → outgoing, received → incoming, standard with
      // from == me → outgoing, encrypted (from != me) → incoming.
      expect(csv, contains(',outgoing,sent,'));
      expect(csv, contains(',incoming,received,'));
      expect(csv, contains(',incoming,encrypted,'));
      expect(csv, contains(',outgoing,standard,'));

      // Without myAddress unknown types pass through unchanged.
      final bare = buildTxHistoryCsv([rec(hash: 'e', type: 'encrypted')]);
      expect(bare, contains(',encrypted,'));
    });

    test('plain fields are emitted unquoted', () {
      final csv = buildTxHistoryCsv([rec(hash: 'plain')]);
      expect(csv, contains(',1000000,oct_from,oct_to,'));
      expect(csv.contains('"'), isFalse);
    });

    test('field containing a comma is quoted', () {
      final csv = buildTxHistoryCsv([rec(memo: 'lunch, coffee')]);
      expect(csv, contains('"lunch, coffee"'));
    });

    test('quotes are doubled inside quoted fields', () {
      final csv = buildTxHistoryCsv([rec(memo: 'say "hi"')]);
      expect(csv, contains('"say ""hi"""'));
    });

    test('newline inside a field is quoted and preserved', () {
      final csv = buildTxHistoryCsv([rec(memo: 'line1\nline2')]);
      expect(csv, contains('"line1\nline2"'));
      // The embedded newline must not create a bare LF record terminator.
      final stripped = csv.replaceAll('\r\n', '');
      expect(stripped, contains('line1\nline2'));
    });

    test('full document for a known record', () {
      final csv = buildTxHistoryCsv([
        rec(
          hash: 'abc',
          type: 'sent',
          amount: '1500000',
          from: 'addr_from',
          to: 'addr_to',
          status: 'confirmed',
          opType: 'standard',
        ),
      ]);
      expect(
          csv,
          'date,direction,type,op_type,amount,from,to,memo,fee,status,'
          'tx_hash,block_hash\r\n'
          ',outgoing,sent,standard,1500000,addr_from,addr_to,,,confirmed,'
          'abc,\r\n');
    });
  });
}
