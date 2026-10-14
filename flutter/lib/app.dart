import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'router/app_router.dart';
import 'services/address_book_service.dart';
import 'services/deep_link_nav.dart';
import 'services/deep_link_router.dart';
import 'services/deep_link_service.dart';
import 'services/network_service.dart';
import 'services/polling_service.dart';
import 'services/tor_proxy_service.dart';
import 'services/wallet_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_manager.dart';

/// Root app widget: providers, theme, router, and deep-link wiring.
///
/// Deep links (`octra://` / `octra-wallet://`, forwarded by the native
/// MainActivity over the 'github.com.maragung.octopus_wallet/deeplink'
/// MethodChannel) are parsed by [DeepLinkRoute] and dispatched without
/// touching any BuildContext (static router + [DeepLinkNav] bus), so no
/// mounted-guard is needed:
/// - `octra://send?to=…&amount=…` → prefilled Send screen.
/// - `octra://<circleId>` → browser tab; the public `octra://` scheme is
///   translated to the internal `oct://` direct-render protocol the
///   browser speaks.
/// - `octra-wallet://…` → browser tab; external dApps carry their return
///   page in the `callback` param — loading it lets the dApp connect
///   through the regular window.octra bridge (no fake connect state).
class OctopusWalletApp extends StatefulWidget {
  const OctopusWalletApp({super.key});

  @override
  State<OctopusWalletApp> createState() => _OctopusWalletAppState();
}

class _OctopusWalletAppState extends State<OctopusWalletApp> {
  DeepLinkService? _deepLinks;

  @override
  void initState() {
    super.initState();
    // Register before the first frame so cold-start links (the native side
    // posts them as soon as the engine is configured) are not dropped.
    _deepLinks = DeepLinkService(onDeepLink: _handleDeepLink);
    // Pull the launch link in case the native push raced ahead of the Dart
    // handler registration (the native side serves it exactly once).
    unawaited(_deepLinks!.checkInitialLink());
  }

  @override
  void dispose() {
    _deepLinks?.dispose();
    super.dispose();
  }

  void _handleDeepLink(Uri uri) {
    final route = DeepLinkRoute.parse(uri.toString());
    if (route == null) {
      debugPrint('[DeepLink] unrecognized link ignored: $uri');
      return;
    }
    switch (route.type) {
      case DeepLinkRouteType.send:
        AppRouter.router.push('/send', extra: {
          'prefillTo': route.to,
          if (route.amount != null) 'prefillAmount': route.amount.toString(),
        });
        break;
      case DeepLinkRouteType.octPage:
        DeepLinkNav.instance.requestOpen(_toOctUrl(route.raw));
        break;
      case DeepLinkRouteType.walletConnect:
        DeepLinkNav.instance.requestOpen(_walletConnectTarget(route.raw));
        break;
    }
  }

  /// The browser renders circle pages over the internal `oct://`
  /// direct-RPC protocol; the public deep-link scheme is `octra://`.
  static String _toOctUrl(String raw) =>
      'oct://${raw.substring('octra://'.length)}';

  /// octra-wallet:// links from external dApps carry their return page in
  /// `callback`; loading it lets the dApp connect through the regular
  /// window.octra bridge. Links without a browsable callback are handed
  /// to the browser as-is (it explains what it cannot open).
  static String _walletConnectTarget(String raw) {
    final callback = Uri.tryParse(raw)?.queryParameters['callback'];
    if (callback != null &&
        (callback.startsWith('http://') ||
            callback.startsWith('https://'))) {
      return callback;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeManager()),
        ChangeNotifierProvider(create: (_) => WalletService()),
        ChangeNotifierProvider(create: (_) => NetworkService()),
        ChangeNotifierProvider(create: (_) => AddressBookService()),
        ChangeNotifierProvider(create: (_) => PollingService()),
        ChangeNotifierProvider(create: (_) => TorProxyService.instance),
      ],
      child: Consumer<ThemeManager>(
        builder: (_, tm, __) {
          final router = AppRouter.router;
          // Each MaterialApp slot gets its OWN palette-derived ThemeData.
          // `themeMode` (system/dark/light) then selects the slot via
          // MaterialApp's platform-brightness resolution — the two slots are
          // never the same object, so a stale platformBrightness read or a
          // mid-switch rebuild can never render the wrong brightness.
          // (ThemeManager.effectivePalette remains for previews/legacy use.)
          return MaterialApp.router(
            title: 'Octopus Wallet',
            theme: AppTheme.fromPalette(tm.lightPalette),
            darkTheme: AppTheme.fromPalette(tm.darkPalette),
            themeMode: tm.themeMode,
            routerConfig: router,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
