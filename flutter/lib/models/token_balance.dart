/// A token balance snapshot for the dashboard.
class TokenBalance {
  final String symbol;
  final String name;
  final String balance;
  final String address; // Token contract / OCT for native

  const TokenBalance({
    required this.symbol,
    required this.name,
    required this.balance,
    required this.address,
  });

  factory TokenBalance.fromJson(Map<String, dynamic> json) => TokenBalance(
        symbol: json['symbol'] as String? ?? '',
        name: json['name'] as String? ?? '',
        balance: json['balance']?.toString() ?? '0',
        address: json['address'] as String? ?? '',
      );
}
