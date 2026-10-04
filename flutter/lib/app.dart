import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_manager.dart';
import 'services/wallet_service.dart';
import 'services/network_service.dart';
import 'services/address_book_service.dart';
import 'services/polling_service.dart';
import 'services/tor_proxy_service.dart';
import 'services/local_web_server_service.dart';
import 'router/app_router.dart';

class OctopusWalletApp extends StatelessWidget {
  const OctopusWalletApp({super.key});

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
        ChangeNotifierProvider(create: (_) => LocalWebServerService.instance),
        // BackgroundPollingService uses singleton pattern - don't create via Provider
      ],
      child: Consumer<ThemeManager>(
        builder: (_, tm, __) {
          final router = AppRouter.router;
          return MaterialApp.router(
            title: 'Octopus Wallet',
            theme: AppTheme.fromPalette(tm.palette),
            routerConfig: router,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
