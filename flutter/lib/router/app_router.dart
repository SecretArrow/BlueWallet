import 'package:go_router/go_router.dart';
import '../screens/setup/setup_screen.dart';
import '../screens/auth/startup_screen.dart';
import '../screens/auth/pin_entry_screen.dart';
import '../screens/auth/session_lock_screen.dart';
import '../screens/main/main_screen.dart';
import '../screens/send/send_menu_screen.dart';
import '../screens/send/send_screen.dart';
import '../screens/send/token_transfer_screen.dart';
import '../screens/receive/receive_screen.dart';
import '../screens/wallets/wallets_screen.dart';
import '../screens/wallets/add_wallet_screen.dart';
import '../screens/wallets/view_keys_screen.dart';
import '../screens/wallets/export_wallet_screen.dart';
import '../screens/wallets/tx_progress_screen.dart';
import '../screens/wallets/mnemonic_wallet_screen.dart';
import '../screens/wallets/derive_child_wallet_screen.dart';
import '../screens/settings/about_screen.dart';
import '../screens/settings/network_settings_screen.dart';
import '../screens/settings/theme_palette_screen.dart';
import '../screens/settings/change_pin_screen.dart';
import '../screens/settings/address_book_screen.dart';
import '../screens/settings/address_book_entry_screen.dart';
import '../screens/settings/biometric_settings_screen.dart';
import '../screens/settings/dapp_origins_screen.dart';
import '../screens/dapp/dapp_browser_screen.dart';
import '../screens/settings/permissions_center_screen.dart';
import '../screens/stealth/stealth_send_screen.dart';
import '../screens/stealth/stealth_tasks_screen.dart';
import '../screens/stealth/stealth_task_detail_screen.dart';
import '../screens/stealth/stealth_scan_screen.dart';
import '../screens/scan/qr_scan_screen.dart';
import '../screens/scan/auto_scan_screen.dart';
import '../screens/transactions/transactions_manager_screen.dart';
import '../screens/transactions/history_detail_screen.dart';
import '../screens/balance/encrypt_balance_screen.dart';
import '../screens/balance/decrypt_balance_screen.dart';
import '../screens/confirm/confirm_action_screen.dart';
import '../screens/devtools/dev_tools_screen.dart';
import '../screens/devtools/dev_deploy_screen.dart';
import '../screens/devtools/dev_call_screen.dart';
import '../screens/devtools/dev_view_screen.dart';
import '../screens/devtools/dev_info_screen.dart';
import '../screens/devtools/dev_receipt_screen.dart';
import '../screens/devtools/dev_verify_screen.dart';
import '../screens/devtools/dev_storage_screen.dart';
import '../screens/devtools/dev_compute_addr_screen.dart';
import '../screens/settings/polling_settings_screen.dart';
import '../screens/settings/data_usage_screen.dart';
import '../screens/settings/tor_proxy_settings_screen.dart';
import '../screens/confirm/confirm_contract_call_screen.dart';
import '../screens/settings/local_web_server_settings_screen.dart';
import '../models/tx_record.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const StartupScreen()),
      GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),
      GoRoute(
        path: '/pin',
        builder: (_, state) => PinEntryScreen(
          mode: state.uri.queryParameters['mode'] ?? 'unlock',
        ),
      ),
      GoRoute(path: '/home', builder: (_, __) => const MainScreen()),
      GoRoute(path: '/send-menu', builder: (_, __) => const SendMenuScreen()),
      GoRoute(
        path: '/send',
        builder: (_, state) => SendScreen(
          prefillAddress: state.uri.queryParameters['to'],
        ),
      ),
      GoRoute(path: '/receive', builder: (_, __) => const ReceiveScreen()),
      GoRoute(path: '/wallets', builder: (_, __) => const WalletsScreen()),
      GoRoute(path: '/add-wallet', builder: (_, __) => const AddWalletScreen()),
      GoRoute(
          path: '/mnemonic-wallet',
          builder: (_, __) => const MnemonicWalletScreen()),
      GoRoute(
        path: '/derive-child-wallet',
        builder: (_, state) => DeriveChildWalletScreen(
          parentId:
              (state.extra as String?) ?? state.uri.queryParameters['id'] ?? '',
        ),
      ),
      GoRoute(
          path: '/view-keys',
          builder: (_, state) => ViewKeysScreen(
                walletId: state.uri.queryParameters['id'],
              )),
      GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
      GoRoute(
        path: '/network-settings',
        builder: (_, __) => const NetworkSettingsScreen(),
      ),
      GoRoute(
        path: '/theme-palette',
        builder: (_, __) => const ThemePaletteScreen(),
      ),
      GoRoute(path: '/change-pin', builder: (_, __) => const ChangePinScreen()),
      GoRoute(
        path: '/biometric-settings',
        builder: (_, __) => const BiometricSettingsScreen(),
      ),
      GoRoute(
        path: '/address-book',
        builder: (_, __) => const AddressBookScreen(),
      ),
      GoRoute(
        path: '/address-book-entry',
        builder: (_, state) => AddressBookEntryScreen(
          editId: state.uri.queryParameters['id'],
        ),
      ),
      GoRoute(
        path: '/dapp-origins',
        builder: (_, __) => const DappOriginsScreen(),
      ),
      GoRoute(
        path: '/dapp-browser',
        builder: (_, state) => DappBrowserScreen(
          initialUrl: state.uri.queryParameters['url'],
        ),
      ),
      GoRoute(
        path: '/permissions-center',
        builder: (_, __) => const PermissionsCenterScreen(),
      ),
      GoRoute(
        path: '/stealth-send',
        builder: (_, __) => const StealthSendScreen(),
      ),
      GoRoute(
        path: '/stealth-tasks',
        builder: (_, __) => const StealthTasksScreen(),
      ),
      GoRoute(
        path: '/stealth-task-detail',
        builder: (_, state) => StealthTaskDetailScreen(
          taskId: state.uri.queryParameters['id'] ?? '',
        ),
      ),
      GoRoute(
          path: '/stealth-scan', builder: (_, __) => const StealthScanScreen()),
      GoRoute(path: '/qr-scan', builder: (_, __) => const QrScanScreen()),
      GoRoute(path: '/auto-scan', builder: (_, __) => const AutoScanScreen()),
      GoRoute(
        path: '/tx-manager',
        builder: (_, __) => const TransactionsManagerScreen(),
      ),
      GoRoute(
        path: '/polling-settings',
        builder: (_, __) => const PollingSettingsScreen(),
      ),
      GoRoute(
        path: '/tx-detail',
        builder: (_, state) => HistoryDetailScreen(
          tx: state.extra as TxRecord?,
        ),
      ),
      GoRoute(
        path: '/encrypt-balance',
        builder: (_, __) => const EncryptBalanceScreen(),
      ),
      GoRoute(
        path: '/decrypt-balance',
        builder: (_, __) => const DecryptBalanceScreen(),
      ),
      GoRoute(
        path: '/confirm-action',
        builder: (_, state) => ConfirmActionScreen(
          data: (state.extra as Map<String, dynamic>?) ?? {},
        ),
      ),
      GoRoute(
          path: '/export-wallet',
          builder: (_, state) => ExportWalletScreen(
                walletId: state.uri.queryParameters['id'],
              )),
      GoRoute(
          path: '/session-lock', builder: (_, __) => const SessionLockScreen()),
      GoRoute(
        path: '/tx-progress',
        builder: (_, state) => TxProgressScreen(
          txData: state.extra as Map<String, dynamic>?,
        ),
      ),
      GoRoute(
          path: '/token-transfer',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return TokenTransferScreen(
              initialTokenAddress: extra?['tokenAddress']?.toString(),
              initialTokenSymbol: extra?['tokenSymbol']?.toString(),
            );
          }),
      // Dev tools (desktop only — guarded in DevToolsScreen)
      GoRoute(path: '/dev-tools', builder: (_, __) => const DevToolsScreen()),
      GoRoute(path: '/dev-deploy', builder: (_, __) => const DevDeployScreen()),
      GoRoute(path: '/dev-call', builder: (_, __) => const DevCallScreen()),
      GoRoute(path: '/dev-view', builder: (_, __) => const DevViewScreen()),
      GoRoute(path: '/dev-info', builder: (_, __) => const DevInfoScreen()),
      GoRoute(
          path: '/dev-receipt', builder: (_, __) => const DevReceiptScreen()),
      GoRoute(path: '/dev-verify', builder: (_, __) => const DevVerifyScreen()),
      GoRoute(
          path: '/dev-storage', builder: (_, __) => const DevStorageScreen()),
      GoRoute(
          path: '/dev-compute-addr',
          builder: (_, __) => const DevComputeAddrScreen()),
      GoRoute(path: '/data-usage', builder: (_, __) => const DataUsageScreen()),
      GoRoute(
        path: '/tor-proxy',
        builder: (_, __) => const TorProxySettingsScreen(),
      ),
      GoRoute(
        path: '/confirm-contract-call',
        builder: (_, state) => ConfirmContractCallScreen(
          requestId: state.uri.queryParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: '/local-web-server-settings',
        builder: (_, __) => const LocalWebServerSettingsScreen(),
      ),
    ],
  );
}
