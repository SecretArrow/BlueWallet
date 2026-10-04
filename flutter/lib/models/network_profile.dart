/// A network (node) profile.
class NetworkProfile {
  final String id;
  final String name;
  final String nodeUrl;
  final String explorerUrl;
  final bool isActive;

  const NetworkProfile({
    required this.id,
    required this.name,
    required this.nodeUrl,
    this.explorerUrl = '',
    this.isActive = false,
  });

  NetworkProfile copyWith({
    String? id,
    String? name,
    String? nodeUrl,
    String? explorerUrl,
    bool? isActive,
  }) =>
      NetworkProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        nodeUrl: nodeUrl ?? this.nodeUrl,
        explorerUrl: explorerUrl ?? this.explorerUrl,
        isActive: isActive ?? this.isActive,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nodeUrl': nodeUrl,
        'explorerUrl': explorerUrl,
        'isActive': isActive,
      };

  factory NetworkProfile.fromJson(Map<String, dynamic> json) => NetworkProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        nodeUrl: json['nodeUrl'] as String,
        explorerUrl: json['explorerUrl'] as String? ?? '',
        isActive: json['isActive'] as bool? ?? false,
      );
}
