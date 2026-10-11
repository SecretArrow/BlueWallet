/// Defensive parsing/casting helpers shared by router + screens.
///
/// All helpers are pure (no BuildContext, no I/O) so they are unit-testable.
/// They never throw on malformed input — they return a safe fallback.
library;

/// Safely converts router `extra` (or any dynamic JSON-ish value) to a
/// `Map<String, dynamic>`. Returns [fallback] when the value is not a Map.
Map<String, dynamic> safeStringMap(dynamic value,
    [Map<String, dynamic>? fallback]) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      return fallback ?? <String, dynamic>{};
    }
  }
  return fallback ?? <String, dynamic>{};
}

/// Safely extracts a non-empty trimmed string from a map, or [fallback].
String safeMapString(Map<String, dynamic> map, String key,
    [String fallback = '']) {
  final v = map[key];
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

/// Parses an integer without throwing. Returns null on invalid input.
int? tryInt(String? raw) {
  if (raw == null) return null;
  return int.tryParse(raw.trim());
}

/// Aggregates status-ish fields of a transaction JSON object into a single
/// lowercase string (mirrors Android `extractStatusText`).
String extractStatusText(Map<String, dynamic> tx) {
  final parts = <String>[
    tx['status']?.toString() ?? '',
    tx['tx_status']?.toString() ?? '',
    tx['state']?.toString() ?? '',
    tx['final_status']?.toString() ?? '',
    if (tx['confirmed'] == true) 'confirmed',
    if (tx['rejected'] == true) 'rejected',
  ];
  return parts.where((s) => s.isNotEmpty).join(' | ').toLowerCase();
}

/// Returns true when [value] contains any of [needles].
bool containsAny(String value, List<String> needles) =>
    needles.any((n) => value.contains(n));

/// Safely unwraps a `{transaction: {...}}` RPC envelope. Accepts maps with
/// dynamic key/value types (as produced by `jsonDecode`) without throwing.
Map<String, dynamic> unwrapTransactionEnvelope(Map<String, dynamic> result) {
  final inner = result['transaction'];
  if (inner is Map<String, dynamic>) return inner;
  if (inner is Map) {
    try {
      return Map<String, dynamic>.from(inner);
    } catch (_) {
      return result;
    }
  }
  return result;
}
