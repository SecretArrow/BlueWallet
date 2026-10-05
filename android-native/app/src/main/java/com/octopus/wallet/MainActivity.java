package com.octopus.wallet;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.app.Activity;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.WindowManager;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.LayoutInflater;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.PopupMenu;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.ImageView;
import android.widget.Toast;
import android.view.ViewGroup;

import androidx.appcompat.app.AppCompatActivity;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

import com.google.android.material.bottomnavigation.BottomNavigationView;
import com.google.android.material.floatingactionbutton.FloatingActionButton;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public class MainActivity extends AppCompatActivity {

    private static final String EXTRA_TX_HASH = "tx_hash";
    private static final String EXTRA_TX_TO = "tx_to";
    private static final String EXTRA_TX_AMOUNT_RAW = "tx_amount_raw";
    private static final String EXTRA_TX_STATUS = "tx_status";
    private static final String EXTRA_TX_TOKEN_SYMBOL = "tx_token_symbol";
    private static final String EXTRA_TX_TYPE = "tx_type";
    private static final String PREFS_TX_CACHE = "tx_cache";
    private static final String KEY_TX_CACHE_PREFIX = "history_";

    private final ExecutorService executor = Executors.newFixedThreadPool(3);
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    /** Returns the application-scoped {@link WalletRepository}. Use for all network access. */
    private WalletRepository repo() {
        return ((OctraWalletApplication) getApplication()).getRepository();
    }

    private SwipeRefreshLayout dashboardRefresh;
    private SwipeRefreshLayout historyRefresh;
    private BottomNavigationView bottomNavigation;

    private LinearLayout historyView;
    private View settingsView;

    private Spinner walletSelector;
    private EditText tokenSearchInput;

    private TextView addressText;
    private TextView totalBalanceText;
    private TextView publicBalanceText;
    private TextView encryptedBalanceText;
    private TextView historyEmptyText;

    private RecyclerView tokenListView;
    private RecyclerView historyListView;
    private RecyclerView settingsActionsListView;
    private FloatingActionButton historyScrollTopFab;

    private final ActivityResultLauncher<Intent> txActivityLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() != Activity.RESULT_OK || result.getData() == null) {
                    return;
                }
                handleSubmittedTxResult(result.getData());
            });

    private final ActivityResultLauncher<String> notificationPermissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestPermission(), granted -> {
                // no-op; permission result handled automatically
            });

    private final ActivityResultLauncher<Intent> settingsActivityLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() != Activity.RESULT_OK || result.getData() == null) {
                    return;
                }
                Intent data = result.getData();
                if (data.getBooleanExtra("theme_changed", false)) {
                    recreate();
                    return;
                }
                if (data.getBooleanExtra("settings_changed", false)) {
                    loadWalletInfo();
                    return;
                }
                if (data.getBooleanExtra("wallet_added", false)) {
                    refreshWalletProfiles();
                    loadWalletInfo();
                }
            });

    private final ActivityResultLauncher<Intent> confirmLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() != Activity.RESULT_OK) {
                    return;
                }
                OctraNative.getInstance().lockWallet();
                PinStore.clear(this);
                startActivity(new Intent(this, UnlockActivity.class));
                finish();
            });

    private final List<String> walletIds = new ArrayList<>();
    private final List<JSONObject> historyItems = new ArrayList<>();
    private final List<JSONObject> pendingHistoryItems = new ArrayList<>();
    private final List<TokenRow> tokenItems = new ArrayList<>();
    private HistoryListAdapter historyListAdapter;

    private boolean isWalletSelectorBinding = false;
    private boolean isBottomNavBinding = false;
    private boolean historyLoadingMore = false;
    private boolean historyHasMore = true;
    private int historyOffset = 0;
    private static final int HISTORY_PAGE_SIZE = 20;

    private String activeWalletId;
    private String walletAddress;
    private String rpcUrl;
    private int currentNonce = 0;
    private long latestPublicRaw = 0L;
    private long latestEncryptedRaw = 0L;
    private boolean latestSnapshotReady = false;
    private String appliedThemeKey;
    private boolean switchingWalletInApp = false;

    /** Repository used for Room-based history caching. */
    private WalletRepository walletRepository;

    // Pending deep-link params parsed before wallet is ready
    private String deepLinkTo;
    private String deepLinkAmount;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(resolveThemeRes());
        super.onCreate(savedInstanceState);
        // Prevent screenshots and app-switcher thumbnails
        getWindow().setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE);
        setContentView(R.layout.activity_main);
        walletRepository = new WalletRepository(this);
        initViews();
        handleDeepLinkIntent(getIntent());
        checkWalletStatus();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleDeepLinkIntent(intent);
    }

    /**
     * Handles octra://send?to=xxx&amount=yyy deep-links.
     * If the wallet is already loaded the Send screen opens immediately;
     * otherwise the parameters are saved and opened after wallet init.
     */
    private void handleDeepLinkIntent(Intent intent) {
        if (intent == null) return;
        Uri data = intent.getData();
        if (data == null) return;
        if (!"octra".equals(data.getScheme())) return;
        if ("send".equals(data.getHost())) {
            String to     = data.getQueryParameter("to");
            String amount = data.getQueryParameter("amount");
            if (to != null && !to.trim().isEmpty()) {
                if (walletAddress != null && !walletAddress.isEmpty()) {
                    openSendWithParams(to.trim(), amount);
                } else {
                    deepLinkTo     = to.trim();
                    deepLinkAmount = amount;
                }
            }
        }
    }

    private void openSendWithParams(String to, String amount) {
        Intent sendIntent = new Intent(this, SendActivity.class);
        sendIntent.putExtra(SendActivity.EXTRA_PREFILL_TO, to);
        if (amount != null && !amount.trim().isEmpty()) {
            sendIntent.putExtra(SendActivity.EXTRA_PREFILL_AMOUNT, amount.trim());
        }
        txActivityLauncher.launch(sendIntent);
        // Clear so it doesn't reopen on resume
        deepLinkTo     = null;
        deepLinkAmount = null;
    }

    private int resolveThemeRes() {
        return ThemeManager.resolveThemeRes(this);
    }

    private void initViews() {
        dashboardRefresh = findViewById(R.id.dashboard_refresh);
        historyRefresh = findViewById(R.id.history_refresh);
        bottomNavigation = findViewById(R.id.bottom_navigation);

        historyView = findViewById(R.id.history_view);
        settingsView = findViewById(R.id.settings_view);

        walletSelector = findViewById(R.id.wallet_selector);
        tokenSearchInput = findViewById(R.id.token_search_input);

        addressText = findViewById(R.id.address_text);
        totalBalanceText = findViewById(R.id.total_balance_text);
        publicBalanceText = findViewById(R.id.public_balance_text);
        encryptedBalanceText = findViewById(R.id.encrypted_balance_text);
        historyEmptyText = findViewById(R.id.history_empty_text);

        tokenListView = findViewById(R.id.token_list_view);
        historyListView = findViewById(R.id.history_list_view);
        settingsActionsListView = findViewById(R.id.settings_actions_list);
        historyScrollTopFab = findViewById(R.id.history_scroll_top_fab);

        tokenListView.setLayoutManager(new LinearLayoutManager(this));
        historyListView.setLayoutManager(new LinearLayoutManager(this));
        settingsActionsListView.setLayoutManager(new LinearLayoutManager(this));

        findViewById(R.id.dashboard_send_button).setOnClickListener(v -> showSendMenu());
        findViewById(R.id.dashboard_receive_button).setOnClickListener(v -> openReceive());

        setupWalletSelector();
        setupBottomNavigation();
        setupHistoryList();
        setupTokenSearch();
        setupSettingsActionsList();
        setupInsets();

        // Pull-to-refresh on the dashboard tab refreshes ONLY balance + token list.
        // Transaction history has its own separate SwipeRefreshLayout (historyRefresh).
        dashboardRefresh.setOnRefreshListener(() -> refreshBalance(true));
        appliedThemeKey = ThemeManager.getCurrentTheme(this);

        // Request notification permission proactively on Android 13+
        requestNotificationPermissionIfNeeded();

        // About/version display moved to AboutActivity; no local view here.
        showMainSection(R.id.nav_dashboard);
    }

    private void requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                notificationPermissionLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS);
            }
        }
    }

    private void setupInsets() {
        View topBar = findViewById(R.id.top_app_bar);
        View bottomBar = findViewById(R.id.bottom_navigation);
        final int topBaseLeft = topBar.getPaddingLeft();
        final int topBaseTop = topBar.getPaddingTop();
        final int topBaseRight = topBar.getPaddingRight();
        final int topBaseBottom = topBar.getPaddingBottom();
        final int bottomBaseLeft = bottomBar.getPaddingLeft();
        final int bottomBaseTop = bottomBar.getPaddingTop();
        final int bottomBaseRight = bottomBar.getPaddingRight();
        final int bottomBaseBottom = bottomBar.getPaddingBottom();
        final int bottomExtraPx = (int) (8 * getResources().getDisplayMetrics().density);
        ViewCompat.setOnApplyWindowInsetsListener(topBar, (view, insets) -> {
            int top = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top;
            view.setPadding(topBaseLeft, topBaseTop + top, topBaseRight, topBaseBottom);
            return insets;
        });
        ViewCompat.setOnApplyWindowInsetsListener(bottomBar, (view, insets) -> {
            int bottom = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom;
            view.setPadding(bottomBaseLeft, bottomBaseTop, bottomBaseRight, bottomBaseBottom + bottom + bottomExtraPx);
            return insets;
        });
        ViewCompat.requestApplyInsets(topBar);
        ViewCompat.requestApplyInsets(bottomBar);
    }

    private void setupBottomNavigation() {
        bottomNavigation.setOnItemSelectedListener(item -> {
            if (isBottomNavBinding) {
                return true;
            }
            showMainSection(item.getItemId());
            return true;
        });
    }

    private void showMainSection(int navId) {
        dashboardRefresh.setEnabled(false);
        dashboardRefresh.setVisibility(View.GONE);
        historyView.setVisibility(View.GONE);
        settingsView.setVisibility(View.GONE);

        if (navId == R.id.nav_dashboard) {
            dashboardRefresh.setEnabled(true);
            dashboardRefresh.setVisibility(View.VISIBLE);
        } else if (navId == R.id.nav_history) {
            historyView.setVisibility(View.VISIBLE);
            updateHistoryScrollTopFabVisibility();
        } else {
            settingsView.setVisibility(View.VISIBLE);
        }

        if (navId != R.id.nav_history && historyScrollTopFab != null) {
            historyScrollTopFab.setVisibility(View.GONE);
        }

        isBottomNavBinding = true;
        bottomNavigation.setSelectedItemId(navId);
        isBottomNavBinding = false;
    }

    private void setupWalletSelector() {
        refreshWalletProfiles();
        walletSelector.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                if (isWalletSelectorBinding || position < 0 || position >= walletIds.size()) {
                    return;
                }
                String selected = walletIds.get(position);
                if (!selected.equals(activeWalletId)) {
                    switchWallet(selected);
                }
            }

            @Override
            public void onNothingSelected(AdapterView<?> parent) {
            }
        });
    }

    private void refreshWalletProfiles() {
        WalletProfileStore.ensureDefault(this);
        walletIds.clear();
        walletIds.addAll(WalletProfileStore.getWalletIds(this));
        activeWalletId = WalletProfileStore.getSelectedWalletId(this);

        ArrayAdapter<String> adapter = new ArrayAdapter<>(this, R.layout.spinner_item_wallet, walletIds);
        adapter.setDropDownViewResource(R.layout.spinner_item_wallet_dropdown);
        walletSelector.setAdapter(adapter);

        int selectedIndex = walletIds.indexOf(activeWalletId);
        if (selectedIndex < 0) {
            selectedIndex = 0;
        }
        isWalletSelectorBinding = true;
        walletSelector.setSelection(selectedIndex);
        isWalletSelectorBinding = false;
    }

    private void switchWallet(String walletId) {
        WalletProfileStore.setSelectedWalletId(this, walletId);
        activeWalletId = walletId;
        switchingWalletInApp = true;

        OctraNative.getInstance().lockWallet();
        File walletDir = WalletProfileStore.getWalletDir(this, walletId);
        OctraNative.getInstance().init(walletDir.getAbsolutePath());

        refreshWalletProfiles();
        checkWalletStatus();
    }

    private boolean tryAutoUnlockWithDefaultPin() {
        String pin = PinStore.getDefaultPin(this);
        if (!pin.matches("\\d{6}")) {
            return false;
        }
        try {
            String result = OctraNative.getInstance().unlockWallet(pin);
            JSONObject json = new JSONObject(result);
            return !json.has("error");
        } catch (Exception e) {
            return false;
        }
    }

    private void checkWalletStatus() {
        OctraNative native_ = OctraNative.getInstance();
        if (!native_.isWalletLoaded()) {
            if (native_.hasEncryptedWallet()) {
                if (switchingWalletInApp
                        && !SessionLockActivity.isSessionExpired(this)
                        && tryAutoUnlockWithDefaultPin()) {
                    switchingWalletInApp = false;
                    loadWalletInfo();
                    return;
                }
                switchingWalletInApp = false;
                startActivity(new Intent(this, UnlockActivity.class));
            } else {
                switchingWalletInApp = false;
                startActivity(new Intent(this, SetupActivity.class));
            }
            finish();
            return;
        }
        switchingWalletInApp = false;
        loadWalletInfo();
    }

    private void loadWalletInfo() {
        // Dispatch pending deep-link if any
        if (deepLinkTo != null && !deepLinkTo.isEmpty()) {
            String to     = deepLinkTo;
            String amount = deepLinkAmount;
            deepLinkTo     = null;
            deepLinkAmount = null;
            mainHandler.postDelayed(() -> openSendWithParams(to, amount), 300);
        }
        try {
            String infoJson = OctraNative.getInstance().getWalletInfo();
            JSONObject info = new JSONObject(infoJson);
            if (info.has("error")) {
                showError(info.getString("error"));
                return;
            }

            walletAddress = info.getString("address");
            String rpcValue = info.optString("rpc_url", "http://165.227.225.79:8080");
            String explorerValue = info.optString("explorer_url", "https://devnet.octrascan.io");
            rpcUrl = rpcValue;
            WalletAddressStore.putAddress(getApplicationContext(), activeWalletId, walletAddress);

            addressText.setText(walletAddress);
            NodeProfileStore.ensureDefault(this, rpcValue, explorerValue);
            renderCachedHistoryIfAny();
            renderCachedTokenSnapshotIfAny();
            refreshDashboardData();
        } catch (Exception e) {
            showError("Failed to load wallet info");
        }
    }

    private void refreshDashboardData() {
        refreshDashboardData(true);
    }

    private void refreshDashboardData(boolean showIndicator) {
        if (showIndicator) {
            dashboardRefresh.setRefreshing(true);
        }
        refreshBalance(showIndicator);
        refreshHistory();
    }

    private void refreshBalance() {
        refreshBalance(true);
    }

    private void refreshBalance(boolean showIndicator) {
        if (walletAddress == null || rpcUrl == null) {
            if (showIndicator) mainHandler.post(() -> dashboardRefresh.setRefreshing(false));
            return;
        }

        // Tracks the two parallel tasks; spinner stops only when both complete (or fail).
        final AtomicInteger pendingTasks = new AtomicInteger(2);
        final Runnable stopSpinnerWhenDone = () -> {
            if (!showIndicator) return;
            if (pendingTasks.decrementAndGet() == 0) {
                mainHandler.post(() -> {
                    if (!isFinishing() && !isDestroyed()) {
                        dashboardRefresh.setRefreshing(false);
                    }
                });
            }
        };

        // Task 1: Fetch native balance (parallel)
        executor.execute(() -> {
            try {
                WalletRepository.Result<WalletRepository.BalanceSummary> balResult =
                        repo().fetchBalance(rpcUrl, walletAddress);
                if (!balResult.isSuccess()) {
                    return; // finally will call stopSpinnerWhenDone
                }
                WalletRepository.BalanceSummary summary = balResult.getValue();
                currentNonce = summary.nonce;

                long publicRaw = summary.publicRaw;
                long encRaw    = summary.encryptedRaw;
                String balanceRaw       = String.valueOf(publicRaw);
                String encryptedRawText = String.valueOf(encRaw);

                final long encryptedRawFinal = Math.max(encRaw, 0L);
                long totalRaw = publicRaw + encryptedRawFinal;

                List<TokenRow> nativeTokens = new ArrayList<>();
                nativeTokens.add(new TokenRow("OCT", "Octra Native Token", "Public",    balanceRaw,       formatTokenAmount(balanceRaw), false));
                nativeTokens.add(new TokenRow("OCT", "Octra Native Token", "Encrypted", encryptedRawText, formatTokenAmount(encryptedRawText), true));

                mainHandler.post(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    latestPublicRaw    = publicRaw;
                    latestEncryptedRaw = encryptedRawFinal;
                    latestSnapshotReady = true;
                    totalBalanceText.setText(formatAmount(String.valueOf(totalRaw)) + " OCT");
                    if (publicBalanceText != null) {
                        publicBalanceText.setText("Public: " + formatAmount(String.valueOf(publicRaw)) + " OCT");
                    }
                    if (encryptedBalanceText != null) {
                        encryptedBalanceText.setText("Encrypted: " + formatAmount(String.valueOf(encryptedRawFinal)) + " OCT");
                    }
                    // Replace only native token rows; preserve contract tokens
                    List<TokenRow> contractTokensCopy = new ArrayList<>();
                    for (TokenRow r : tokenItems) {
                        if ("Token".equals(r.balanceType)) contractTokensCopy.add(r);
                    }
                    tokenItems.clear();
                    tokenItems.addAll(nativeTokens);
                    tokenItems.addAll(contractTokensCopy);
                    applyTokenFilter(tokenSearchInput.getText() == null ? "" : tokenSearchInput.getText().toString());
                    persistTokenSnapshotToDbAsync();
                });
            } catch (Exception ignored) {
                // Fetch failure handled by finally
            } finally {
                stopSpinnerWhenDone.run();
            }
        });

        // Task 2: Fetch contract tokens (parallel, independent)
        executor.execute(() -> {
            try {
                List<TokenRow> contractTokens = fetchContractTokens();
                mainHandler.post(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    // Replace only contract token rows; preserve native tokens
                    List<TokenRow> nativeTokensCopy = new ArrayList<>();
                    for (TokenRow r : tokenItems) {
                        if (!"Token".equals(r.balanceType)) nativeTokensCopy.add(r);
                    }
                    tokenItems.clear();
                    tokenItems.addAll(nativeTokensCopy);
                    tokenItems.addAll(contractTokens);
                    applyTokenFilter(tokenSearchInput.getText() == null ? "" : tokenSearchInput.getText().toString());
                    if (latestSnapshotReady) persistTokenSnapshotToDbAsync();
                });
            } catch (Exception ignored) {
                // Contract token fetching is optional; failure handled by finally
            } finally {
                stopSpinnerWhenDone.run();
            }
        });
    }

    /**
     * Fetches token data for all deployed contracts in parallel.
     *
     * <p>For each contract: check symbol → balance → name + decimals.
     * Contracts without a symbol or with zero balance are skipped.
     * Uses a fixed thread pool (8 threads) so that all ~159 contracts
     * are probed concurrently instead of sequentially (O(N×4) → O(ceil(N/8)×4)).</p>
     */
    private List<TokenRow> fetchContractTokens() throws Exception {
        // Fast path (webcli GET /api/tokens parity): try the dedicated
        // octra_tokensByAddress index first — single RPC instead of probing
        // every deployed contract. Falls through to listContracts probing below.
        try {
            JSONArray fast = repo().fetchTokensFast(rpcUrl, walletAddress);
            if (fast != null && fast.length() > 0) {
                List<TokenRow> out = new ArrayList<>(fast.length());
                for (int i = 0; i < fast.length(); i++) {
                    JSONObject t = fast.optJSONObject(i);
                    if (t == null) continue;
                    String addr = t.optString("address", "");
                    String symbol = t.optString("symbol", "");
                    if (addr.isEmpty() || symbol.isEmpty() || "0".equals(symbol)) continue;
                    String balance = t.optString("balance", "0");
                    if (balance.isEmpty() || "0".equals(balance)) continue;
                    String name = t.optString("name", symbol);
                    int decimals = 0;
                    try { decimals = Integer.parseInt(t.optString("decimals", "0")); }
                    catch (Exception ignored) {}
                    String formatted = formatTokenWithDecimals(balance, decimals);
                    out.add(new TokenRow(symbol, name, "Token", balance, formatted, false, addr, decimals));
                }
                if (!out.isEmpty()) return out;
            }
        } catch (Exception ignored) {
            // fall through to probing
        }

        JSONObject listResult = repo().listContracts(rpcUrl);
        if (listResult == null) return new ArrayList<>();

        JSONArray contracts = listResult.optJSONArray("contracts");
        if (contracts == null || contracts.length() == 0) return new ArrayList<>();

        final String walletAddr = walletAddress;
        ExecutorService tokenPool = Executors.newFixedThreadPool(
                Math.min(8, contracts.length()));

        List<Future<TokenRow>> futures = new ArrayList<>(contracts.length());
        for (int i = 0; i < contracts.length(); i++) {
            JSONObject contract = contracts.optJSONObject(i);
            if (contract == null) continue;
            String contractAddr = contract.optString("address", "");
            if (contractAddr.isEmpty()) continue;

            final String addr = contractAddr;
            futures.add(tokenPool.submit(() -> {
                try {
                    // 1) Symbol — required; skip contract if missing
                    String symbol = getContractStorage(addr, "symbol");
                    if (symbol == null || symbol.isEmpty() || "0".equals(symbol)) return null;
                    if (symbol.length() > 10) symbol = symbol.substring(0, 10);

                    // 2) Balance for this wallet — skip if zero
                    String balance = getContractBalance(addr, walletAddr);
                    if (balance == null || balance.isEmpty() || "0".equals(balance)) return null;

                    // 3) Name + decimals
                    String name = getContractStorage(addr, "name");
                    if (name == null || name.isEmpty()) name = symbol;
                    if (name.length() > 32) name = name.substring(0, 32);

                    String decimalsStr = getContractStorage(addr, "decimals");
                    int decimals = 0;
                    try { decimals = Integer.parseInt(decimalsStr); } catch (Exception ignored) {}

                    String formatted = formatTokenWithDecimals(balance, decimals);
                    return new TokenRow(symbol, name, "Token", balance, formatted, false, addr, decimals);
                } catch (Exception e) {
                    return null;
                }
            }));
        }

        List<TokenRow> tokens = new ArrayList<>();
        for (Future<TokenRow> future : futures) {
            try {
                TokenRow row = future.get(10, TimeUnit.SECONDS);
                if (row != null) tokens.add(row);
            } catch (Exception ignored) {}
        }
        tokenPool.shutdown();
        return tokens;
    }
    
    private String getContractStorage(String contractAddr, String key) {
        try {
            return repo().contractStorage(rpcUrl, contractAddr, key);
        } catch (Exception e) {
            return null;
        }
    }

    private String getContractBalance(String contractAddr, String walletAddr) {
        try {
            JSONObject result = repo().contractView(
                    rpcUrl, contractAddr, "balance_of",
                    new JSONArray().put(walletAddr), walletAddr);
            if (result == null) return "0";
            return result.optString("result", "0");
        } catch (Exception e) {
            return "0";
        }
    }
    
    private String formatTokenWithDecimals(String rawValue, int decimals) {
        return TokenFormat.format(rawValue, decimals);
    }

    private void refreshHistory() {
        if (walletAddress == null || rpcUrl == null) {
            historyRefresh.setRefreshing(false);
            return;
        }

        historyOffset = 0;
        historyHasMore = true;
        historyLoadingMore = true;

        executor.execute(() -> {
            JSONArray txs = fetchHistoryFromRpc(HISTORY_PAGE_SIZE, historyOffset);
            JSONArray hydrated = hydrateHistoryRows(txs);
            mainHandler.post(() -> {
                if (isFinishing() || isDestroyed()) return;
                renderHistory(hydrated);
                saveHistoryCache(hydrated);
                historyOffset = hydrated.length();
                historyHasMore = hydrated.length() >= HISTORY_PAGE_SIZE;
                historyLoadingMore = false;
                historyRefresh.setRefreshing(false);
            });
        });
    }

    private void loadMoreHistoryIfNeeded() {
        if (!historyHasMore || historyLoadingMore || walletAddress == null || rpcUrl == null) {
            return;
        }
        historyLoadingMore = true;
        final int offset = historyOffset;
        executor.execute(() -> {
            JSONArray txs = fetchHistoryFromRpc(HISTORY_PAGE_SIZE, offset);
            JSONArray hydrated = hydrateHistoryRows(txs);
            mainHandler.post(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (hydrated.length() == 0) {
                    historyHasMore = false;
                    historyLoadingMore = false;
                    return;
                }

                JSONArray combined = toJsonArray(historyItems);
                Set<String> seenHashes = new HashSet<>();
                for (int i = 0; i < combined.length(); i++) {
                    JSONObject row = combined.optJSONObject(i);
                    if (row == null) continue;
                    String h = firstNonEmpty(row.optString("hash", ""), row.optString("tx_hash", "")).trim();
                    if (!h.isEmpty()) seenHashes.add(h);
                }

                for (int i = 0; i < hydrated.length(); i++) {
                    JSONObject row = hydrated.optJSONObject(i);
                    if (row == null) continue;
                    String h = firstNonEmpty(row.optString("hash", ""), row.optString("tx_hash", "")).trim();
                    if (!h.isEmpty() && seenHashes.contains(h)) {
                        continue;
                    }
                    combined.put(row);
                }

                renderHistory(combined);
                saveHistoryCache(combined);
                historyOffset = historyOffset + hydrated.length();
                historyHasMore = hydrated.length() >= HISTORY_PAGE_SIZE;
                historyLoadingMore = false;
            });
        });
    }

    private void renderCachedHistoryIfAny() {
        final String walletKey = activeWalletId == null ? "default" : activeWalletId;
        // Try Room first (async – holds more entries with richer data than SharedPreferences).
        executor.execute(() -> {
            try {
                List<JSONObject> roomRows =
                        walletRepository.loadHistoryFromRoom(walletKey, HISTORY_PAGE_SIZE * 2);
                if (!roomRows.isEmpty()) {
                    JSONArray arr = new JSONArray();
                    for (JSONObject row : roomRows) arr.put(row);
                    mainHandler.post(() -> {
                        if (!isFinishing() && !isDestroyed()) renderHistory(arr);
                    });
                    return;
                }
            } catch (Exception ignored) {}

            // Fall back to SharedPreferences cache.
            try {
                String raw = getSharedPreferences(PREFS_TX_CACHE, MODE_PRIVATE)
                        .getString(KEY_TX_CACHE_PREFIX + walletKey, "");
                if (raw == null || raw.trim().isEmpty()) return;
                JSONArray arr = new JSONArray(raw);
                if (arr.length() > 0) {
                    mainHandler.post(() -> {
                        if (!isFinishing() && !isDestroyed()) renderHistory(arr);
                    });
                }
            } catch (Exception ignored) {}
        });
    }

    private void renderCachedTokenSnapshotIfAny() {
        final String walletKey = activeWalletId == null ? "default" : activeWalletId;
        executor.execute(() -> {
            try {
                WalletRepository.TokenSnapshot snapshot =
                        walletRepository.loadTokenSnapshotFromRoom(walletKey);
                if (snapshot == null || snapshot.tokens == null || snapshot.tokens.length() == 0) {
                    return;
                }
                List<TokenRow> cachedRows = new ArrayList<>();
                for (int i = 0; i < snapshot.tokens.length(); i++) {
                    JSONObject row = snapshot.tokens.optJSONObject(i);
                    if (row == null) continue;
                    TokenRow tokenRow = tokenRowFromJson(row);
                    if (tokenRow != null) cachedRows.add(tokenRow);
                }
                if (cachedRows.isEmpty()) return;

                mainHandler.post(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    latestPublicRaw = snapshot.publicRaw;
                    latestEncryptedRaw = snapshot.encryptedRaw;
                    latestSnapshotReady = true;
                    totalBalanceText.setText(formatAmount(String.valueOf(snapshot.totalRaw)) + " OCT");
                    if (publicBalanceText != null) {
                        publicBalanceText.setText("Public: " + formatAmount(String.valueOf(snapshot.publicRaw)) + " OCT");
                    }
                    if (encryptedBalanceText != null) {
                        encryptedBalanceText.setText("Encrypted: " + formatAmount(String.valueOf(snapshot.encryptedRaw)) + " OCT");
                    }
                    tokenItems.clear();
                    tokenItems.addAll(cachedRows);
                    applyTokenFilter(tokenSearchInput.getText() == null ? "" : tokenSearchInput.getText().toString());
                });
            } catch (Exception ignored) {
            }
        });
    }

    private void persistTokenSnapshotToDbAsync() {
        final String walletId = activeWalletId == null ? "default" : activeWalletId;
        final long totalRaw = latestPublicRaw + latestEncryptedRaw;
        final long publicRaw = latestPublicRaw;
        final long encryptedRaw = latestEncryptedRaw;
        final JSONArray tokens = tokenRowsToJsonArray(tokenItems);
        executor.execute(() -> walletRepository.saveTokenSnapshotToRoom(
                walletId,
                totalRaw,
                publicRaw,
                encryptedRaw,
                tokens));
    }

    private JSONArray tokenRowsToJsonArray(List<TokenRow> rows) {
        JSONArray array = new JSONArray();
        if (rows == null) return array;
        for (TokenRow row : rows) {
            if (row == null) continue;
            JSONObject obj = new JSONObject();
            try {
                obj.put("token_symbol", row.tokenSymbol == null ? "" : row.tokenSymbol);
                obj.put("token_name", row.tokenName == null ? "" : row.tokenName);
                obj.put("balance_type", row.balanceType == null ? "" : row.balanceType);
                obj.put("raw_value", row.rawValue == null ? "0" : row.rawValue);
                obj.put("formatted_value", row.formattedValue == null ? "0" : row.formattedValue);
                obj.put("encrypted", row.encrypted);
                obj.put("token_address", row.tokenAddress == null ? "" : row.tokenAddress);
                obj.put("decimals", row.decimals);
            } catch (Exception ignored) {
            }
            array.put(obj);
        }
        return array;
    }

    private TokenRow tokenRowFromJson(JSONObject obj) {
        if (obj == null) return null;
        String symbol = obj.optString("token_symbol", "").trim();
        String name = obj.optString("token_name", "").trim();
        String balanceType = obj.optString("balance_type", "").trim();
        String rawValue = obj.optString("raw_value", "0").trim();
        String formattedValue = obj.optString("formatted_value", "0").trim();
        boolean encrypted = obj.optBoolean("encrypted", false);
        String tokenAddress = obj.optString("token_address", "").trim();
        int decimals = obj.optInt("decimals", 9);
        if (symbol.isEmpty()) symbol = "OCT";
        if (name.isEmpty()) name = "Octra Token";
        if (balanceType.isEmpty()) balanceType = "Token";
        return new TokenRow(symbol, name, balanceType, rawValue, formattedValue, encrypted, tokenAddress, decimals);
    }

    private void saveHistoryCache(JSONArray txs) {
        try {
            String walletKey = activeWalletId == null ? "default" : activeWalletId;
            getSharedPreferences(PREFS_TX_CACHE, MODE_PRIVATE)
                    .edit()
                    .putString(KEY_TX_CACHE_PREFIX + walletKey, txs == null ? "[]" : txs.toString())
                    .apply();
        } catch (Exception ignored) {
        }
        // Also persist to Room DB on the background executor for richer offline access.
        persistHistoryToDbAsync(txs);
    }

    private void persistHistoryToDbAsync(JSONArray txs) {
        if (txs == null || txs.length() == 0) return;
        final String walletId = activeWalletId == null ? "default" : activeWalletId;
        executor.execute(() -> {
            try {
                List<JSONObject> list = new ArrayList<>(txs.length());
                for (int i = 0; i < txs.length(); i++) {
                    JSONObject tx = txs.optJSONObject(i);
                    if (tx != null) list.add(tx);
                }
                walletRepository.saveHistoryToRoom(walletId, list);
            } catch (Exception ignored) {}
        });
    }

    private JSONArray hydrateHistoryRows(JSONArray txs) {
        JSONArray out = new JSONArray();
        if (txs == null) {
            return out;
        }
        for (int i = 0; i < txs.length(); i++) {
            JSONObject tx = txs.optJSONObject(i);
            if (tx == null) {
                continue;
            }

            JSONObject merged = tx;
            String hash = firstNonEmpty(tx.optString("hash", ""), tx.optString("tx_hash", "")).trim();
            String fromValue = firstNonEmpty(tx.optString("from", ""), tx.optString("from_", ""), tx.optString("sender", ""));
            String toValue = firstNonEmpty(tx.optString("to", ""), tx.optString("to_", ""), tx.optString("recipient", ""), tx.optString("receiver", ""));
            boolean missingAmount = !hasHistoryAmount(tx);
            boolean missingParties = fromValue.isEmpty() || toValue.isEmpty();
            if (!hash.isEmpty() && (missingAmount || missingParties)) {
                JSONObject detail = fetchTxDetail(hash);
                if (detail != null) {
                    merged = mergeHistoryObjects(tx, detail);
                }
            }

            // Enrich with stored token_symbol from TxTaskStore when the network response omits it.
            if (!hash.isEmpty() && merged.optString("token_symbol", "").trim().isEmpty()) {
                String storedSym = TxTaskStore.getTokenSymbolByTxHash(this, hash);
                if (!storedSym.isEmpty()) {
                    try { merged.put("token_symbol", storedSym); } catch (Exception ignored) {}
                }
            }

            out.put(merged);
        }
        return out;
    }

    private JSONObject mergeHistoryObjects(JSONObject base, JSONObject detail) {
        JSONObject merged = new JSONObject();
        try {
            Iterator<String> baseKeys = base.keys();
            while (baseKeys.hasNext()) {
                String key = baseKeys.next();
                merged.put(key, base.opt(key));
            }

            Iterator<String> detailKeys = detail.keys();
            while (detailKeys.hasNext()) {
                String key = detailKeys.next();
                Object value = detail.opt(key);
                if (value == null || JSONObject.NULL.equals(value)) {
                    continue;
                }
                if (value instanceof String && ((String) value).trim().isEmpty()) {
                    continue;
                }
                merged.put(key, value);
            }
        } catch (Exception ignored) {
            return base;
        }
        return merged;
    }

    private JSONArray fetchHistoryFromRpc(int limit, int offset) {
        try {
            List<JSONObject> txs = repo().fetchHistory(rpcUrl, walletAddress, limit, offset);
            JSONArray out = new JSONArray();
            for (JSONObject tx : txs) out.put(tx);
            return out;
        } catch (Exception e) {
            return new JSONArray();
        }
    }

    private void appendHistorySource(JSONArray out, JSONArray source, String fallbackStatus) {
        if (source == null) {
            return;
        }
        for (int i = 0; i < source.length(); i++) {
            JSONObject row = source.optJSONObject(i);
            if (row != null) {
                if (row.optString("status", "").trim().isEmpty() && fallbackStatus != null && !fallbackStatus.isEmpty()) {
                    try {
                        row.put("status", fallbackStatus);
                    } catch (Exception ignored) {
                    }
                }
                out.put(row);
            }
        }
    }

    private void setupHistoryList() {
        historyRefresh.setOnChildScrollUpCallback((parent, child) -> {
            if (historyListView == null) return false;
            return historyListView.canScrollVertically(-1);
        });

        historyRefresh.setOnRefreshListener(() -> {
            // Only allow refresh if scrolled to top
            if (!historyListView.canScrollVertically(-1)) {
                refreshHistory();
            } else {
                historyRefresh.setRefreshing(false);
            }
        });
        historyListAdapter = new HistoryListAdapter();
        historyListView.setAdapter(historyListAdapter);

        historyListView.addOnScrollListener(new RecyclerView.OnScrollListener() {
            @Override
            public void onScrolled(@NonNull RecyclerView recyclerView, int dx, int dy) {
                updateHistoryScrollTopFabVisibility();
                LinearLayoutManager lm = (LinearLayoutManager) recyclerView.getLayoutManager();
                if (lm != null) {
                    int totalItemCount = lm.getItemCount();
                    int lastVisible = lm.findLastVisibleItemPosition();
                    if (totalItemCount > 0 && lastVisible >= totalItemCount - 3) {
                        loadMoreHistoryIfNeeded();
                    }
                }
            }
        });

        if (historyScrollTopFab != null) {
            historyScrollTopFab.setOnClickListener(v -> {
                if (historyListAdapter == null || historyListAdapter.getItemCount() <= 0) {
                    return;
                }
                historyListView.smoothScrollToPosition(0);
            });
            historyScrollTopFab.setVisibility(View.GONE);
        }
    }

    private void updateHistoryScrollTopFabVisibility() {
        if (historyScrollTopFab == null || historyListView == null) {
            return;
        }
        boolean inHistory = historyView != null && historyView.getVisibility() == View.VISIBLE;
        LinearLayoutManager lm = (LinearLayoutManager) historyListView.getLayoutManager();
        int firstVisible = lm != null ? lm.findFirstVisibleItemPosition() : 0;
        boolean shouldShow = inHistory
                && historyItems.size() > 6
                && firstVisible > 2;
        historyScrollTopFab.setVisibility(shouldShow ? View.VISIBLE : View.GONE);
    }

    private void setupTokenSearch() {
        tokenSearchInput.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                applyTokenFilter(s == null ? "" : s.toString());
            }

            @Override
            public void afterTextChanged(Editable s) {
            }
        });
    }

    private void applyTokenFilter(String query) {
        String normalized = query == null ? "" : query.trim().toLowerCase(Locale.US);
        List<TokenRow> filtered = new ArrayList<>();
        for (TokenRow row : tokenItems) {
            if (normalized.isEmpty()) {
                filtered.add(row);
                continue;
            }
            if (row.tokenName.toLowerCase(Locale.US).contains(normalized)
                    || row.tokenSymbol.toLowerCase(Locale.US).contains(normalized)
                    || row.balanceType.toLowerCase(Locale.US).contains(normalized)) {
                filtered.add(row);
            }
        }
        tokenListView.setAdapter(new TokenListAdapter(filtered));
    }

    private void renderHistory(JSONArray txs) {
        List<HistoryEntry> rows = new ArrayList<>();
        boolean hasSortKey = false;
        for (int i = 0; i < txs.length(); i++) {
            JSONObject tx = txs.optJSONObject(i);
            if (tx == null) {
                continue;
            }
            long key = extractHistorySortKey(tx);
            if (key > 0L) {
                hasSortKey = true;
            }
            rows.add(new HistoryEntry(tx, key, i));
        }

        if (hasSortKey) {
            Collections.sort(rows, (left, right) -> {
                if (left.sortKey != right.sortKey) {
                    return Long.compare(right.sortKey, left.sortKey);
                }
                return Integer.compare(right.sourceIndex, left.sourceIndex);
            });
        } else {
            Collections.sort(rows, (left, right) -> Integer.compare(right.sourceIndex, left.sourceIndex));
        }

        // Build hash → token_symbol map from pending items so the symbol survives tx confirmation.
        Map<String, String> pendingTokenSymbols = new HashMap<>();
        for (JSONObject pending : pendingHistoryItems) {
            String h = firstNonEmpty(pending.optString("hash", ""), pending.optString("tx_hash", "")).trim();
            String sym = pending.optString("token_symbol", "").trim();
            if (!h.isEmpty() && !sym.isEmpty() && !"OCT".equalsIgnoreCase(sym)) {
                pendingTokenSymbols.put(h.toLowerCase(Locale.US), sym);
            }
        }

        List<JSONObject> networkRows = new ArrayList<>();
        Set<String> networkHashes = new HashSet<>();
        for (HistoryEntry entry : rows) {
            JSONObject netTx = entry.tx;
            String hash = firstNonEmpty(netTx.optString("hash", ""), netTx.optString("tx_hash", "")).trim();
            if (!hash.isEmpty()) {
                networkHashes.add(hash);
                // Copy token_symbol from the matching pending entry when the tx is confirmed on-chain.
                if (netTx.optString("token_symbol", "").trim().isEmpty()) {
                    String sym = pendingTokenSymbols.get(hash.toLowerCase(Locale.US));
                    if (sym != null && !sym.isEmpty()) {
                        try { netTx.put("token_symbol", sym); } catch (Exception ignored) {}
                    }
                }
            }
            networkRows.add(netTx);
        }

        List<JSONObject> pendingRows = new ArrayList<>();
        for (JSONObject pending : pendingHistoryItems) {
            String hash = firstNonEmpty(pending.optString("hash", ""), pending.optString("tx_hash", "")).trim();
            if (!hash.isEmpty() && networkHashes.contains(hash)) {
                continue;
            }
            pendingRows.add(pending);
        }
        Collections.sort(pendingRows, (left, right) -> Long.compare(extractHistorySortKey(right), extractHistorySortKey(left)));
        pendingHistoryItems.clear();
        pendingHistoryItems.addAll(pendingRows);

        historyItems.clear();
        historyItems.addAll(pendingRows);
        historyItems.addAll(networkRows);

        historyEmptyText.setVisibility(historyItems.isEmpty() ? View.VISIBLE : View.GONE);
        if (historyListAdapter == null) {
            historyListAdapter = new HistoryListAdapter();
            historyListView.setAdapter(historyListAdapter);
        }
        historyListAdapter.notifyDataSetChanged();
        updateHistoryScrollTopFabVisibility();
        historyRefresh.setRefreshing(false);
    }

    private void handleSubmittedTxResult(Intent data) {
        String hash = data.getStringExtra(EXTRA_TX_HASH);
        if (hash == null || hash.trim().isEmpty()) {
            return;
        }
        String to = data.getStringExtra(EXTRA_TX_TO);
        long amountRaw = data.getLongExtra(EXTRA_TX_AMOUNT_RAW, 0L);
        String status = data.getStringExtra(EXTRA_TX_STATUS);
        String tokenSymbol = data.getStringExtra(EXTRA_TX_TOKEN_SYMBOL);
        String txType = data.getStringExtra(EXTRA_TX_TYPE);
        JSONObject pending = new JSONObject();
        try {
            pending.put("hash", hash);
            pending.put("tx_hash", hash);
            pending.put("to", to == null ? "" : to);
            pending.put("amount_raw", String.valueOf(Math.max(amountRaw, 0L)));
            if (tokenSymbol != null && !tokenSymbol.trim().isEmpty()) {
                pending.put("token_symbol", tokenSymbol.trim());
            }
            if (txType != null && !txType.trim().isEmpty()) {
                pending.put("tx_type", txType.trim());
            }
            pending.put("status", status == null || status.trim().isEmpty() ? "pending" : status);
            pending.put("local_ts", System.currentTimeMillis());
        } catch (JSONException ignored) {
            return;
        }

        for (int i = 0; i < pendingHistoryItems.size(); i++) {
            JSONObject existing = pendingHistoryItems.get(i);
            String existingHash = firstNonEmpty(existing.optString("hash", ""), existing.optString("tx_hash", "")).trim();
            if (hash.equalsIgnoreCase(existingHash)) {
                pendingHistoryItems.set(i, pending);
                renderHistory(toJsonArray(historyItems));
                return;
            }
        }

        pendingHistoryItems.add(0, pending);
        renderHistory(toJsonArray(historyItems));
        if (historyView != null && historyView.getVisibility() == View.VISIBLE) {
            historyListView.smoothScrollToPosition(0);
        }
        
        // Auto refresh balance after transaction (no loading indicator)
        scheduleBalanceRefresh();
    }

    private void scheduleBalanceRefresh() {
        // Refresh balance after a short delay to allow blockchain to process
        mainHandler.postDelayed(() -> {
            if (isFinishing() || isDestroyed()) return;
            refreshBalance(false);
        }, 3000);
        // Second refresh after 8 seconds for confirmation
        mainHandler.postDelayed(() -> {
            if (isFinishing() || isDestroyed()) return;
            refreshBalance(false);
        }, 8000);
    }

    private JSONArray toJsonArray(List<JSONObject> rows) {
        JSONArray array = new JSONArray();
        for (JSONObject row : rows) {
            array.put(row);
        }
        return array;
    }

    private void showHistoryDetail(JSONObject tx) {
        showHistoryDetailDialog(tx);
    }

    private void showSendMenu() {
        if (isFinishing() || isDestroyed()) return;
        startActivity(new Intent(this, SendMenuActivity.class));
    }

    private void setupSettingsActionsList() {
        if (settingsActionsListView == null) {
            return;
        }
        List<SettingsActionRow> initialRows = new ArrayList<>();
        initialRows.add(new SettingsActionRow("Wallets", "wallets", R.drawable.ic_wallet));
        initialRows.add(new SettingsActionRow("Theme", "theme", R.drawable.ic_palette));
        initialRows.add(new SettingsActionRow("Networks", "network", R.drawable.ic_network));
        initialRows.add(new SettingsActionRow("Permissions", "permissions", R.drawable.ic_notification));
        initialRows.add(new SettingsActionRow("Change PIN", "change_pin", R.drawable.ic_lock));
        initialRows.add(new SettingsActionRow("DApp Origins", "manage_origins", R.drawable.ic_dapp));
        initialRows.add(new SettingsActionRow("DApp Browser", "dapp_browser", R.drawable.ic_dapp));
        initialRows.add(new SettingsActionRow("Cache", "maintenance", R.drawable.ic_cache));
        initialRows.add(new SettingsActionRow("Session", "session", R.drawable.ic_session));
        initialRows.add(new SettingsActionRow("Auto Scan", "auto_scan", R.drawable.ic_auto_scan));
        initialRows.add(new SettingsActionRow("Address Book", "address_book", R.drawable.ic_wallet));
        initialRows.add(new SettingsActionRow("Data Usage", "data_usage", R.drawable.ic_network));
        initialRows.add(new SettingsActionRow("Polling Settings", "polling_settings", R.drawable.ic_nav_history));
        initialRows.add(new SettingsActionRow("Tor Proxy", "tor_proxy", R.drawable.ic_network));
        // Sort all except About and Logout
        List<SettingsActionRow> sortedRows = new ArrayList<>(initialRows);
        sortedRows.sort((left, right) -> left.title.compareToIgnoreCase(right.title));
        // Add About second from bottom, Logout at bottom
        sortedRows.add(new SettingsActionRow("About", "about", R.drawable.ic_info));
        sortedRows.add(new SettingsActionRow("Logout", "logout", R.drawable.ic_logout));
        final List<SettingsActionRow> rows = sortedRows;

        settingsActionsListView.setAdapter(new SettingsActionAdapter(rows, row -> runSettingsAction(row.actionId)));
    }

    private void expandListView(RecyclerView listView) {
        // No-op: RecyclerView handles measurement natively; method retained for compatibility.
    }

    private void runSettingsAction(String actionId) {
        if ("wallets".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, WalletsMenuActivity.class));
            return;
        }
        if ("theme".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, ThemePaletteActivity.class));
            return;
        }
        if ("network".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, NetworkSettingsActivity.class));
            return;
        }
        if ("permissions".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, PermissionsCenterActivity.class));
            return;
        }
        if ("change_pin".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, ChangePinActivity.class));
            return;
        }
        if ("manage_origins".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, DappOriginsActivity.class));
            return;
        }
        if ("dapp_browser".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, DappBrowserActivity.class));
            return;
        }
        if ("maintenance".equals(actionId)) {
            Intent maintenanceIntent = new Intent();
            maintenanceIntent.setClassName(this, "github.com.maragung.octopus_wallet.MaintenanceCenterActivity");
            maintenanceIntent.putExtra("maintenance_mode", true);
            settingsActivityLauncher.launch(maintenanceIntent);
            return;
        }
        if ("session".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, SessionLockActivity.class));
            return;
        }
        if ("auto_scan".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, AutoScanActivity.class));
            return;
        }
        if ("address_book".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, AddressBookActivity.class));
            return;
        }
        if ("data_usage".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, DataUsageActivity.class));
            return;
        }
        if ("polling_settings".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, TxSettingsActivity.class));
            return;
        }
        if ("tor_proxy".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, TorProxySettingsActivity.class));
            return;
        }
        if ("about".equals(actionId)) {
            settingsActivityLauncher.launch(new Intent(this, AboutActivity.class));
            return;
        }
        if ("logout".equals(actionId)) {
            doLogout();
        }
    }

    private void showHistoryDetailDialog(JSONObject tx) {
        // Launch HistoryDetailActivity to show full transaction details
        try {
            android.content.Intent intent = new android.content.Intent(this, HistoryDetailActivity.class);
            intent.putExtra("tx_json", tx == null ? "{}" : tx.toString());
            startActivity(intent);
        } catch (Exception e) {
            showError("Unable to open transaction detail");
        }
    }

    private String firstNonEmpty(String... values) {
        for (String value : values) {
            if (value != null && !value.trim().isEmpty()) {
                return value;
            }
        }
        return "";
    }

    private JSONObject fetchTxDetail(String hash) {
        try {
            JSONObject result = repo().fetchTransaction(rpcUrl, hash);
            if (result == null) return null;
            if (result.has("transaction") && result.optJSONObject("transaction") != null) {
                result = result.optJSONObject("transaction");
            }
            if (!result.has("hash") && !result.has("tx_hash")) {
                result.put("hash", hash);
            }
            return result;
        } catch (Exception e) {
            return null;
        }
    }

    private void openReceive() {
        Intent intent = new Intent(this, ReceiveActivity.class);
        intent.putExtra("address", walletAddress == null ? "" : walletAddress);
        startActivity(intent);
    }

    private void doLogout() {
        if (isFinishing() || isDestroyed()) return;
        Intent intent = new Intent(this, ConfirmActionActivity.class);
        intent.putExtra(ConfirmActionActivity.EXTRA_TITLE, "Logout");
        intent.putExtra(ConfirmActionActivity.EXTRA_MESSAGE,
                "Lock current wallet and return to unlock screen?");
        intent.putExtra(ConfirmActionActivity.EXTRA_POSITIVE, "Logout");
        intent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE, "Cancel");
        confirmLauncher.launch(intent);
    }

    private String buildRpcEndpoint() {
        return OctraRpcClient.buildRpcEndpoint(rpcUrl);
    }

    private String formatAmount(String rawAmount) {
        long raw = parseRawAmount(rawAmount);
        BigDecimal value = BigDecimal.valueOf(raw, 6);
        // Ensure we don't show more than 6 decimals, truncate if necessary
        value = value.setScale(6, RoundingMode.DOWN).stripTrailingZeros();
        if (value.scale() < 0) {
            value = value.setScale(0);
        }
        return value.toPlainString();
    }

    private String formatTokenAmount(String rawAmount) {
        long raw = parseRawAmount(rawAmount);
        BigDecimal value = BigDecimal.valueOf(raw, 6).stripTrailingZeros();
        if (value.scale() < 0) {
            value = value.setScale(0);
        }
        return value.toPlainString();
    }

    private String resolveHistoryStatus(JSONObject tx) {
        String status = firstNonEmpty(
                tx.optString("status", ""),
                tx.optString("state", ""),
                tx.optString("tx_status", ""),
                tx.optString("result", ""),
                tx.optString("final_status", "")
        );

        if (status.isEmpty()) {
            if (tx.has("error") || tx.has("reject_reason") || tx.has("rejection_reason")) {
                return "rejected";
            }
            return "pending";
        }

        String normalized = status.trim().toLowerCase(Locale.US);
        if (normalized.contains("reject") || normalized.contains("fail") || normalized.contains("error")) {
            return "rejected";
        }
        if (normalized.contains("confirm") || normalized.contains("success") || normalized.contains("ok") || normalized.contains("final")) {
            return "confirmed";
        }
        if (normalized.contains("pend") || normalized.contains("queue") || normalized.contains("mempool")) {
            return "pending";
        }
        return normalized;
    }

    private String resolveHistoryType(JSONObject tx) {
        String type = firstNonEmpty(
                tx.optString("op_type", ""),
                tx.optString("type", ""),
                tx.optString("tx_type", "")
        );
        if (type == null || type.trim().isEmpty()) {
            return "standard";
        }
        return type.trim().toLowerCase(Locale.US);
    }

    private long resolveHistoryTimeMillis(JSONObject tx) {
        long localTs = tx.optLong("local_ts", 0L);
        if (localTs > 0L) {
            return localTs;
        }
        String timestampValue = firstNonEmpty(
                tx.optString("timestamp", ""),
                tx.optString("time", ""),
                tx.optString("created_at", ""),
                tx.optString("created", "")
        );
        if (timestampValue == null || timestampValue.trim().isEmpty()) {
            return 0L;
        }
        try {
            double ts = Double.parseDouble(timestampValue.trim());
            if (ts <= 0d) {
                return 0L;
            }
            if (ts > 1000000000000d) {
                return (long) ts;
            }
            return (long) (ts * 1000d);
        } catch (Exception e) {
            return 0L;
        }
    }

    private String formatHistoryTime(long timeMillis) {
        if (timeMillis <= 0L) {
            return "--:--";
        }
        java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.getDefault());
        return sdf.format(new java.util.Date(timeMillis));
    }

    private String compactAddress(String address) {
        if (address == null || address.trim().isEmpty()) {
            return "-";
        }
        String value = address.trim();
        if (value.length() <= 24) {
            return value;
        }
        return value.substring(0, 10) + "..." + value.substring(value.length() - 10);
    }

    private String resolveHistoryAmountRaw(JSONObject tx) {
        String direct = firstNonEmpty(
                tx.optString("amount_raw", ""),
                tx.optString("value_raw", ""),
                tx.optString("raw_amount", ""),
                tx.optString("value", ""),
                tx.optString("amount", "")
        );
        if (!direct.isEmpty()) {
            return normalizeRawAmountCandidate(direct);
        }

        JSONObject nested = tx.optJSONObject("transaction");
        if (nested == null) {
            nested = tx.optJSONObject("tx");
        }
        if (nested == null) {
            nested = tx.optJSONObject("data");
        }
        if (nested != null) {
            String nestedAmount = firstNonEmpty(
                    nested.optString("amount_raw", ""),
                    nested.optString("value_raw", ""),
                    nested.optString("raw_amount", ""),
                    nested.optString("value", ""),
                    nested.optString("amount", "")
            );
            if (!nestedAmount.isEmpty()) {
                return normalizeRawAmountCandidate(nestedAmount);
            }
        }
        return "0";
    }

    private boolean hasHistoryAmount(JSONObject tx) {
        return parseRawAmount(resolveHistoryAmountRaw(tx)) > 0L;
    }

    /**
     * Converts a raw-amount candidate string to a normalised raw microcoin value.
     *
     * <p>If the candidate looks like an integer it is returned as-is.  If it contains
     * a decimal point it is treated as an OCT value and multiplied by 1,000,000
     * using {@link BigDecimal} arithmetic so that precision is never lost
     * (e.g. {@code "0.1"} → {@code "100000"}, not {@code "99999"}).</p>
     */
    private String normalizeRawAmountCandidate(String candidate) {
        if (candidate == null) {
            return "0";
        }
        String text = candidate.trim();
        if (text.isEmpty()) {
            return "0";
        }
        // Fast path: already a plain integer (most common from RPC responses)
        try {
            return String.valueOf(Long.parseLong(text));
        } catch (Exception ignored) {
        }

        String sanitized = text.replaceAll("[^0-9.-]", "");
        if (sanitized.isEmpty() || sanitized.equals("-") || sanitized.equals(".")) {
            return "0";
        }
        try {
            BigDecimal oct = new BigDecimal(sanitized);
            long raw = oct.multiply(BigDecimal.valueOf(1_000_000))
                    .setScale(0, RoundingMode.HALF_UP)
                    .longValueExact();
            return String.valueOf(Math.max(raw, 0L));
        } catch (Exception ignored) {
            return "0";
        }
    }

    private long extractHistorySortKey(JSONObject tx) {
        long millis = resolveHistoryTimeMillis(tx);
        if (millis > 0L) {
            return millis;
        }
        long localTs = tx.optLong("local_ts", 0L);
        if (localTs > 0L) {
            return localTs;
        }
        long height = tx.optLong("block_height", 0L);
        if (height <= 0L) {
            height = tx.optLong("height", 0L);
        }
        if (height > 0L) {
            return height;
        }
        return tx.optLong("nonce", 0L);
    }

    private String formatHistoryStatus(String status) {
        if (status == null || status.trim().isEmpty()) {
            return "Pending";
        }
        String normalized = status.trim().toLowerCase(Locale.US);
        if ("confirmed".equals(normalized)) {
            return "Confirmed";
        }
        if ("rejected".equals(normalized)) {
            return "Rejected";
        }
        if ("pending".equals(normalized)) {
            return "Pending";
        }
        return Character.toUpperCase(normalized.charAt(0)) + normalized.substring(1);
    }

    private String resolveHistoryAmountDisplay(JSONObject tx) {
        String type      = resolveHistoryType(tx);
        String amountRaw = resolveHistoryAmountRaw(tx);

        // Always prefer an explicit token_symbol field regardless of type.
        // This fixes the case where a local "token_send" pending entry or a
        // network "contract_call" entry carries the symbol but the type resolver
        // returns a different string.
        String tokenSym = firstNonEmpty(
                tx.optString("token_symbol", ""),
                tx.optString("symbol", ""),
                tx.optString("ticker", "")
        ).trim();

        if (!tokenSym.isEmpty() && !"OCT".equalsIgnoreCase(tokenSym)) {
            return formatAmount(amountRaw) + " " + tokenSym;
        }

        // Also handle contract/token types that explicitly request their symbol
        if ("contract_call".equals(type) || "token_transfer".equals(type)
                || "token".equals(type) || "token_send".equals(type)) {
            if (!tokenSym.isEmpty()) {
                return formatAmount(amountRaw) + " " + tokenSym;
            }
        }

        // Stealth and all other types default to OCT
        return formatAmount(amountRaw) + " OCT";
    }

    private String formatHistoryTypeLabel(String type) {
        if (type == null || type.trim().isEmpty()) return "Standard";
        String normalized = type.trim().toLowerCase(Locale.US);
        switch (normalized) {
            case "standard": return "Send";
            case "send": return "Send";
            case "stealth": return "Stealth";
            case "stealth_send": return "Stealth";
            case "encrypt": return "Encrypt";
            case "encrypt_balance": return "Encrypt";
            case "decrypt": return "Decrypt";
            case "decrypt_balance": return "Decrypt";
            case "contract_call": return "Token Transfer";
            case "token_transfer": return "Token Transfer";
            case "token": return "Token Transfer";
            case "deploy": return "Deploy";
            case "contract_deploy": return "Deploy";
            default:
                return Character.toUpperCase(normalized.charAt(0)) + normalized.substring(1);
        }
    }

    private long parseRawAmount(String rawAmount) {
        try {
            return Long.parseLong(rawAmount);
        } catch (Exception e) {
            return 0L;
        }
    }

    @Override
    protected void onResume() {
        super.onResume();

        // Check auto-lock session expiry
        if (SessionLockActivity.isSessionExpired(this)) {
            Intent lockIntent = new Intent(this, UnlockActivity.class);
            lockIntent.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(lockIntent);
            finish();
            return;
        }
        SessionLockActivity.recordActivity(this);

        String currentTheme = ThemeManager.getCurrentTheme(this);
        if (appliedThemeKey != null && !appliedThemeKey.equals(currentTheme)) {
            recreate();
            return;
        }

        // Always refresh wallet selector in case accounts were added/removed elsewhere
        String latestWalletId = WalletProfileStore.getSelectedWalletId(this);
        if (latestWalletId != null && !latestWalletId.equals(activeWalletId)) {
            refreshWalletProfiles();
            loadWalletInfo();
        } else {
            List<String> currentIds = WalletProfileStore.getWalletIds(this);
            if (currentIds.size() != walletIds.size() || !currentIds.equals(walletIds)) {
                refreshWalletProfiles();
            }
        }

        if (walletAddress != null && !walletAddress.isEmpty() && rpcUrl != null && !rpcUrl.isEmpty()) {
            refreshHistory();
        }

        // Start/stop auto scan service based on settings
        int scanInterval = AutoScanActivity.getScanIntervalMinutes(this);
        if (scanInterval > 0) {
            AutoScanService.setScanListener(() -> {
                if (walletAddress != null && !walletAddress.isEmpty()) {
                    refreshDashboardData(false);
                }
            });
            AutoScanService.startScanning(this);
        } else {
            AutoScanService.stopScanning(this);
            AutoScanService.setScanListener(null);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    protected void onStop() {
        super.onStop();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    public void onUserInteraction() {
        super.onUserInteraction();
        SessionLockActivity.recordActivity(this);
    }

    private String shortenAddress(String address) {
        if (address == null || address.isEmpty()) {
            return "-";
        }
        if (address.length() <= 20) {
            return address;
        }
        return address.substring(0, 8) + "..." + address.substring(address.length() - 8);
    }

    private String shortenHash(String hash) {
        if (hash == null || hash.isEmpty()) {
            return "-";
        }
        if (hash.length() <= 16) {
            return hash;
        }
        return hash.substring(0, 8) + "..." + hash.substring(hash.length() - 8);
    }

    private String getAppVersionText() {
        try {
            PackageInfo packageInfo = getPackageManager().getPackageInfo(getPackageName(), 0);
            String versionName = packageInfo.versionName == null ? "-" : packageInfo.versionName;
            return "Version " + versionName;
        } catch (Exception e) {
            return "Version -";
        }
    }

    private static final class TokenRow {
        final String tokenSymbol;
        final String tokenName;
        final String balanceType;
        final String rawValue;
        final String formattedValue;
        final boolean encrypted;
        final String tokenAddress;
        final int decimals;

        TokenRow(String tokenSymbol, String tokenName, String balanceType, String rawValue, String formattedValue, boolean encrypted) {
            this(tokenSymbol, tokenName, balanceType, rawValue, formattedValue, encrypted, null, 9);
        }

        TokenRow(String tokenSymbol, String tokenName, String balanceType, String rawValue, String formattedValue, boolean encrypted, String tokenAddress, int decimals) {
            this.tokenSymbol = tokenSymbol;
            this.tokenName = tokenName;
            this.balanceType = balanceType;
            this.rawValue = rawValue;
            this.formattedValue = formattedValue;
            this.encrypted = encrypted;
            this.tokenAddress = tokenAddress;
            this.decimals = decimals;
        }
    }

    private static final class HistoryEntry {
        final JSONObject tx;
        final long sortKey;
        final int sourceIndex;

        HistoryEntry(JSONObject tx, long sortKey, int sourceIndex) {
            this.tx = tx;
            this.sortKey = sortKey;
            this.sourceIndex = sourceIndex;
        }
    }

    private static final class SettingsActionRow {
        final String title;
        final String actionId;
        final int iconResId;

        SettingsActionRow(String title, String actionId, int iconResId) {
            this.title = title;
            this.actionId = actionId;
            this.iconResId = iconResId;
        }
    }

    private final class TokenListAdapter extends RecyclerView.Adapter<TokenListAdapter.VH> {
        private final List<TokenRow> rows;

        TokenListAdapter(List<TokenRow> rows) {
            this.rows = rows;
        }

        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(MainActivity.this).inflate(R.layout.item_token_balance, parent, false);
            return new VH(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            TokenRow row = rows.get(position);
            holder.title.setText(row.tokenName);
            holder.ticker.setText(row.tokenSymbol);
            holder.balanceTypeIcon.setImageResource(row.encrypted ? R.drawable.ic_encrypted_eye : R.drawable.ic_public_eye);
            holder.amount.setText(row.formattedValue);
            holder.menuButton.setOnClickListener(v -> showTokenItemMenu(row, v));
        }

        @Override
        public int getItemCount() {
            return rows.size();
        }

        final class VH extends RecyclerView.ViewHolder {
            final TextView title;
            final TextView ticker;
            final ImageView balanceTypeIcon;
            final TextView amount;
            final View menuButton;

            VH(View itemView) {
                super(itemView);
                title = itemView.findViewById(R.id.token_title_text);
                ticker = itemView.findViewById(R.id.token_ticker_text);
                balanceTypeIcon = itemView.findViewById(R.id.token_balance_type_icon);
                amount = itemView.findViewById(R.id.token_amount_text);
                menuButton = itemView.findViewById(R.id.token_menu_button);
            }
        }
    }

    private final class SettingsActionAdapter extends RecyclerView.Adapter<SettingsActionAdapter.VH> {
        private final List<SettingsActionRow> rows;
        private final OnSettingsItemClickListener listener;

        SettingsActionAdapter(List<SettingsActionRow> rows, OnSettingsItemClickListener listener) {
            this.rows = rows;
            this.listener = listener;
        }

        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(MainActivity.this).inflate(R.layout.item_settings_action, parent, false);
            return new VH(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            SettingsActionRow row = rows.get(position);
            holder.title.setText(row.title);
            if (holder.icon != null && row.iconResId != 0) {
                holder.icon.setImageResource(row.iconResId);
                holder.icon.setImageTintList(android.content.res.ColorStateList.valueOf(
                        com.google.android.material.color.MaterialColors.getColor(holder.icon, com.google.android.material.R.attr.colorPrimary)));
                holder.icon.setVisibility(View.VISIBLE);
            }
            holder.itemView.setOnClickListener(v -> listener.onItemClick(row));
        }

        @Override
        public int getItemCount() {
            return rows.size();
        }

        final class VH extends RecyclerView.ViewHolder {
            final TextView title;
            final ImageView icon;

            VH(View itemView) {
                super(itemView);
                title = itemView.findViewById(R.id.settings_action_title);
                icon = itemView.findViewById(R.id.settings_action_icon);
            }
        }
    }

    private interface OnSettingsItemClickListener {
        void onItemClick(SettingsActionRow row);
    }

    private void showTokenItemMenu(TokenRow row, View anchor) {
        PopupMenu menu = new PopupMenu(this, anchor);
        final int actionSend = 1;
        final int actionStealth = 2;
        final int actionEncrypt = 3;
        final int actionDecrypt = 4;
        final int actionUnsupported = 5;

        boolean isContractToken = "Token".equals(row.balanceType);

        if (isContractToken) {
            menu.getMenu().add(0, actionSend, 0, "Send Token");
            menu.getMenu().add(0, actionUnsupported, 1, "Token privacy features are not supported");
        } else if (row.encrypted) {
            menu.getMenu().add(0, actionStealth, 0, "Send Stealth");
            menu.getMenu().add(0, actionDecrypt, 1, "Decrypt");
        } else {
            menu.getMenu().add(0, actionSend, 0, "Send");
            menu.getMenu().add(0, actionEncrypt, 1, "Encrypt");
        }

        menu.setOnMenuItemClickListener(item -> {
            int id = item.getItemId();
            if (id == actionSend) {
                Intent intent = new Intent(this, SendActivity.class);
                if (isContractToken) {
                    intent.putExtra(SendActivity.EXTRA_TOKEN_ADDRESS, row.tokenAddress == null ? "" : row.tokenAddress);
                    intent.putExtra(SendActivity.EXTRA_TOKEN_SYMBOL, row.tokenSymbol == null ? "" : row.tokenSymbol);
                    intent.putExtra(SendActivity.EXTRA_TOKEN_NAME, row.tokenName == null ? "" : row.tokenName);
                    intent.putExtra(SendActivity.EXTRA_TOKEN_DECIMALS, row.decimals);
                }
                txActivityLauncher.launch(intent);
                return true;
            }
            if (id == actionStealth) {
                txActivityLauncher.launch(new Intent(this, StealthSendActivity.class));
                return true;
            }
            if (id == actionEncrypt) {
                startActivity(new Intent(this, EncryptBalanceActivity.class));
                return true;
            }
            if (id == actionDecrypt) {
                startActivity(new Intent(this, DecryptBalanceActivity.class));
                return true;
            }
            if (id == actionUnsupported) {
                showError("Token privacy features are not supported yet");
                return true;
            }
            return false;
        });
        menu.show();
    }

    private final class HistoryListAdapter extends RecyclerView.Adapter<HistoryListAdapter.VH> {
        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(MainActivity.this).inflate(R.layout.item_history_row, parent, false);
            return new VH(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            JSONObject tx = historyItems.get(position);
            String hash = tx.optString("hash", tx.optString("tx_hash", "-"));
            String amountRaw = resolveHistoryAmountRaw(tx);
            String status = resolveHistoryStatus(tx);
            String type = resolveHistoryType(tx);
            String from = firstNonEmpty(tx.optString("from", ""), tx.optString("from_", ""), tx.optString("sender", ""));
            String to = firstNonEmpty(tx.optString("to", ""), tx.optString("to_", ""), tx.optString("recipient", ""), tx.optString("receiver", ""));

            holder.amountText.setText(resolveHistoryAmountDisplay(tx));
            holder.typeText.setText(formatHistoryTypeLabel(type));

            String statusFormatted = formatHistoryStatus(status);
            if (statusFormatted != null && !statusFormatted.isEmpty()) {
                holder.statusText.setVisibility(View.VISIBLE);
                holder.statusText.setText("• " + statusFormatted);
            } else {
                holder.statusText.setVisibility(View.GONE);
            }

            holder.timeText.setText(formatHistoryTime(resolveHistoryTimeMillis(tx)));

            // Show counterparty address (the other party, not user's own address)
            boolean isSent = walletAddress != null && !walletAddress.isEmpty()
                    && from != null && from.equalsIgnoreCase(walletAddress);
            holder.directionIcon.setImageResource(isSent ? R.drawable.ic_arrow_sent : R.drawable.ic_arrow_received);

            String counterparty = isSent ? to : from;
            if (counterparty != null && !counterparty.isEmpty()) {
                holder.partiesText.setVisibility(View.VISIBLE);
                holder.partiesText.setText((isSent ? "To: " : "From: ") + compactAddress(counterparty));
            } else {
                holder.partiesText.setVisibility(View.GONE);
            }

            holder.itemView.setOnClickListener(v -> {
                if (position >= 0 && position < historyItems.size()) {
                    showHistoryDetail(historyItems.get(position));
                }
            });
        }

        @Override
        public int getItemCount() {
            return historyItems.size();
        }

        final class VH extends RecyclerView.ViewHolder {
            final android.widget.ImageView directionIcon;
            final TextView amountText;
            final TextView statusText;
            final TextView typeText;
            final TextView partiesText;
            final TextView timeText;

            VH(View itemView) {
                super(itemView);
                directionIcon = itemView.findViewById(R.id.history_direction_icon);
                amountText = itemView.findViewById(R.id.history_amount_text);
                statusText = itemView.findViewById(R.id.history_status_text);
                typeText = itemView.findViewById(R.id.history_type_text);
                partiesText = itemView.findViewById(R.id.history_parties_text);
                timeText = itemView.findViewById(R.id.history_time_text);
            }
        }
    }

    private void copyText(String label, String value) {
        if (value == null || value.isEmpty() || "-".equals(value)) {
            showError(label + " is empty");
            return;
        }
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard != null) {
            clipboard.setPrimaryClip(ClipData.newPlainText(label, value));
        }
        showSuccess(label + " copied");
        // Auto-clear clipboard after 30 seconds to prevent shoulder-surfing
        mainHandler.postDelayed(() -> {
            try {
                ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                if (cm == null) return;
                ClipData current = cm.getPrimaryClip();
                if (current == null || current.getItemCount() == 0) return;
                CharSequence currentText = current.getItemAt(0).coerceToText(this);
                if (currentText != null && currentText.toString().equals(value)) {
                    cm.setPrimaryClip(ClipData.newPlainText("", ""));
                }
            } catch (Exception ignored) {}
        }, 30_000L);
    }

    private void showError(String message) {
        Toast.makeText(this, AppErrorCode.withCode("MainActivity", message), Toast.LENGTH_LONG).show();
    }

    private void showSuccess(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    @Override
    protected void onDestroy() {
        AutoScanService.setScanListener(null);
        executor.shutdownNow();
        super.onDestroy();
    }
}
