package com.octopus.wallet;

import android.annotation.SuppressLint;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.view.KeyEvent;
import android.view.LayoutInflater;
import android.view.MenuItem;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.PopupMenu;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.button.MaterialButton;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * In-app dApp browser with Startpage + modular {@code window.octra} provider.
 *
 * <p>Provider calls enter through {@link DappJsBridge} (minimal, validated
 * {@code @JavascriptInterface}) and dispatch to {@link AdapterRegistry} adapters — currently {@link
 * OctraWalletAdapter}. Sensitive actions require explicit approval via {@link
 * ConfirmActionActivity}; dismissal or cancel always counts as rejection, never approval.
 */
public class DappBrowserActivity extends AppCompatActivity implements DappJsBridge.Host {

  private static final String TAG = "DappBrowser";
  private static final long NAV_DEBOUNCE_MS = 600L;

  private WebView webView;
  private EditText urlInput;
  private ProgressBar progressBar;
  private LinearLayout connectionStatus;
  private TextView connectionText;

  private View startpageRoot;
  private RecyclerView recentList;
  private View recentEmpty;
  private View recentError;
  private RecentVisitsAdapter recentAdapter;
  private LinearLayout bookmarksStrip;
  private TextView privateBanner;

  private final DappSessionManager sessions = new DappSessionManager();
  private DappJsBridge bridge;
  private boolean destroyed = false;
  private boolean privateMode = false;
  private String currentHost = "";
  private String lastPageTitle = "";
  private long lastNavAt = 0L;

  // ─── Approval queue (one dialog at a time; cancel == deny) ────────────

  private static final class ApprovalJob {
    final String title;
    final String message;
    final WalletAdapterContext.ApprovalCallback callback;

    ApprovalJob(String title, String message, WalletAdapterContext.ApprovalCallback callback) {
      this.title = title;
      this.message = message;
      this.callback = callback;
    }
  }

  private final Deque<ApprovalJob> approvalQueue = new ArrayDeque<>();
  private boolean approvalShowing = false;

  // Overflow menu item ids (bookmark toggle + private mode).
  private static final int MENU_BOOKMARK = 1;
  private static final int MENU_PRIVATE = 2;
  private static final int MAX_STARTPAGE_CHIPS = 8;

  private final ActivityResultLauncher<Intent> confirmLauncher =
      registerForActivityResult(
          new ActivityResultContracts.StartActivityForResult(),
          result -> {
            approvalShowing = false;
            ApprovalJob done = approvalQueue.poll();
            boolean approved =
                result.getResultCode() == RESULT_OK
                    && result.getData() != null
                    && result
                        .getData()
                        .getBooleanExtra(ConfirmActionActivity.EXTRA_CONFIRMED, false);
            if (done != null && done.callback != null) {
              try {
                done.callback.onDecision(approved);
              } catch (Exception e) {
                Log.w(TAG, "Approval callback failed: " + e.getMessage());
              }
            }
            pumpApprovals();
          });

  // ─── Lifecycle ─────────────────────────────────────────────────────

  @SuppressLint("SetJavaScriptEnabled")
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    setTheme(ThemeManager.resolveThemeRes(this));
    super.onCreate(savedInstanceState);
    setContentView(R.layout.activity_dapp_browser);
    // Edge-to-edge after content exists so the insets listener attaches.
    InsetsHelper.applyToActivity(this);

    privateMode = getIntent().getBooleanExtra("private_mode", false);

    webView = findViewById(R.id.webView);
    urlInput = findViewById(R.id.urlInput);
    progressBar = findViewById(R.id.progressBar);
    connectionStatus = findViewById(R.id.connectionStatus);
    connectionText = findViewById(R.id.connectionText);
    startpageRoot = findViewById(R.id.startpageRoot);
    recentList = findViewById(R.id.recentList);
    recentEmpty = findViewById(R.id.recentEmpty);
    recentError = findViewById(R.id.recentError);
    bookmarksStrip = findViewById(R.id.bookmarksStrip);
    privateBanner = findViewById(R.id.private_banner);

    ImageButton btnBack = findViewById(R.id.btnBack);
    ImageButton btnHome = findViewById(R.id.btnHome);
    ImageButton btnGo = findViewById(R.id.btnGo);
    ImageButton btnMore = findViewById(R.id.btnMore);
    ImageButton btnClose = findViewById(R.id.btnClose);

    btnBack.setOnClickListener(
        v -> {
          if (webView != null && webView.canGoBack()) {
            webView.goBack();
          }
        });
    btnHome.setOnClickListener(v -> showStartpage());
    btnGo.setOnClickListener(v -> navigateToUrl());
    btnMore.setOnClickListener(v -> showBrowserMenu(btnMore));
    btnClose.setOnClickListener(v -> finish());

    urlInput.setOnEditorActionListener(
        (v, actionId, event) -> {
          if (actionId == EditorInfo.IME_ACTION_GO
              || (event != null && event.getKeyCode() == KeyEvent.KEYCODE_ENTER)) {
            navigateToUrl();
            return true;
          }
          return false;
        });

    WebSettings settings = webView.getSettings();
    settings.setJavaScriptEnabled(true);
    settings.setDomStorageEnabled(true);
    settings.setAllowFileAccess(false);
    settings.setAllowContentAccess(false);
    settings.setCacheMode(WebSettings.LOAD_DEFAULT);

    bridge = new DappJsBridge(this, sessions);
    webView.addJavascriptInterface(bridge, "OctraWalletBridge");

    webView.setWebViewClient(new DappWebViewClient());
    webView.setWebChromeClient(
        new WebChromeClient() {
          @Override
          public void onProgressChanged(WebView view, int newProgress) {
            if (destroyed) return;
            if (newProgress < 100) {
              progressBar.setVisibility(View.VISIBLE);
              progressBar.setProgress(newProgress);
            } else {
              progressBar.setVisibility(View.GONE);
            }
          }

          @Override
          public void onReceivedTitle(WebView view, String title) {
            if (title != null && !title.trim().isEmpty()) {
              lastPageTitle = title.trim();
            }
          }
        });

    recentAdapter =
        new RecentVisitsAdapter(
            new RecentVisitsAdapter.Listener() {
              @Override
              public void onOpen(RecentVisitsStore.Entry entry) {
                openInCurrentTab(entry.url);
              }

              @Override
              public void onOpenNewTab(RecentVisitsStore.Entry entry) {
                RecentVisitsAdapter.openNewTab(DappBrowserActivity.this, entry.url);
              }

              @Override
              public void onDelete(RecentVisitsStore.Entry entry) {
                RecentVisitsStore.remove(DappBrowserActivity.this, entry.url);
                refreshRecent();
              }
            });
    recentList.setLayoutManager(new LinearLayoutManager(this));
    recentList.setAdapter(recentAdapter);

    View clearAll = findViewById(R.id.clearVisitsButton);
    if (clearAll != null) {
      clearAll.setOnClickListener(
          v -> {
            RecentVisitsStore.clearAll(this);
            refreshRecent();
            Toast.makeText(this, "Browsing history cleared", Toast.LENGTH_SHORT).show();
          });
    }

    updatePrivateBanner();

    String intentUrl = getIntent().getStringExtra("url");
    if (intentUrl != null && !intentUrl.trim().isEmpty()) {
      urlInput.setText(intentUrl.trim());
      hideStartpage();
      webView.loadUrl(intentUrl.trim());
    } else {
      showStartpage();
    }
  }

  @Override
  public void onBackPressed() {
    if (webView != null
        && webView.canGoBack()
        && startpageRoot != null
        && startpageRoot.getVisibility() != View.VISIBLE) {
      webView.goBack();
    } else {
      super.onBackPressed();
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    // Edits made in BookmarksActivity land here while the startpage is up.
    if (startpageRoot != null && startpageRoot.getVisibility() == View.VISIBLE) {
      renderBookmarks();
    }
  }

  @Override
  protected void onDestroy() {
    destroyed = true;
    // Pending approvals must never resolve after the host is gone:
    // deny everything outstanding so no request hangs, none approves.
    approvalQueue.clear();
    approvalShowing = false;
    if (bridge != null) {
      try {
        bridge.cancelAll(null);
        bridge.destroy();
      } catch (Exception e) {
        Log.w(TAG, "Bridge destroy failed: " + e.getMessage());
      }
    }
    if (webView != null) {
      try {
        webView.removeJavascriptInterface("OctraWalletBridge");
        webView.stopLoading();
        webView.destroy();
      } catch (Exception e) {
        Log.w(TAG, "WebView destroy failed: " + e.getMessage());
      }
      webView = null;
    }
    super.onDestroy();
  }

  // ─── DappJsBridge.Host ─────────────────────────────────────────────

  @Override
  public String currentUrl() {
    try {
      if (webView != null && webView.getUrl() != null) return webView.getUrl();
    } catch (Exception ignored) {
      // WebView may throw once destroyed — fall through to "".
    }
    return "";
  }

  @Override
  public boolean isConnected() {
    String url = currentUrl();
    if (url.isEmpty() || !isOriginAllowed(url)) return false;
    return sessions.isConnected(url);
  }

  @Override
  public String getConnectedAddress() {
    String url = currentUrl();
    if (url.isEmpty()) return "";
    return sessions.addressFor(url);
  }

  @Override
  public String getOrigin() {
    return currentUrl();
  }

  @Override
  public boolean isOriginAllowed(String url) {
    try {
      String host = DappSessionManager.hostOf(url);
      if (host.isEmpty()) return false;
      Set<String> allowed = DappOriginStore.getAllowedOrigins(this);
      return allowed.contains(DappOriginStore.normalizeHost(host));
    } catch (Exception e) {
      return false;
    }
  }

  @Override
  public List<String> getPermissions() {
    return sessions.permissionsFor(currentUrl());
  }

  @Override
  public void setSessionConnected(String address, List<String> permissions) {
    String url = currentUrl();
    if (url.isEmpty() || address == null || address.isEmpty()) return;
    String host = DappSessionManager.hostOf(url);
    if (!host.isEmpty()) {
      try {
        DappOriginStore.addOrigin(this, host);
      } catch (Exception e) {
        Log.w(TAG, "Persisting origin failed: " + e.getMessage());
      }
    }
    sessions.connect(url, address, permissions);
    runOnUiThread(this::updateConnectionUi);
  }

  @Override
  public void clearSession() {
    sessions.disconnect(currentUrl());
    runOnUiThread(this::updateConnectionUi);
  }

  @Override
  public void sendResult(int requestId, String resultJson) {
    if (destroyed || webView == null) return;
    final String payload = resultJson == null ? "null" : resultJson;
    runOnUiThread(
        () -> {
          if (destroyed || webView == null) return;
          try {
            String js =
                "window.__octra_response("
                    + requestId
                    + ", '"
                    + payload.replace("\\", "\\\\").replace("'", "\\'")
                    + "', null, 0);";
            webView.evaluateJavascript(js, null);
          } catch (Exception e) {
            Log.w(TAG, "sendResult failed: " + e.getMessage());
          }
        });
  }

  @Override
  public void sendError(int requestId, String error, int code) {
    if (destroyed || webView == null) return;
    final String safe = error == null ? "Unknown error" : error;
    final int c = code;
    runOnUiThread(
        () -> {
          if (destroyed || webView == null) return;
          try {
            String js =
                "window.__octra_response("
                    + requestId
                    + ", null, '"
                    + safe.replace("\\", "\\\\").replace("'", "\\'")
                    + "', "
                    + c
                    + ");";
            webView.evaluateJavascript(js, null);
          } catch (Exception e) {
            Log.w(TAG, "sendError failed: " + e.getMessage());
          }
        });
  }

  @Override
  public boolean isCancelled(int requestId) {
    return destroyed || bridge == null || !bridge.isPending(requestId);
  }

  @Override
  public boolean isAlive() {
    return !destroyed && !isFinishing() && !isDestroyed();
  }

  @Override
  public ExecutorService io() {
    return ((OctraWalletApplication) getApplication()).getIoExecutor();
  }

  @Override
  public void requestApproval(
      String title, String message, WalletAdapterContext.ApprovalCallback callback) {
    if (destroyed || callback == null) return;
    runOnUiThread(
        () -> {
          if (destroyed) {
            callback.onDecision(false);
            return;
          }
          approvalQueue.offer(
              new ApprovalJob(
                  title == null ? "Please Confirm" : title,
                  message == null ? "" : message,
                  callback));
          pumpApprovals();
        });
  }

  private void pumpApprovals() {
    if (destroyed || approvalShowing) return;
    ApprovalJob job = approvalQueue.peek();
    if (job == null) return;
    approvalShowing = true;
    try {
      Intent intent = new Intent(this, ConfirmActionActivity.class);
      intent.putExtra(ConfirmActionActivity.EXTRA_TITLE, job.title);
      intent.putExtra(ConfirmActionActivity.EXTRA_MESSAGE, job.message);
      intent.putExtra(ConfirmActionActivity.EXTRA_POSITIVE, "Allow");
      intent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE, "Deny");
      intent.putExtra(ConfirmActionActivity.EXTRA_REQUIRE_EXPLICIT, true);
      confirmLauncher.launch(intent);
    } catch (Exception e) {
      Log.w(TAG, "Approval launch failed: " + e.getMessage());
      approvalShowing = false;
      approvalQueue.poll();
      try {
        job.callback.onDecision(false);
      } catch (Exception ignored) {
        // Callback failure here must not break the queue.
      }
      pumpApprovals();
    }
  }

  // ─── Wallet access (real data only) ────────────────────────────────

  @Override
  public String getWalletAddress() {
    String addr = getIntent().getStringExtra("walletAddress");
    if (addr != null && !addr.trim().isEmpty()) return addr.trim();
    try {
      String raw = OctraNative.getInstance().getWalletInfo();
      if (raw != null && !raw.isEmpty()) {
        return new JSONObject(raw).optString("address", "").trim();
      }
    } catch (Exception ignored) {
      // Fall through to prefs below.
    }
    return getSharedPreferences("wallet_prefs", MODE_PRIVATE).getString("active_address", "");
  }

  @Override
  public String getWalletPublicKeyB64() {
    String pk = getIntent().getStringExtra("walletPublicKey");
    if (pk != null && !pk.trim().isEmpty()) return pk.trim();
    try {
      String raw = OctraNative.getInstance().getWalletInfo();
      if (raw != null && !raw.isEmpty()) {
        JSONObject info = new JSONObject(raw);
        String v = info.optString("public_key", "").trim();
        if (!v.isEmpty()) return v;
      }
    } catch (Exception ignored) {
      // Fall through to prefs below.
    }
    return getSharedPreferences("wallet_prefs", MODE_PRIVATE).getString("active_public_key", "");
  }

  @Override
  public String getRpcUrl() {
    try {
      String raw = OctraNative.getInstance().getWalletInfo();
      if (raw != null && !raw.isEmpty()) {
        String rpc = new JSONObject(raw).optString("rpc_url", "").trim();
        if (!rpc.isEmpty()) return rpc;
      }
    } catch (Exception ignored) {
      // Fall through to default below.
    }
    return UrlSecurityValidator.DEFAULT_RPC;
  }

  @Override
  public String getChainId() {
    return getActiveChainId();
  }

  @Override
  public JSONObject getNetworkInfo() {
    String chainId = getActiveChainId();
    boolean mainnet = chainId.contains("mainnet");
    JSONObject o = new JSONObject();
    try {
      o.put("id", mainnet ? "mainnet" : "devnet");
      o.put("name", mainnet ? "Octra Mainnet" : "Octra Devnet");
      o.put("chainId", chainId);
      o.put("rpcUrl", getRpcUrl());
      o.put("explorerUrl", getActiveExplorerUrl());
      o.put("isTestnet", !mainnet);
    } catch (JSONException e) {
      Log.w(TAG, "networkInfo build failed: " + e.getMessage());
    }
    return o;
  }

  private String getActiveChainId() {
    String rpc = getRpcUrl();
    if (rpc != null && rpc.contains("rpc.octrascan.io")) {
      return "octra-mainnet-1";
    }
    return "octra-devnet-1";
  }

  private String getActiveExplorerUrl() {
    try {
      String raw = OctraNative.getInstance().getWalletInfo();
      if (raw != null && !raw.isEmpty()) {
        String explorer = new JSONObject(raw).optString("explorer_url", "").trim();
        if (!explorer.isEmpty()) return explorer;
      }
    } catch (Exception ignored) {
      // Fall through to default below.
    }
    return UrlSecurityValidator.DEFAULT_EXPLORER;
  }

  // ─── Navigation + Startpage ────────────────────────────────────────

  private void navigateToUrl() {
    if (destroyed || webView == null) return;
    long now = SystemClock.elapsedRealtime();
    if (now - lastNavAt < NAV_DEBOUNCE_MS) return;
    lastNavAt = now;
    String input = urlInput.getText() == null ? "" : urlInput.getText().toString().trim();
    if (input.isEmpty()) return;
    openInCurrentTab(input);
  }

  private void openInCurrentTab(String input) {
    if (destroyed || webView == null || input == null) return;
    String trimmed = input.trim();
    if (trimmed.isEmpty()) return;
    if (isOctUrl(trimmed)) {
      hideStartpage();
      loadOctUrl(trimmed);
      return;
    }
    String url = toWebUrl(trimmed);
    if (url == null) {
      Toast.makeText(this, "Invalid address", Toast.LENGTH_SHORT).show();
      return;
    }
    hideStartpage();
    urlInput.setText(url);
    webView.loadUrl(url);
  }

  /**
   * Search-or-URL: bare words become a privacy-friendly search, anything host-like becomes https.
   * Never returns internal schemes.
   */
  String toWebUrl(String input) {
    if (input == null) return null;
    String t = input.trim();
    if (t.isEmpty()) return null;
    String low = t.toLowerCase(java.util.Locale.US);
    if (low.startsWith("about:")
        || low.startsWith("javascript:")
        || low.startsWith("file://")
        || low.startsWith("data:")) {
      return null;
    }
    if (t.contains(" ") && !t.startsWith("http://") && !t.startsWith("https://")) {
      try {
        return "https://duckduckgo.com/?q=" + Uri.encode(t);
      } catch (Exception e) {
        return null;
      }
    }
    if (!t.startsWith("http://") && !t.startsWith("https://")) {
      t = "https://" + t;
    }
    try {
      Uri parsed = Uri.parse(t);
      if (parsed.getHost() == null || parsed.getHost().isEmpty()) return null;
      return parsed.toString();
    } catch (Exception e) {
      return null;
    }
  }

  private void showStartpage() {
    if (startpageRoot == null) return;
    if (webView != null) {
      try {
        webView.stopLoading();
      } catch (Exception e) {
        Log.w(TAG, "stopLoading failed: " + e.getMessage());
      }
      webView.setVisibility(View.INVISIBLE);
    }
    startpageRoot.setVisibility(View.VISIBLE);
    refreshRecent();
    renderBookmarks();
  }

  private void hideStartpage() {
    if (startpageRoot == null) return;
    startpageRoot.setVisibility(View.GONE);
    if (webView != null) webView.setVisibility(View.VISIBLE);
  }

  private void refreshRecent() {
    if (recentList == null || recentAdapter == null) return;
    try {
      List<RecentVisitsStore.Entry> entries =
          privateMode ? new ArrayList<>() : RecentVisitsStore.getRecent(this);
      recentAdapter.submit(entries);
      boolean empty = entries.isEmpty();
      if (recentEmpty != null) recentEmpty.setVisibility(empty ? View.VISIBLE : View.GONE);
      if (recentError != null) recentError.setVisibility(View.GONE);
      recentList.setVisibility(empty ? View.GONE : View.VISIBLE);
    } catch (Exception e) {
      Log.w(TAG, "Recent refresh failed: " + e.getMessage());
      recentList.setVisibility(View.GONE);
      if (recentEmpty != null) recentEmpty.setVisibility(View.GONE);
      if (recentError != null) recentError.setVisibility(View.VISIBLE);
    }
  }

  private void updateConnectionUi() {
    if (destroyed || connectionStatus == null) return;
    if (isConnected()) {
      String addr = getConnectedAddress();
      String shortAddr =
          (addr != null && addr.length() > 10) ? addr.substring(0, 10) + "..." : addr;
      connectionStatus.setVisibility(View.VISIBLE);
      String host = currentHost.isEmpty() ? "dApp" : currentHost;
      connectionText.setText("Connected to " + host + ": " + shortAddr);
    } else {
      connectionStatus.setVisibility(View.GONE);
    }
  }

  // ─── Overflow menu: bookmark toggle + private mode ─────────────────

  /** Browser overflow menu (anchored at btnMore). */
  private void showBrowserMenu(View anchor) {
    if (destroyed || anchor == null) return;
    final String pageUrl = currentUrl();
    final boolean bookmarked = !pageUrl.isEmpty() && BookmarkStore.contains(this, pageUrl);
    PopupMenu popup = new PopupMenu(this, anchor);
    popup.getMenu().add(0, MENU_BOOKMARK, 0, bookmarked ? "Remove bookmark" : "Bookmark page");
    MenuItem privateItem = popup.getMenu().add(0, MENU_PRIVATE, 1, "Private mode");
    privateItem.setCheckable(true);
    privateItem.setChecked(privateMode);
    popup.setOnMenuItemClickListener(
        item -> {
          if (destroyed) return true;
          int id = item.getItemId();
          if (id == MENU_BOOKMARK) {
            if (bookmarked) removeCurrentBookmark(pageUrl);
            else promptAddBookmark(pageUrl);
            return true;
          }
          if (id == MENU_PRIVATE) {
            setPrivateMode(!privateMode);
            return true;
          }
          return false;
        });
    popup.show();
  }

  /** Adds the current page as a bookmark (name dialog; cancel aborts). */
  private void promptAddBookmark(String pageUrl) {
    if (destroyed) return;
    if (pageUrl.isEmpty() || !RecentVisitsStore.isRecordable(pageUrl)) {
      Toast.makeText(this, "Nothing to bookmark on this page", Toast.LENGTH_SHORT).show();
      return;
    }
    String suggested =
        !lastPageTitle.isEmpty() ? lastPageTitle : (currentHost.isEmpty() ? pageUrl : currentHost);
    final EditText nameInput = new EditText(this);
    nameInput.setText(suggested);
    nameInput.setSelection(nameInput.getText().length());
    new AlertDialog.Builder(this)
        .setTitle("Bookmark page")
        .setMessage(pageUrl)
        .setView(nameInput)
        .setPositiveButton(
            "OK",
            (d, w) -> {
              if (destroyed) return;
              String name =
                  nameInput.getText() == null ? "" : nameInput.getText().toString().trim();
              BookmarkStore.add(DappBrowserActivity.this, name, pageUrl);
              renderBookmarks();
              Toast.makeText(this, "Bookmarked", Toast.LENGTH_SHORT).show();
            })
        .setNegativeButton("Cancel", null)
        .show();
  }

  private void removeCurrentBookmark(String pageUrl) {
    if (destroyed || pageUrl.isEmpty()) return;
    BookmarkStore.remove(this, pageUrl);
    renderBookmarks();
    Toast.makeText(this, "Bookmark removed", Toast.LENGTH_SHORT).show();
  }

  /** Runtime private-mode toggle: recording + startpage honor this field. */
  private void setPrivateMode(boolean on) {
    privateMode = on;
    updatePrivateBanner();
    Toast.makeText(
            this,
            on ? "Private mode on — visits are not recorded" : "Private mode off",
            Toast.LENGTH_SHORT)
        .show();
    if (on && recentList != null) {
      refreshRecent(); // Hide any history list while private.
    }
  }

  private void updatePrivateBanner() {
    if (privateBanner == null) return;
    privateBanner.setVisibility(privateMode ? View.VISIBLE : View.GONE);
  }

  // ─── Startpage quick access (bookmark chips) ───────────────────────

  /**
   * Renders the quick-access strip: up to 8 bookmark chips plus a Manage chip, or the two default
   * explorer shortcuts when nothing is saved yet.
   */
  private void renderBookmarks() {
    if (bookmarksStrip == null || destroyed) return;
    bookmarksStrip.removeAllViews();
    List<BookmarkStore.Bookmark> bookmarks;
    try {
      bookmarks = BookmarkStore.list(this);
    } catch (Exception e) {
      Log.w(TAG, "Bookmark list failed: " + e.getMessage());
      bookmarks = new ArrayList<>();
    }
    if (bookmarks.isEmpty()) {
      addBookmarkChip("Devnet Explorer", UrlSecurityValidator.DEVNET_EXPLORER, null);
      addBookmarkChip("Mainnet Explorer", UrlSecurityValidator.MAINNET_EXPLORER, null);
      return;
    }
    int shown = Math.min(bookmarks.size(), MAX_STARTPAGE_CHIPS);
    for (int i = 0; i < shown; i++) {
      BookmarkStore.Bookmark b = bookmarks.get(i);
      String label = b.name.isEmpty() ? b.url : b.name;
      addBookmarkChip(label, b.url, b.url);
    }
    addManageChip();
  }

  private void addBookmarkChip(String label, String url, final String deletableUrl) {
    MaterialButton chip =
        (MaterialButton)
            LayoutInflater.from(this).inflate(R.layout.item_bookmark_chip, bookmarksStrip, false);
    chip.setText(label);
    chip.setOnClickListener(v -> openInCurrentTab(url));
    if (deletableUrl != null) {
      chip.setOnLongClickListener(
          v -> {
            confirmRemoveBookmark(deletableUrl);
            return true;
          });
    }
    bookmarksStrip.addView(chip);
  }

  private void addManageChip() {
    MaterialButton chip =
        (MaterialButton)
            LayoutInflater.from(this).inflate(R.layout.item_bookmark_chip, bookmarksStrip, false);
    chip.setText("Manage");
    chip.setIconResource(R.drawable.ic_bookmark);
    chip.setOnClickListener(
        v -> {
          if (destroyed) return;
          try {
            startActivity(new Intent(this, BookmarksActivity.class));
          } catch (Exception e) {
            Log.w(TAG, "BookmarksActivity launch failed: " + e.getMessage());
          }
        });
    bookmarksStrip.addView(chip);
  }

  private void confirmRemoveBookmark(String url) {
    if (destroyed) return;
    new AlertDialog.Builder(this)
        .setTitle("Remove bookmark")
        .setMessage(url)
        .setPositiveButton(
            "Remove",
            (d, w) -> {
              if (destroyed) return;
              BookmarkStore.remove(DappBrowserActivity.this, url);
              renderBookmarks();
              Toast.makeText(this, "Bookmark removed", Toast.LENGTH_SHORT).show();
            })
        .setNegativeButton("Cancel", null)
        .show();
  }

  // ─── WebView Client ────────────────────────────────────────────────

  private class DappWebViewClient extends WebViewClient {
    @Override
    public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
      super.onPageStarted(view, url, favicon);
      if (destroyed) return;
      String newHost = DappSessionManager.hostOf(url == null ? "" : url);
      if (!newHost.equals(currentHost)) {
        currentHost = newHost;
        // A cross-origin navigation must not leave the previous page's
        // approvals or reads hanging: fail them loudly, keep sessions.
        if (bridge != null) bridge.cancelAll("Navigation cancelled request");
        approvalQueue.clear();
        approvalShowing = false;
      }
      updateConnectionUi();
    }

    @Override
    public void onPageFinished(WebView view, String url) {
      super.onPageFinished(view, url);
      if (destroyed) return;
      hideStartpage();
      if (url != null) urlInput.setText(url);
      currentHost = DappSessionManager.hostOf(url == null ? "" : url);
      injectProvider();
      updateConnectionUi();
      if (!privateMode && url != null && RecentVisitsStore.isRecordable(url)) {
        String title = lastPageTitle.isEmpty() ? url : lastPageTitle;
        RecentVisitsStore.recordVisit(DappBrowserActivity.this, url, title);
        refreshRecent();
      }
    }

    @Override
    public void onReceivedError(
        WebView view, WebResourceRequest request, android.webkit.WebResourceError error) {
      super.onReceivedError(view, request, error);
      if (destroyed || request == null || !request.isForMainFrame()) return;
      String url = request.getUrl() == null ? "" : request.getUrl().toString();
      Log.w(TAG, "Page error for " + url + ": " + error);
      Toast.makeText(
              DappBrowserActivity.this,
              "Failed to load page — check your connection and try again.",
              Toast.LENGTH_SHORT)
          .show();
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
      if (request == null || request.getUrl() == null) return false;
      String url = request.getUrl().toString();
      if (isOctUrl(url)) {
        loadOctUrl(url);
        return true;
      }
      if (url.startsWith("http://") || url.startsWith("https://")) {
        return false;
      }
      try {
        startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
      } catch (Exception e) {
        Log.w(TAG, "External URL blocked: " + e.getMessage());
      }
      return true;
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
      if (request != null && request.getUrl() != null) {
        String url = request.getUrl().toString();
        if (isOctUrl(url)) {
          return fetchOctResource(url);
        }
      }
      return super.shouldInterceptRequest(view, request);
    }

    @Override
    public boolean onRenderProcessGone(
        WebView view, android.webkit.RenderProcessGoneDetail detail) {
      progressBar.setVisibility(View.GONE);
      boolean crashed = detail != null && detail.didCrash();
      Log.w(TAG, "Renderer gone (crashed=" + crashed + "), offering reload");
      if (destroyed) return true;
      new AlertDialog.Builder(DappBrowserActivity.this)
          .setTitle(crashed ? "Page crashed" : "Page stopped")
          .setMessage("The browser engine ran out of resources. " + "Reload the page to try again.")
          .setPositiveButton(
              "Reload",
              (d, w) -> {
                if (!destroyed && view != null) view.reload();
              })
          .setNegativeButton("Close", (d, w) -> finish())
          .setCancelable(false)
          .show();
      return true;
    }
  }

  // ─── Provider injection ────────────────────────────────────────────

  private void injectProvider() {
    if (destroyed || webView == null) return;
    try {
      webView.evaluateJavascript(getOctraProviderScript(), null);
    } catch (Exception e) {
      Log.w(TAG, "Provider injection failed: " + e.getMessage());
    }
  }

  private String getOctraProviderScript() {
    String chainId = getActiveChainId();
    return "(function() {\n"
        + "  'use strict';\n"
        + "  if (window.octra) return;\n"
        + "\n"
        + "  let _requestId = 0;\n"
        + "  const _pending = new Map();\n"
        + "  const _listeners = {};\n"
        + "  let _connected = false;\n"
        + "  let _accounts = [];\n"
        + "\n"
        + "  function _emit(event, data) {\n"
        + "    for (const cb of _listeners[event] || []) { try { cb(data); } catch {} }\n"
        + "  }\n"
        + "\n"
        + "  // Bridge response handler — called from native\n"
        + "  // RFC-O-1: 4th argument carries the numeric error code (0 = none).\n"
        + "  window.__octra_response = function(id, resultJson, error, code) {\n"
        + "    const p = _pending.get(id);\n"
        + "    if (!p) return;\n"
        + "    _pending.delete(id);\n"
        + "    if (error) {\n"
        + "      const err = new Error(error);\n"
        + "      if (code) err.code = code;\n"
        + "      p.reject(err);\n"
        + "    }\n"
        + "    else p.resolve(JSON.parse(resultJson));\n"
        + "  };\n"
        + "\n"
        + "  const octraProvider = {\n"
        + "    isOctra: true,\n"
        + "    chainId: '"
        + chainId
        + "',\n"
        + "    get accounts() { return [..._accounts]; },\n"
        + "    get isConnected() { return _connected; },\n"
        + "\n"
        + "    async connect() {\n"
        + "      const id = ++_requestId;\n"
        + "      return new Promise((resolve, reject) => {\n"
        + "        _pending.set(id, {resolve, reject});\n"
        + "        OctraWalletBridge.connect(id);\n"
        + "      }).then(r => {\n"
        + "        _connected = true; _accounts = [r.address];\n"
        + "        _emit('connect', r); _emit('accountsChanged', _accounts);\n"
        + "        return r;\n"
        + "      });\n"
        + "    },\n"
        + "\n"
        + "    async disconnect() {\n"
        + "      _connected = false; _accounts = [];\n"
        + "      _emit('disconnect'); _emit('accountsChanged', []);\n"
        + "      return {ok: true};\n"
        + "    },\n"
        + "\n"
        + "    async request({method, params = []}) {\n"
        + "      if (!_connected && method !== 'octra_accounts' && method !== 'octra_chainId'\n"
        + "          && method !== 'disconnect')\n"
        + "        throw new Error('Not connected. Call window.octra.connect() first.');\n"
        + "      const id = ++_requestId;\n"
        + "      return new Promise((resolve, reject) => {\n"
        + "        _pending.set(id, {resolve, reject});\n"
        + "        OctraWalletBridge.request(id, method, JSON.stringify(params));\n"
        + "      }).then(r => {\n"
        + "        if (method === 'octra_requestAccounts' && Array.isArray(r)) {\n"
        + "          _connected = true; _accounts = r;\n"
        + "          _emit('connect', {address: r[0]}); _emit('accountsChanged', _accounts);\n"
        + "        }\n"
        + "        if (method === 'disconnect') {\n"
        + "          _connected = false; _accounts = [];\n"
        + "          _emit('disconnect'); _emit('accountsChanged', []);\n"
        + "        }\n"
        + "        return r;\n"
        + "      });\n"
        + "    },\n"
        + "\n"
        + "    async sendTransaction(to, amount) {\n"
        + "      return this.request({method:'octra_sendTransaction', params:[{to,amount}]});\n"
        + "    },\n"
        + "    async callContract(address, method, params=[], amount='0') {\n"
        + "      return this.request({method:'octra_callContract',"
        + " params:[address,method,params,amount]});\n"
        + "    },\n"
        + "    async callView(address, method, params=[]) {\n"
        + "      return this.request({method:'octra_callView', params:[address,method,params]});\n"
        + "    },\n"
        + "    // wallet_* twins of the legacy submit/view calls (RFC alias dual-stack):\n"
        + "    // same session gate + approval (send) via request(); never allowed pre-connect.\n"
        + "    async sendTransactionWallet(to, amount) {\n"
        + "      return this.request({method:'wallet_sendTransaction', params:[{to,amount}]});\n"
        + "    },\n"
        + "    async callViewWallet(address, method, params=[]) {\n"
        + "      return this.request({method:'wallet_callView', params:[address,method,params]});\n"
        + "    },\n"
        + "    async getBalance() { return this.request({method:'octra_getBalance'}); },\n"
        + "    async requestAccounts() {\n"
        + "      const accounts = await this.request({method:'octra_requestAccounts'});\n"
        + "      _connected = true; _accounts = accounts;\n"
        + "      _emit('connect', {address: accounts[0]}); _emit('accountsChanged', _accounts);\n"
        + "      return accounts;\n"
        + "    },\n"
        + "    async getEncryptedBalance() {\n"
        + "      return this.request({method:'octra_getEncryptedBalance'});\n"
        + "    },\n"
        + "    async contractCall(opts) {\n"
        + "      return this.request({method:'octra_callContract',\n"
        + "        params:[opts.contractAddress, opts.method, opts.params||[],"
        + " opts.amount||'0']});\n"
        + "    },\n"
        + "\n"
        + "    on(event, cb) { if (!_listeners[event]) _listeners[event]=[];"
        + " _listeners[event].push(cb); return this; },\n"
        + "    off(event, cb) { if (_listeners[event])"
        + " _listeners[event]=_listeners[event].filter(c=>c!==cb); return this; },\n"
        + "  };\n"
        + "\n"
        + "  const _walletListeners = {};\n"
        + "  function _wemit(event, data) {\n"
        + "    for (const cb of _walletListeners[event] || []) { try { cb(data); } catch {} }\n"
        + "  }\n"
        + "  function _wforbidden(method) {\n"
        + "    const err = new Error(method + ' is sign-only and not served by this wallet');\n"
        + "    err.code = 'METHOD_FORBIDDEN';\n"
        + "    throw err;\n"
        + "  }\n"
        + "  async function _walletConnectResult(address) {\n"
        + "    let publicKey = '';\n"
        + "    try {\n"
        + "      const pk = await octraProvider.request({method:'getPublicKey'});\n"
        + "      publicKey = (pk && pk.publicKey) || '';\n"
        + "    } catch (e) { publicKey = ''; }\n"
        + "    const networkInfo = await octraProvider.request({method:'octra_networkInfo'});\n"
        + "    const chainId = (networkInfo && networkInfo.chainId) || networkInfo.id;\n"
        + "    const permissions = await octraProvider.request({method:'octra_permissions'});\n"
        + "    return { address, publicKey, accounts: [{address}],\n"
        + "      network: networkInfo.id, networkInfo, chainId,\n"
        + "      capabilities: ['ping','events'] };\n"
        + "  }\n"
        + "  const walletProvider = {\n"
        + "    async connect() {\n"
        + "      const accounts = await octraProvider.request({method:'octra_requestAccounts',"
        + " params:[]});\n"
        + "      const address = accounts[0];\n"
        + "      if (!address) throw new Error('Connect did not yield an address');\n"
        + "      const result = await _walletConnectResult(address);\n"
        + "      _wemit('connect', result);\n"
        + "      _wemit('accountChanged', {address});\n"
        + "      return result;\n"
        + "    },\n"
        + "    async disconnect() {\n"
        + "      await octraProvider.request({method:'disconnect'});\n"
        + "      _wemit('disconnect', {reason:'user disconnect'});\n"
        + "      return undefined;\n"
        + "    },\n"
        + "    isConnected() { return octraProvider.isConnected; },\n"
        + "    async getAccounts() {\n"
        + "      const a = await octraProvider.request({method:'wallet_getAccounts'});\n"
        + "      return a.filter(x => !!x).map(address => ({address}));\n"
        + "    },\n"
        + "    async getAddress() {\n"
        + "      const a = await octraProvider.request({method:'wallet_getAccounts'});\n"
        + "      return a[0] || '';\n"
        + "    },\n"
        + "    async getPublicKey() {\n"
        + "      const r = await octraProvider.request({method:'getPublicKey'});\n"
        + "      return r.publicKey;\n"
        + "    },\n"
        + "    async getBalance() {\n"
        + "      const r = await octraProvider.request({method:'wallet_getBalance'});\n"
        + "      const num = v => { const n = Number(v); return Number.isFinite(n) ? n : 0; };\n"
        + "      return { balance: String(r.balance ?? r.public ?? ''),\n"
        + "        balanceRaw: String(r.balance_raw ?? r.raw ?? ''),\n"
        + "        nonce: num(r.nonce ?? r.pending_nonce) };\n"
        + "    },\n"
        + "    async getNetwork() {\n"
        + "      const n = await octraProvider.request({method:'octra_networkInfo'});\n"
        + "      return n.id;\n"
        + "    },\n"
        + "    async getNetworkInfo() {\n"
        + "      return octraProvider.request({method:'octra_networkInfo'});\n"
        + "    },\n"
        + "    async getNetworks() {\n"
        + "      const n = await octraProvider.request({method:'octra_networkInfo'});\n"
        + "      return [n];\n"
        + "    },\n"
        + "    async getChainId() {\n"
        + "      const n = await octraProvider.request({method:'octra_networkInfo'});\n"
        + "      return (n && typeof n === 'object' && (n.chainId || n.id)) || n;\n"
        + "    },\n"
        + "    async getPermissions() {\n"
        + "      return octraProvider.request({method:'octra_permissions'});\n"
        + "    },\n"
        + "    async signMessage() { _wforbidden('wallet_signMessage'); },\n"
        + "    async signTypedData() { _wforbidden('wallet_signTypedData'); },\n"
        + "    async approveContract() { _wforbidden('wallet_approveContract'); },\n"
        + "    async signContract() { _wforbidden('wallet_signContract'); },\n"
        + "    async signTransfer() { _wforbidden('wallet_signTransfer'); },\n"
        + "    async ping() {\n"
        + "      return { pong: true, v: 1, connected: octraProvider.isConnected,\n"
        + "        locked: !octraProvider.isConnected, capabilities: ['ping','events'],\n"
        + "        origin: window.location.origin, ts: Date.now() };\n"
        + "    },\n"
        + "    async isAlive() { return octraProvider.isConnected; },\n"
        + "    async request(method, params) {\n"
        + "      const m = String(method == null ? '' : method);\n"
        + "      const low = m.trim().toLowerCase();\n"
        + "      const canon = low.startsWith('orion_wallet_') ? 'wallet_' + low.slice(13) : low;\n"
        + "      if"
        + " (/^(wallet_)?(signmessage|signtypeddata|approvecontract|signcontract|signtransfer|signtransaction|submittransaction|sendtransaction|broadcasttransaction|transfer|swap|bridge)$/.test(canon)\n"
        + "          ||"
        + " /(sendtransaction|broadcast|(^|_)transfer$|(^|_)swap$|(^|_)bridge$)/.test(canon)) {\n"
        + "        const err = new Error(canon + ' is prohibited: this wallet never broadcasts"
        + " through the SDK');\n"
        + "        err.code = 'METHOD_FORBIDDEN';\n"
        + "        throw err;\n"
        + "      }\n"
        + "      return octraProvider.request({method: m, params});\n"
        + "    },\n"
        + "    on(event, cb) { if (!_walletListeners[event]) _walletListeners[event]=[];"
        + " _walletListeners[event].push(cb); return this; },\n"
        + "    off(event, cb) { if (_walletListeners[event])"
        + " _walletListeners[event]=_walletListeners[event].filter(c=>c!==cb); return this; },\n"
        + "    once(event, cb) { const self = this; const wrap = d => { self.off(event, wrap);"
        + " cb(d); }; return this.on(event, wrap); },\n"
        + "  };\n"
        + "  try {\n"
        + "    if (!window.wallet) {\n"
        + "      Object.defineProperty(window, 'wallet', {\n"
        + "        value: Object.freeze(walletProvider), writable: true, configurable: true });\n"
        + "    }\n"
        + "  } catch (e) { }\n"
        + "  window.dispatchEvent(new CustomEvent('octra:wallet#initialized',\n"
        + "    {detail: {provider: window.wallet || walletProvider}}));\n"
        + "\n"
        + "  Object.defineProperty(window, 'octra', {\n"
        + "    value: Object.freeze(octraProvider),\n"
        + "    writable: false, configurable: false,\n"
        + "  });\n"
        + "  window.dispatchEvent(new Event('octra#initialized'));\n"
        + "})();";
  }

  // ─── oct:// circle protocol (direct RPC, no local server) ────────────

  private boolean isOctUrl(String url) {
    return OctUrlParser.isOctUrl(url);
  }

  private String[] parseOctUrl(String url) {
    return OctUrlParser.parseOctUrl(url);
  }

  private boolean isTextMime(String mime) {
    return OctUrlParser.isTextMime(mime);
  }

  private WebResourceResponse octError(int code, String reason) {
    Map<String, String> headers = new HashMap<>();
    headers.put("Cache-Control", "no-store");
    byte[] body;
    try {
      body = reason.getBytes("UTF-8");
    } catch (java.io.UnsupportedEncodingException impossible) {
      body = new byte[0];
    }
    return new WebResourceResponse(
        "text/plain", "utf-8", code, reason, headers, new java.io.ByteArrayInputStream(body));
  }

  private WebResourceResponse fetchOctResource(String url) {
    try {
      String[] parts = parseOctUrl(url);
      if (parts[0].isEmpty()) {
        return octError(400, "circle_id required");
      }
      JSONObject asset = OctraRpcClient.getInstance().circleAsset(getRpcUrl(), parts[0], parts[1]);
      if (asset == null || asset.has("error")) {
        return octError(404, "Circle asset not found");
      }
      String mime = asset.optString("content_type", "application/octet-stream");
      int semi = mime.indexOf(';');
      if (semi != -1) {
        mime = mime.substring(0, semi).trim();
      }
      if (mime.isEmpty()) {
        mime = "application/octet-stream";
      }
      byte[] raw = OctraNative.getInstance().base64Decode(asset.optString("body_b64", ""));
      if (raw == null) {
        raw = new byte[0];
      }
      if (OctUrlParser.isTooLarge(raw.length)) {
        return octError(
            413,
            "Asset too large ("
                + raw.length
                + " bytes, limit "
                + OctUrlParser.MAX_DIRECT_BYTES
                + ")");
      }
      Map<String, String> headers = new HashMap<>();
      headers.put("Cache-Control", "no-store");
      headers.put("X-Content-Type-Options", "nosniff");
      String encoding = isTextMime(mime) ? "utf-8" : null;
      return new WebResourceResponse(
          mime, encoding, 200, "OK", headers, new java.io.ByteArrayInputStream(raw));
    } catch (Exception e) {
      Log.w(TAG, "Circle fetch failed: " + e.getMessage());
      return octError(500, "Circle fetch failed");
    }
  }

  private byte[] readAllBytes(java.io.InputStream in) throws java.io.IOException {
    java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
    byte[] buf = new byte[8192];
    int n;
    while ((n = in.read(buf)) != -1) {
      out.write(buf, 0, n);
    }
    return out.toByteArray();
  }

  private void loadOctUrl(final String octUrl) {
    urlInput.setText(octUrl);
    progressBar.setVisibility(View.VISIBLE);
    ((OctraWalletApplication) getApplication())
        .getIoExecutor()
        .execute(
            () -> {
              final WebResourceResponse res = fetchOctResource(octUrl);
              runOnUiThread(
                  () -> {
                    if (destroyed) return;
                    progressBar.setVisibility(View.GONE);
                    int code = res != null ? res.getStatusCode() : 500;
                    if (code == 413) {
                      Toast.makeText(
                              this,
                              "Page too large to render directly "
                                  + "(over 8 MB). Try a smaller circle page.",
                              Toast.LENGTH_LONG)
                          .show();
                      showStartpage();
                      return;
                    }
                    if (res == null || code < 200 || code >= 300) {
                      Toast.makeText(
                              this,
                              "Cannot open " + octUrl + " (circle not found, code " + code + ")",
                              Toast.LENGTH_LONG)
                          .show();
                      showStartpage();
                      return;
                    }
                    try {
                      byte[] raw = readAllBytes(res.getData());
                      String mime = res.getMimeType();
                      if (mime != null && isTextMime(mime)) {
                        hideStartpage();
                        String text = new String(raw, java.nio.charset.StandardCharsets.UTF_8);
                        webView.loadDataWithBaseURL(octUrl, text, mime, "UTF-8", null);
                      } else if (mime != null && mime.startsWith("image/")) {
                        hideStartpage();
                        String b64 = OctraNative.getInstance().base64Encode(raw);
                        webView.loadUrl("data:" + mime + ";base64," + b64);
                      } else {
                        Toast.makeText(this, "Preview not supported for " + mime, Toast.LENGTH_LONG)
                            .show();
                        showStartpage();
                      }
                    } catch (Exception e) {
                      Log.w(TAG, "Circle render failed: " + e.getMessage());
                      Toast.makeText(this, "Failed to render circle page", Toast.LENGTH_LONG)
                          .show();
                      showStartpage();
                    }
                  });
            });
  }
}
