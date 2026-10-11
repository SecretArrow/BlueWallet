import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/services/recent_sites_service.dart';
import 'package:octopus_wallet/widgets/startpage_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StartpageView.resolveSearchUrl', () {
    test('bare domains gain https, queries become search URLs', () {
      expect(StartpageView.resolveSearchUrl('example.com'),
          'https://example.com');
      expect(StartpageView.resolveSearchUrl('https://example.com/a'),
          'https://example.com/a');
      expect(StartpageView.resolveSearchUrl('oct://abc/page'),
          'oct://abc/page');
      expect(
          StartpageView.resolveSearchUrl('octra wallet'),
          startsWith('https://duckduckgo.com/?q='));
      expect(StartpageView.resolveSearchUrl('  '), '');
    });
  });

  group('RecentSitesService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // Fresh singleton state between tests.
      await RecentSitesService.instance.clearAll();
    });

    test('upsert dedups + caps at 10, most-recent first', () async {
      final svc = RecentSitesService.instance;
      for (var i = 0; i < 12; i++) {
        await svc.record('https://site$i.example/page', title: 'S$i');
      }
      expect(svc.pages.length, RecentSitesService.maxEntries);
      expect(svc.pages.first.url, 'https://site11.example/page');
      // Revisit moves to front without duplicating.
      await svc.record('https://site5.example/page', title: 'S5-new');
      expect(svc.pages.length, RecentSitesService.maxEntries);
      expect(svc.pages.first.url, 'https://site5.example/page');
      expect(svc.pages.first.title, 'S5-new');
      expect(
          svc.pages
              .where((p) => p.url == 'https://site5.example/page')
              .length,
          1);
    });

    test('private mode skips recording; filtered URLs skipped', () async {
      final svc = RecentSitesService.instance;
      await svc.record('https://private.example/', private: true);
      await svc.record('about:blank');
      await svc.record('chrome-error://chromewebdata/');
      expect(svc.pages, isEmpty);
      await svc.record('https://ok.example/');
      expect(svc.pages.length, 1);
    });

    test('remove + clearAll', () async {
      final svc = RecentSitesService.instance;
      await svc.record('https://a.example/');
      await svc.record('https://b.example/');
      await svc.remove('https://a.example/');
      expect(svc.pages.length, 1);
      await svc.clearAll();
      expect(svc.pages, isEmpty);
    });
  });
}
