/// Pure search + direction filtering for the transaction history list.
///
/// Extracted from the HistoryTab widget so the composition rules
/// (search ∩ direction chip) are unit-testable without widget plumbing.
library;

import '../models/tx_record.dart';
import '../services/wallet_service.dart';

/// Direction/type chips shown above the history list.
enum TxHistoryDirectionFilter { all, incoming, outgoing, stealth }

/// True when [tx] renders as an outgoing row — the exact semantics the
/// history row widget uses: `type == 'sent'` or the sender is [myAddress].
bool isOutgoingTx(TxRecord tx, String myAddress) {
  return tx.type == 'sent' ||
      (myAddress.isNotEmpty && tx.fromAddress == myAddress);
}

/// Applies the search query and the direction chip to [txs] and returns the
/// matching records in input order.
///
/// The two filters compose with AND (search ∩ chip). An empty or
/// whitespace-only [query] matches everything. The query is a
/// case-insensitive substring matched against the counterparty addresses
/// (`from`/`to`), the memo/message and the amount (both the raw value and
/// its formatted OCT display form, e.g. `1.5`).
List<TxRecord> filterTxHistory(
  List<TxRecord> txs, {
  String query = '',
  TxHistoryDirectionFilter direction = TxHistoryDirectionFilter.all,
  String myAddress = '',
}) {
  final q = query.trim().toLowerCase();
  return txs
      .where((tx) =>
          matchesDirectionFilter(tx, direction, myAddress) &&
          (q.isEmpty || matchesSearchQuery(tx, q)))
      .toList();
}

/// Direction chip predicate: All / Incoming / Outgoing / Stealth.
bool matchesDirectionFilter(
  TxRecord tx,
  TxHistoryDirectionFilter direction,
  String myAddress,
) {
  switch (direction) {
    case TxHistoryDirectionFilter.all:
      return true;
    case TxHistoryDirectionFilter.incoming:
      return !isOutgoingTx(tx, myAddress);
    case TxHistoryDirectionFilter.outgoing:
      return isOutgoingTx(tx, myAddress);
    case TxHistoryDirectionFilter.stealth:
      return (tx.opType ?? '').toLowerCase() == 'stealth';
  }
}

/// Case-insensitive substring match over addresses, memo and amount.
bool matchesSearchQuery(TxRecord tx, String lowercasedQuery) {
  final candidates = [
    tx.fromAddress,
    tx.toAddress,
    tx.memo ?? '',
    tx.amount,
  ];
  for (final value in candidates) {
    if (value.toLowerCase().contains(lowercasedQuery)) return true;
  }
  // Amount also matches in its formatted OCT form ("1500000" → "1.50"),
  // so users can search "1.5" instead of raw microcoins.
  final raw = int.tryParse(tx.amount);
  if (raw != null) {
    if (WalletService.formatOct(raw).toLowerCase().contains(lowercasedQuery)) {
      return true;
    }
  }
  return false;
}
