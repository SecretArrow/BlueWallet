/// Pure oct address format validation.
///
/// Mirrors the canonical rule already enforced by the Android send screens
/// (`SendActivity`, `StealthSendActivity`, `AddressBookActivity`): an Octra
/// address is exactly 47 characters and starts with `oct`. Pure Dart, no
/// Flutter, no network — fully unit-testable.
class OctAddress {
  /// Total length of a well-formed Octra address (e.g.
  /// `oct5ZPf49ZYNnA1hopXe9EcDbiBPhgwJyudxLaLhHefEmFt`).
  static const int expectedLength = 47;

  static const String prefix = 'oct';

  OctAddress._();

  /// True when [address] is a well-formed Octra address:
  /// non-null, trimmed-equal, `oct` prefix, exact length.
  static bool isValid(String? address) {
    if (address == null) return false;
    final a = address.trim();
    if (a.length != expectedLength) return false;
    return a.startsWith(prefix);
  }
}
