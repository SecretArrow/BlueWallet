import 'package:flutter_test/flutter_test.dart';
import 'package:octopus_wallet/models/address_entry.dart';
import 'package:octopus_wallet/services/address_book_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Defensive tests for the address book. Pure helpers run directly;
/// service paths use mocked SharedPreferences + settle like network tests.
void main() {
  group('AddressEntry.tryFromJson', () {
    test('parses valid rows', () {
      final e = AddressEntry.tryFromJson(
          {'id': '1', 'label': 'L', 'address': 'octA'});
      expect(e, isNotNull);
      expect(e!.address, 'octA');
    });

    test('skips garbage rows', () {
      expect(AddressEntry.tryFromJson(null), isNull);
      expect(AddressEntry.tryFromJson('nope'), isNull);
      expect(AddressEntry.tryFromJson({}), isNull);
      expect(AddressEntry.tryFromJson({'id': '1', 'label': 'L'}), isNull);
      expect(
          AddressEntry.tryFromJson({'id': '1', 'label': 'L', 'address': '   '}),
          isNull);
      expect(
          AddressEntry.tryFromJson({'id': '1', 'label': 'L', 'address': 123}),
          isNull);
    });
  });

  group('AddressBookService', () {
    Future<AddressBookService> freshService() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final s = AddressBookService();
      await Future.delayed(const Duration(milliseconds: 100));
      return s;
    }

    test('add validates, trims and dedupes', () async {
      final s = await freshService();
      await expectLater(
          s.add(const AddressEntry(id: 'x', label: 'L', address: '  ')),
          throwsArgumentError);
      final a = await s.add(
          const AddressEntry(id: 'a', label: '  Alice  ', address: '  octA  '));
      expect(a.label, 'Alice');
      expect(a.address, 'octA');
      final b = await s
          .add(const AddressEntry(id: 'b', label: 'Alice2', address: 'OCTA'));
      expect(b.id, 'a', reason: 'duplicate returns existing');
      expect(s.entries.length, 1);
    });

    test('update validates and reports missing', () async {
      final s = await freshService();
      await s.add(const AddressEntry(id: 'a', label: 'A', address: 'octA'));
      expect(
          await s.update(
              const AddressEntry(id: 'a', label: 'A2', address: 'octA')),
          isTrue);
      expect(
          await s.update(
              const AddressEntry(id: 'zz', label: 'Z', address: 'octZ')),
          isFalse);
      await expectLater(
          s.update(const AddressEntry(id: 'a', label: 'A', address: '')),
          throwsArgumentError);
    });
  });
}
