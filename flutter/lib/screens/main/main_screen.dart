import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/settings_tab.dart';

/// Main host screen with adaptive navigation:
/// - Mobile: bottom NavigationBar
/// - Desktop: side NavigationRail
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tabIndex = 0;

  /// True once the initial data load has been successfully dispatched
  /// (i.e. after wallets are loaded and activeWallet != null).
  bool _refreshDone = false;

  bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // WalletService._init() is async: wallets may not be loaded yet when
    // the screen first mounts. We subscribe via context.watch (in build) so
    // this method fires on every notifyListeners(), and delay the initial
    // data load until activeWallet is actually available.
    if (!_refreshDone) {
      final ws = context.read<WalletService>();
      if (ws.activeWallet != null) {
        _refreshDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refresh();
        });
      }
    }
  }

  Future<void> _refresh() async {
    final ws = context.read<WalletService>();
    final ns = context.read<NetworkService>();
    await ws.refresh(ns.activeNodeUrl);
    if (mounted) await ws.loadHistory(ns.activeNodeUrl);
    if (mounted) await ws.fetchTokens(ns.activeNodeUrl);
    // Restore auto-scan from saved settings (no-op if already running)
    if (mounted) await ws.restoreAutoScan(ns.activeNodeUrl);
  }

  static const _tabs = [
    DashboardTab(),
    HistoryTab(),
    SettingsTab(),
  ];

  static const _navItems = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard_rounded),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history_rounded),
      label: 'History',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
  ];

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard_rounded),
      label: Text('Dashboard'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history_rounded),
      label: Text('History'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: Text('Settings'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Establish a dependency on WalletService so that didChangeDependencies()
    // is called again when _init() completes and notifyListeners() fires.
    // This is required to handle the async wallet-load race condition.
    context.watch<WalletService>();

    return PopScope(
      // canPop=false means we intercept all back presses.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_tabIndex != 0) {
          // Not on Dashboard → go back to Dashboard tab.
          setState(() => _tabIndex = 0);
          return;
        }
        // On Dashboard → confirm exit.
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit'),
            content: const Text('Exit Octra Wallet?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        if (shouldExit == true && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Theme.of(context).brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
          systemNavigationBarIconBrightness:
              Theme.of(context).brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
        ),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Octra Wallet'),
            centerTitle: true,
            automaticallyImplyLeading: false,
            actions: [
              // Refresh button — always visible, essential on desktop
              // where pull-to-refresh doesn't work with a mouse
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _refresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: _isDesktop
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _tabIndex,
                      onDestinationSelected: (i) =>
                          setState(() => _tabIndex = i),
                      labelType: NavigationRailLabelType.all,
                      destinations: _railDestinations,
                    ),
                    const VerticalDivider(thickness: 1, width: 1),
                    Expanded(
                      child: IndexedStack(index: _tabIndex, children: _tabs),
                    ),
                  ],
                )
              : IndexedStack(index: _tabIndex, children: _tabs),
          bottomNavigationBar: _isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (i) => setState(() => _tabIndex = i),
                  destinations: _navItems,
                ),
        ),
      ),
    );
  }
}
