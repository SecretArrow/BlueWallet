import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/address_entry.dart';

const _kAddressBookKey = 'address_book';

class AddressBookService extends ChangeNotifier {
  List<AddressEntry> _entries = [];

  List<AddressEntry> get entries => List.unmodifiable(_entries);

  AddressBookService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAddressBookKey) ?? '[]';
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map(AddressEntry.tryFromJson)
          .whereType<AddressEntry>()
          .toList();
      _entries = list;
    } catch (_) {
      _entries = [];
    }
    notifyListeners();
  }

  /// Adds an entry after validating; returns the existing entry when the
  /// address is already saved (mirrors Android dedup). Throws
  /// [ArgumentError] on blank address. Blank labels are allowed (UIs
  /// substitute a shortened address, mirroring Android).
  Future<AddressEntry> add(AddressEntry entry) async {
    if (entry.address.trim().isEmpty) {
      throw ArgumentError('Address must not be blank');
    }
    for (final e in _entries) {
      if (e.address.toLowerCase() == entry.address.trim().toLowerCase()) {
        return e;
      }
    }
    final clean = AddressEntry(
        id: entry.id, label: entry.label.trim(), address: entry.address.trim());
    _entries.add(clean);
    await _save();
    notifyListeners();
    return clean;
  }

  /// Updates an entry; returns false when the id is unknown.
  Future<bool> update(AddressEntry entry) async {
    if (entry.address.trim().isEmpty) {
      throw ArgumentError('Address must not be blank');
    }
    final idx = _entries.indexWhere((e) => e.id == entry.id);
    if (idx < 0) return false;
    _entries[idx] = entry;
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> remove(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_kAddressBookKey, raw);
  }
}
