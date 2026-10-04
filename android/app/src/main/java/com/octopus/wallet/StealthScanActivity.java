package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.CheckBox;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.button.MaterialButton;

import org.json.JSONArray;
import org.json.JSONObject;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;

public class StealthScanActivity extends BaseTxActivity {
    private final List<StealthOutputItem> items = new ArrayList<>();
    private RecyclerView recyclerView;
    private TextView statusText;
    private TextView emptyText;
    private MaterialButton claimButton;
    private OutputsAdapter adapter;
    private volatile boolean loading = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_stealth_scan);
        setupToolbar(R.id.stealth_scan_toolbar, "Stealth Outputs");

        recyclerView = findViewById(R.id.stealth_scan_list);
        recyclerView.setLayoutManager(new LinearLayoutManager(this));
        statusText = findViewById(R.id.stealth_scan_status);
        emptyText = findViewById(R.id.stealth_scan_empty);
        claimButton = findViewById(R.id.stealth_scan_claim_button);

        adapter = new OutputsAdapter();
        recyclerView.setAdapter(adapter);

        claimButton.setOnClickListener(v -> submitClaim());
        refreshClaimButtonState();
        refreshOutputs();
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.stealth_scan_toolbar_menu, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == R.id.action_refresh) {
            refreshOutputs();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    private void refreshOutputs() {
        if (loading) {
            return;
        }
        loading = true;
        statusText.setText("Refreshing stealth outputs...");

        ioExecutor().execute(() -> {
            List<StealthOutputItem> scanned = new ArrayList<>();
            Exception failure = null;
            try {
                JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
                if (info.has("error")) {
                    throw new IllegalStateException(info.optString("error", "Wallet info unavailable"));
                }
                String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
                String address = info.optString("address", "");
                JSONObject root = fetchStealthOutputs(rpcUrl, address);
                scanned.addAll(parseOutputs(root));
            } catch (Exception e) {
                failure = e;
            }

            Exception finalFailure = failure;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                loading = false;
                if (finalFailure != null) {
                    showFailurePopup(finalFailure);
                    statusText.setText("Refresh failed");
                    emptyText.setVisibility(items.isEmpty() ? View.VISIBLE : View.GONE);
                    return;
                }

                items.clear();
                items.addAll(scanned);
                adapter.notifyDataSetChanged();
                emptyText.setVisibility(items.isEmpty() ? View.VISIBLE : View.GONE);
                statusText.setText(items.isEmpty()
                        ? "No claimable outputs found"
                        : ("Found " + items.size() + " output(s)"));
                refreshClaimButtonState();
            });
        });
    }

    private JSONObject fetchStealthOutputs(String rpcUrl, String address) throws Exception {
        org.json.JSONArray outputs = repo().fetchStealthOutputs(rpcUrl, address);
        // Wrap into the envelope format expected by parseOutputs()
        JSONObject result = new JSONObject();
        result.put("outputs", outputs);
        JSONObject envelope = new JSONObject();
        envelope.put("result", result);
        return envelope;
    }

    private List<StealthOutputItem> parseOutputs(JSONObject root) {
        List<StealthOutputItem> out = new ArrayList<>();
        if (root == null || root.isNull("result")) {
            return out;
        }
        JSONObject result = root.optJSONObject("result");
        if (result == null) {
            return out;
        }

        JSONArray array = firstArray(result,
                "outputs",
                "stealth_outputs",
                "items",
                "list",
                "transactions",
                "history",
                "txs");

        if (array == null) {
            return out;
        }

        for (int i = 0; i < array.length(); i++) {
            JSONObject item = array.optJSONObject(i);
            if (item == null) continue;

            String amountRaw = firstNonEmpty(
                    item.optString("amount_raw", ""),
                    item.optString("value_raw", ""),
                    item.optString("amount", ""),
                    item.optString("value", "")
            );
            long amount = parseRawAmount(amountRaw);
            if (amount <= 0L) {
                continue;
            }

            String outputId = firstNonEmpty(
                    item.optString("output_id", ""),
                    item.optString("id", ""),
                    item.optString("tx_hash", "") + ":" + item.optString("index", "")
            );
            String txHash = firstNonEmpty(item.optString("tx_hash", ""), item.optString("hash", ""));

            StealthOutputItem row = new StealthOutputItem();
            row.outputId = outputId.isEmpty() ? ("out_" + i) : outputId;
            row.txHash = txHash;
            row.amountRaw = String.valueOf(amount);
            row.selected = false;
            out.add(row);
        }
        return out;
    }

    private JSONArray firstArray(JSONObject object, String... keys) {
        if (object == null || keys == null) return null;
        for (String key : keys) {
            JSONArray value = object.optJSONArray(key);
            if (value != null) return value;
        }
        return null;
    }

    private String firstNonEmpty(String... values) {
        if (values == null) return "";
        for (String value : values) {
            if (value != null && !value.trim().isEmpty()) {
                return value.trim();
            }
        }
        return "";
    }

    private long parseRawAmount(String raw) {
        try {
            return Math.max(0L, Long.parseLong(raw == null ? "0" : raw.trim()));
        } catch (Exception ignored) {
            return 0L;
        }
    }

    private void refreshClaimButtonState() {
        int selectedCount = 0;
        for (StealthOutputItem item : items) {
            if (item.selected) selectedCount++;
        }
        claimButton.setEnabled(selectedCount > 0);
        claimButton.setText(selectedCount > 0
                ? ("Claim Selected (" + selectedCount + ")")
                : "Claim Selected");
    }

    private void submitClaim() {
        JSONArray selected = new JSONArray();
        int selectedCount = 0;
        for (StealthOutputItem item : items) {
            if (!item.selected) continue;
            selectedCount++;
            JSONObject o = new JSONObject();
            try {
                o.put("output_id", item.outputId);
                o.put("amount_raw", item.amountRaw);
                o.put("tx_hash", item.txHash == null ? "" : item.txHash);
            } catch (Exception ignored) {
            }
            selected.put(o);
        }

        if (selectedCount <= 0) {
            showError("Select at least one output");
            return;
        }

        StealthClaimService.startClaiming(this, selected);
        showSuccess("Claim queued in background");
        for (StealthOutputItem item : items) {
            item.selected = false;
        }
        adapter.notifyDataSetChanged();
        refreshClaimButtonState();
    }

    private String formatAmount(String raw) {
        try {
            long value = parseRawAmount(raw);
            BigDecimal bd = BigDecimal.valueOf(value, 6)
                    .setScale(6, RoundingMode.DOWN)
                    .stripTrailingZeros();
            if (bd.scale() < 0) bd = bd.setScale(0);
            return bd.toPlainString();
        } catch (Exception ignored) {
            return "0";
        }
    }

    private void showFailurePopup(Exception error) {
        if (isFinishing() || isDestroyed()) return;
        String message = AppErrorCode.fromException("StealthScan", "Stealth scan failed", error);
        Intent intent = new Intent(this, ConfirmActionActivity.class);
        intent.putExtra(ConfirmActionActivity.EXTRA_TITLE, "Program Error");
        intent.putExtra(ConfirmActionActivity.EXTRA_MESSAGE, message);
        intent.putExtra(ConfirmActionActivity.EXTRA_POSITIVE, "OK");
        intent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE, "");
        startActivity(intent);
    }

    private final class OutputsAdapter extends RecyclerView.Adapter<OutputsAdapter.VH> {
        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(StealthScanActivity.this)
                    .inflate(R.layout.item_stealth_scan_output, parent, false);
            return new VH(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            StealthOutputItem item = items.get(position);

            holder.check.setOnCheckedChangeListener(null);
            holder.check.setChecked(item.selected);
            holder.check.setOnCheckedChangeListener((buttonView, isChecked) -> {
                item.selected = isChecked;
                refreshClaimButtonState();
            });

            holder.title.setText("Output " + item.outputId + " • " + formatAmount(item.amountRaw) + " OCT");
            holder.subtitle.setText("Tx: " + (item.txHash == null || item.txHash.isEmpty() ? "-" : item.txHash));

            holder.itemView.setOnClickListener(v -> {
                item.selected = !item.selected;
                holder.check.setChecked(item.selected);
                refreshClaimButtonState();
            });
        }

        @Override
        public int getItemCount() {
            return items.size();
        }

        final class VH extends RecyclerView.ViewHolder {
            final CheckBox check;
            final TextView title;
            final TextView subtitle;

            VH(View itemView) {
                super(itemView);
                check = itemView.findViewById(R.id.stealth_output_check);
                title = itemView.findViewById(R.id.stealth_output_title);
                subtitle = itemView.findViewById(R.id.stealth_output_subtitle);
            }
        }
    }

    private static final class StealthOutputItem {
        String outputId;
        String txHash;
        String amountRaw;
        boolean selected;
    }
}
