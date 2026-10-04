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
}
