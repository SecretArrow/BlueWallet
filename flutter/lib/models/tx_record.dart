/// A transaction history record matching the node API response shape.
class TxRecord {
  final String hash;
  final String type;       // 'sent' | 'received' | 'encrypted' | 'decrypted'
  final String amount;
  final String fromAddress;
  final String toAddress;
  final int timestamp;     // unix milliseconds
  final String status;     // 'confirmed' | 'pending' | 'failed'
  final String? memo;
  final String? opType;    // 'standard' | 'encrypt' | 'decrypt' | 'stealth'
  final String? fee;
  final String? blockHash;

  const TxRecord({
    required this.hash,
    required this.type,
    required this.amount,
    required this.fromAddress,
    required this.toAddress,
    required this.timestamp,
    required this.status,
    this.memo,
    this.opType,
    this.fee,
    this.blockHash,
  });

  factory TxRecord.fromJson(Map<String, dynamic> json) {
    final from = json['from']?.toString() ?? '';
    final to = (json['to_'] ?? json['to'])?.toString() ?? '';
    return TxRecord(
      hash: json['hash']?.toString() ?? json['tx_hash']?.toString() ?? '',
      type: json['type']?.toString() ?? 'standard',
      amount: json['amount']?.toString() ?? '0',
      fromAddress: from,
      toAddress: to,
      timestamp: _parseTs(json['timestamp']),
      status: json['status']?.toString() ?? 'confirmed',
      memo: json['message']?.toString() ?? json['memo']?.toString(),
      opType: json['op_type']?.toString() ?? 'standard',
      fee: json['fee']?.toString(),
      blockHash: json['block_hash']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'type': type,
        'amount': amount,
        'from': fromAddress,
        'to_': toAddress,
        'timestamp': timestamp,
        'status': status,
        if (memo != null) 'message': memo,
        if (opType != null) 'op_type': opType,
        if (fee != null) 'fee': fee,
        if (blockHash != null) 'block_hash': blockHash,
      };

  static int _parseTs(dynamic ts) {
    if (ts == null) return 0;
    if (ts is int) {
      // if seconds-scale, convert to ms
      return ts > 1e12.toInt() ? ts : ts * 1000;
    }
    if (ts is double) {
      return ts > 1e12 ? ts.toInt() : (ts * 1000).toInt();
    }
    final d = double.tryParse(ts.toString());
    if (d != null) return d > 1e12 ? d.toInt() : (d * 1000).toInt();
    return 0;
  }
}
