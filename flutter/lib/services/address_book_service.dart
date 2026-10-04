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
          .map((e) => AddressEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _entries = list;
    } catch (_) {
      _entries = [];
    }
    notifyListeners();
  }

  Future<void> add(AddressEntry entry) async {
    _entries.add(entry);
    await _save();
    notifyListeners();
  }

  Future<void> update(AddressEntry entry) async {
    final idx = _entries.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      _entries[idx] = entry;
      await _save();
      notifyListeners();
    }
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
