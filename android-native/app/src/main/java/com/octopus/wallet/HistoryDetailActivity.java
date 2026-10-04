package com.octopus.wallet;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.PopupMenu;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.coordinatorlayout.widget.CoordinatorLayout;

import com.google.android.material.floatingactionbutton.FloatingActionButton;

import org.json.JSONObject;

import java.text.NumberFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class HistoryDetailActivity extends AppCompatActivity {

    private String fullHash = "";
    private String explorerBaseUrl = "";

    @Override
    protected void onResume() {
        super.onResume();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    protected void onPause() {
        super.onPause();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    public void onUserInteraction() {
        super.onUserInteraction();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_history_detail);

        androidx.appcompat.widget.Toolbar toolbar = findViewById(R.id.detail_toolbar);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setDisplayShowHomeEnabled(true);
        }
        toolbar.setNavigationOnClickListener(v -> finish());

        // Resolve explorer URL from active node profile
        resolveExplorerUrl();

        // Find views
        TextView hashText = findViewById(R.id.detail_hash_text);
        TextView statusText = findViewById(R.id.detail_status_text);
        TextView fromText = findViewById(R.id.detail_from_text);
        TextView toText = findViewById(R.id.detail_to_text);
        TextView amountText = findViewById(R.id.detail_amount_text);
        TextView amountRawText = findViewById(R.id.detail_amount_raw_text);
        TextView typeText = findViewById(R.id.detail_type_text);
        TextView epochText = findViewById(R.id.detail_epoch_text);
        TextView nonceText = findViewById(R.id.detail_nonce_text);
        TextView feeText = findViewById(R.id.detail_fee_text);
        TextView timeText = findViewById(R.id.detail_time_text);

        String txJson = getIntent().getStringExtra("tx_json");
        if (txJson == null) txJson = "{}";

        try {
            JSONObject tx = new JSONObject(txJson);

            // Hash
            String hash = tx.optString("hash", tx.optString("tx_hash", "-"));
            fullHash = (hash == null || hash.trim().isEmpty()) ? "" : hash.trim();
            hashText.setText(fullHash.isEmpty() ? "-" : fullHash);

            // Status
            String status = resolveStatus(tx);
            statusText.setText(formatStatus(status));

            // From / To
            String from = firstNonEmpty(tx.optString("from", ""), tx.optString("from_", ""), tx.optString("sender", ""));
            String to = firstNonEmpty(tx.optString("to", ""), tx.optString("to_", ""), tx.optString("recipient", ""), tx.optString("receiver", ""));
            fromText.setText(from.isEmpty() ? "-" : from);
            toText.setText(to.isEmpty() ? "-" : to);

            // Amount
            String rawAmount = firstNonEmpty(tx.optString("amount_raw", ""), tx.optString("value_raw", ""), tx.optString("raw_amount", ""), tx.optString("value", ""), tx.optString("amount", ""));
            amountText.setText(formatAmount(rawAmount) + " OCT");

            // Amount (raw)
            long rawValue = parseRawAmount(rawAmount);
            amountRawText.setText(NumberFormat.getNumberInstance(Locale.US).format(rawValue));

            // Type
            String type = firstNonEmpty(tx.optString("op_type", ""), tx.optString("type", ""), tx.optString("tx_type", ""));
            typeText.setText(type.isEmpty() ? "standard" : type.toLowerCase(Locale.US));

            // Epoch
            long epoch = tx.optLong("epoch", tx.optLong("block_epoch", -1));
            epochText.setText(epoch >= 0 ? String.valueOf(epoch) : "-");

            // Nonce
            long nonce = tx.optLong("nonce", tx.optLong("tx_nonce", -1));
            nonceText.setText(nonce >= 0 ? String.valueOf(nonce) : "-");

            // Fee (OU)
            String feeRaw = firstNonEmpty(tx.optString("fee", ""), tx.optString("ou", ""), tx.optString("fee_raw", ""), tx.optString("ou_fee", ""));
            if (!feeRaw.isEmpty()) {
                feeText.setText(formatAmount(feeRaw) + " OCT");
            } else {
                feeText.setText("-");
            }

            // Time
            long timeMillis = resolveTimeMillis(tx);
            if (timeMillis > 0) {
                SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault());
                timeText.setText(sdf.format(new Date(timeMillis)));
            } else {
                timeText.setText("--:--");
            }

        } catch (Exception e) {
            hashText.setText("-");
            statusText.setText("Pending");
            fromText.setText("-");
            toText.setText("-");
            amountText.setText("0 OCT");
            amountRawText.setText("0");
            typeText.setText("-");
            epochText.setText("-");
            nonceText.setText("-");
            feeText.setText("-");
            timeText.setText("--:--");
        }

        // FAB menu
        FloatingActionButton fab = findViewById(R.id.detail_fab);
        fab.setOnClickListener(v -> {
            PopupMenu popup = new PopupMenu(this, v);
            popup.getMenu().add(0, 1, 0, "Copy Hash");
            popup.getMenu().add(0, 2, 1, "View in Browser");
            popup.setOnMenuItemClickListener(item -> {
                if (item.getItemId() == 1) {
                    copyHash();
                    return true;
                }
                if (item.getItemId() == 2) {
                    viewInBrowser();
                    return true;
                }
                return false;
            });
            popup.show();
        });
    }

    private void resolveExplorerUrl() {
        try {
            List<NodeProfileStore.NodeProfile> profiles = NodeProfileStore.getProfiles(this);
            String selectedName = NodeProfileStore.getSelectedName(this);
            NodeProfileStore.NodeProfile active = NodeProfileStore.findByName(profiles, selectedName);
            if (active == null && !profiles.isEmpty()) {
                active = profiles.get(0);
            }
            if (active != null && active.explorerUrl != null && !active.explorerUrl.isEmpty()) {
                explorerBaseUrl = active.explorerUrl;
            } else {
                explorerBaseUrl = "https://devnet.octrascan.io";
            }
        } catch (Exception e) {
            explorerBaseUrl = "https://devnet.octrascan.io";
        }
    }

    private void copyHash() {
        if (fullHash.isEmpty() || "-".equals(fullHash)) {
            Toast.makeText(this, "Hash is empty", Toast.LENGTH_SHORT).show();
            return;
        }
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard != null) {
            clipboard.setPrimaryClip(ClipData.newPlainText("Transaction Hash", fullHash));
        }
        Toast.makeText(this, "Hash copied", Toast.LENGTH_SHORT).show();
    }

    private void viewInBrowser() {
        if (fullHash.isEmpty() || "-".equals(fullHash)) {
            Toast.makeText(this, "Hash is empty", Toast.LENGTH_SHORT).show();
            return;
        }
        String base = explorerBaseUrl.endsWith("/") ? explorerBaseUrl : explorerBaseUrl + "/";
        String url = base + "tx/" + fullHash;
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            startActivity(intent);
        } catch (Exception e) {
            Toast.makeText(this, "Unable to open browser", Toast.LENGTH_SHORT).show();
        }
    }

    private String resolveStatus(JSONObject tx) {
        String status = firstNonEmpty(
                tx.optString("status", ""),
                tx.optString("state", ""),
                tx.optString("tx_status", ""),
                tx.optString("result", ""),
                tx.optString("final_status", ""));
        if (status.isEmpty()) {
            if (tx.has("error") || tx.has("reject_reason") || tx.has("rejection_reason")) {
                return "rejected";
            }
            return "pending";
        }
        String n = status.trim().toLowerCase(Locale.US);
        if (n.contains("reject") || n.contains("fail") || n.contains("error")) return "rejected";
        if (n.contains("confirm") || n.contains("success") || n.contains("ok") || n.contains("final")) return "confirmed";
        if (n.contains("pend") || n.contains("queue") || n.contains("mempool")) return "pending";
        return n;
    }

    private long resolveTimeMillis(JSONObject tx) {
        long localTs = tx.optLong("local_ts", 0L);
        if (localTs > 0L) return localTs;
        String tsValue = firstNonEmpty(
                tx.optString("timestamp", ""),
                tx.optString("time", ""),
                tx.optString("created_at", ""),
                tx.optString("created", ""));
        if (tsValue.isEmpty()) return 0L;
        try {
            double ts = Double.parseDouble(tsValue.trim());
            if (ts <= 0d) return 0L;
            return ts > 1_000_000_000_000d ? (long) ts : (long) (ts * 1000d);
        } catch (Exception e) {
            return 0L;
        }
    }

    private String firstNonEmpty(String... values) {
        for (String v : values) {
            if (v != null && !v.trim().isEmpty()) return v;
        }
        return "";
    }

    private String formatAmount(String rawAmount) {
        long raw = parseRawAmount(rawAmount);
        try {
            java.math.BigDecimal value = java.math.BigDecimal.valueOf(raw, 6)
                    .setScale(6, java.math.RoundingMode.DOWN).stripTrailingZeros();
            if (value.scale() < 0) value = value.setScale(0);
            return value.toPlainString();
        } catch (Exception e) {
            return "0";
        }
    }

    private long parseRawAmount(String raw) {
        if (raw == null || raw.trim().isEmpty()) return 0L;
        try {
            return Long.parseLong(raw.trim());
        } catch (Exception e) {
            return 0L;
        }
    }

    private String formatStatus(String status) {
        if (status == null || status.trim().isEmpty()) return "Pending";
        String n = status.trim().toLowerCase(Locale.US);
        if ("confirmed".equals(n)) return "Confirmed";
        if ("rejected".equals(n)) return "Rejected";
        if ("pending".equals(n)) return "Pending";
        return Character.toUpperCase(n.charAt(0)) + n.substring(1);
    }
}
