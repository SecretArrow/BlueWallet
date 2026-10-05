/// A saved address book entry.
class AddressEntry {
  final String id;
  final String label;
  final String address;

  const AddressEntry({
    required this.id,
    required this.label,
    required this.address,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'address': address,
      };

  factory AddressEntry.fromJson(Map<String, dynamic> json) => AddressEntry(
        id: json['id'] as String,
        label: json['label'] as String,
        address: json['address'] as String,
      );

  /// Lenient parse for stored data: garbage rows become null and are
  /// skipped by the loader instead of wiping the whole book.
  /// Pure, unit-tested.
  static AddressEntry? tryFromJson(dynamic e) {
    if (e is! Map) return null;
    final m = Map<String, dynamic>.from(e);
    // Address is an on-chain identifier: must genuinely be a string.
    // (Coercing 123 → "123" would display a phantom contact.)
    final addrRaw = m['address'];
    if (addrRaw is! String || addrRaw.trim().isEmpty) return null;
    return AddressEntry(
      id: m['id']?.toString() ?? 'addr_unknown',
      label: m['label']?.toString() ?? '',
      address: addrRaw.trim(),
    );
  }
}
