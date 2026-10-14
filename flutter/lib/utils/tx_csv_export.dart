/// RFC 4180-compliant CSV export for transaction history.
///
/// Pure string building (no I/O) so it is unit-testable. Every field that
/// contains a comma, double quote, CR or LF is wrapped in double quotes and
/// embedded quotes are doubled, per RFC 4180 section 2. Each record —
/// including the header — is terminated with CRLF.
library;

import '../models/tx_record.dart';

/// Column order for the exported CSV (mirrors the native Android exporter).
const txHistoryCsvHeader = <String>[
  'date',
  'direction',
  'type',
  'op_type',
  'amount',
  'from',
  'to',
  'memo',
  'fee',
  'status',
  'tx_hash',
  'block_hash',
];

/// Builds the transaction history CSV document for [txs].
///
/// Rows are emitted in the given order (callers pass the currently filtered
/// list). [myAddress], when known, is used to derive the `direction` column
/// with the exact same semantics the history rows use on screen
/// (`type == 'sent' || fromAddress == myAddress` → `outgoing`). Without it,
/// `sent`/`received` map to `outgoing`/`incoming` and other types pass
/// through unchanged.
String buildTxHistoryCsv(List<TxRecord> txs, {String? myAddress}) {
  final buffer = StringBuffer();
  _appendRow(buffer, txHistoryCsvHeader);
  for (final tx in txs) {
    _appendRow(buffer, _rowValues(tx, myAddress));
  }
  return buffer.toString();
}

/// Escapes a single CSV field per RFC 4180: fields containing a comma,
/// double quote, CR or LF are quoted, and embedded quotes are doubled.
String escapeCsvField(String field) {
  final needsQuotes = field.contains(',') ||
      field.contains('"') ||
      field.contains('\r') ||
      field.contains('\n');
  if (!needsQuotes) return field;
  final doubled = field.replaceAll('"', '""');
  return '"$doubled"';
}

void _appendRow(StringBuffer buffer, List<String> fields) {
  for (var i = 0; i < fields.length; i++) {
    if (i > 0) buffer.write(',');
    buffer.write(escapeCsvField(fields[i]));
  }
  buffer.write('\r\n');
}

List<String> _rowValues(TxRecord tx, String? myAddress) {
  return [
    _isoDate(tx.timestamp),
    _direction(tx, myAddress),
    tx.type,
    tx.opType ?? '',
    tx.amount,
    tx.fromAddress,
    tx.toAddress,
    tx.memo ?? '',
    tx.fee ?? '',
    tx.status,
    tx.hash,
    tx.blockHash ?? '',
  ];
}

/// ISO 8601 / UTC date from the millisecond timestamp; empty when unknown
/// (timestamp 0 renders as "Unknown date" in the UI).
String _isoDate(int timestampMs) {
  if (timestampMs <= 0) return '';
  return DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true)
      .toIso8601String();
}

String _direction(TxRecord tx, String? myAddress) {
  final selfKnown = myAddress != null && myAddress.isNotEmpty;
  if (selfKnown) {
    final isSent = tx.type == 'sent' || tx.fromAddress == myAddress;
    return isSent ? 'outgoing' : 'incoming';
  }
  if (tx.type == 'sent') return 'outgoing';
  if (tx.type == 'received') return 'incoming';
  return tx.type;
}
