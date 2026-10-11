import 'dart:convert';

/// Per-origin dApp session: which address + scopes an origin was granted.
///
/// Persisted by [DappSessionStore] so approvals survive restarts, and
/// revocable from the dApp origins / permissions screens.
class DappSession {
  final String origin;
  final String address;
  final List<String> scopes;
  final int connectedAtMs;

  const DappSession({
    required this.origin,
    required this.address,
    required this.scopes,
    required this.connectedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'origin': origin,
        'address': address,
        'scopes': scopes,
        'connectedAtMs': connectedAtMs,
      };

  static DappSession? fromJson(dynamic v) {
    try {
      if (v is! Map) return null;
      final origin = v['origin']?.toString() ?? '';
      final address = v['address']?.toString() ?? '';
      if (origin.isEmpty || address.isEmpty) return null;
      final rawScopes = v['scopes'];
      final scopes = rawScopes is List
          ? rawScopes.map((e) => e.toString()).toList()
          : <String>['accounts'];
      final ts = v['connectedAtMs'] is num
          ? (v['connectedAtMs'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch;
      return DappSession(
        origin: origin,
        address: address,
        scopes: scopes,
        connectedAtMs: ts,
      );
    } catch (_) {
      return null;
    }
  }

  static String encodeList(List<DappSession> sessions) =>
      jsonEncode(sessions.map((s) => s.toJson()).toList());

  static List<DappSession> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <DappSession>[];
      for (final item in decoded) {
        final s = DappSession.fromJson(item);
        if (s != null) out.add(s);
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}
