/// Represents a wallet account stored on-device.
class WalletProfile {
  final String id;
  final String name;
  final String address;

  /// 'mnemonic' | 'random' | 'imported' | 'child' | null (legacy)
  final String? walletType;

  /// BIP-32/SLIP-0010 derivation path, e.g. "m/44'/540'/0'/0'/0'"
  final String? derivationPath;

  /// ID of the parent mnemonic wallet (only for child wallets)
  final String? parentId;

  /// True when this wallet was imported as an address only (watch-only).
  /// Watch-only wallets hold no secret key on device and can never sign
  /// or send funds - they only track balance and history via RPC.
  final bool watchOnly;

  const WalletProfile({
    required this.id,
    required this.name,
    required this.address,
    this.walletType,
    this.derivationPath,
    this.parentId,
    this.watchOnly = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        if (walletType != null) 'walletType': walletType,
        if (derivationPath != null) 'derivationPath': derivationPath,
        if (parentId != null) 'parentId': parentId,
        if (watchOnly) 'watchOnly': true,
      };

  factory WalletProfile.fromJson(Map<String, dynamic> json) => WalletProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String,
        walletType: json['walletType'] as String?,
        derivationPath: json['derivationPath'] as String?,
        parentId: json['parentId'] as String?,
        watchOnly: json['watchOnly'] == true,
      );

  bool get isMnemonicWallet =>
      walletType == 'mnemonic' || walletType == 'child';

  /// Watch-only wallets can view balance/history but never sign.
  bool get isWatchOnly => watchOnly;
}
