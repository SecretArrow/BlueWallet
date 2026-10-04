package com.octopus.wallet;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.button.MaterialButton;

import java.util.ArrayList;
import java.util.List;

/**
 * Activity to display data usage statistics and history.
 */
public class DataUsageActivity extends AppCompatActivity {

    private TextView totalDataText;
    private TextView rxDataText;
    private TextView txDataText;
    private TextView sessionDataText;
    private TextView emptyText;
    private RecyclerView historyList;
    private MaterialButton clearHistoryButton;

    private DataUsageTracker tracker;
    private DataUsageAdapter adapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_data_usage);

        tracker = new DataUsageTracker(this);

        initViews();
        setupToolbar();
        loadData();
    }

    private void initViews() {
        totalDataText = findViewById(R.id.total_data_text);
        rxDataText = findViewById(R.id.rx_data_text);
        txDataText = findViewById(R.id.tx_data_text);
        sessionDataText = findViewById(R.id.session_data_text);
        emptyText = findViewById(R.id.empty_text);
        historyList = findViewById(R.id.history_list);
        clearHistoryButton = findViewById(R.id.clear_history_button);

        historyList.setLayoutManager(new LinearLayoutManager(this));

        clearHistoryButton.setOnClickListener(v -> showClearConfirmation());
    }

    private void setupToolbar() {
        MaterialToolbar toolbar = findViewById(R.id.toolbar);
        toolbar.setNavigationOnClickListener(v -> finish());
    }

    private void loadData() {
        // Load total usage
        DataUsageTracker.DataUsage totalUsage = tracker.getTotalUsage();
        totalDataText.setText(totalUsage.getFormattedTotal());
        rxDataText.setText(totalUsage.getFormattedRx());
        txDataText.setText(totalUsage.getFormattedTx());

        // Load session usage
        DataUsageTracker.DataUsage sessionUsage = tracker.getSessionUsage();
        sessionDataText.setText(sessionUsage.getFormattedTotal());

        // Load history
        List<DataUsageTracker.DataUsageEntry> entries = tracker.getUsageHistoryList();
        
        if (entries.isEmpty()) {
            emptyText.setVisibility(View.VISIBLE);
            historyList.setVisibility(View.GONE);
        } else {
            emptyText.setVisibility(View.GONE);
            historyList.setVisibility(View.VISIBLE);
            adapter = new DataUsageAdapter(entries);
            historyList.setAdapter(adapter);
        }
    }

    private void showClearConfirmation() {
        new AlertDialog.Builder(this)
            .setTitle("Clear History")
            .setMessage("Are you sure you want to clear all data usage history?")
            .setPositiveButton("Clear", (dialog, which) -> {
                tracker.clearHistory();
                loadData();
                Toast.makeText(this, "History cleared", Toast.LENGTH_SHORT).show();
            })
            .setNegativeButton("Cancel", null)
            .show();
    }

    /**
     * RecyclerView adapter for data usage entries.
     */
    private class DataUsageAdapter extends RecyclerView.Adapter<DataUsageAdapter.ViewHolder> {
        private final List<DataUsageTracker.DataUsageEntry> entries;

        DataUsageAdapter(List<DataUsageTracker.DataUsageEntry> entries) {
            this.entries = entries;
        }

        @Override
        public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(parent.getContext())
                .inflate(R.layout.item_data_usage, parent, false);
            return new ViewHolder(view);
        }

        @Override
        public void onBindViewHolder(ViewHolder holder, int position) {
            DataUsageTracker.DataUsageEntry entry = entries.get(position);
            
            holder.typeText.setText(entry.type);
            holder.descriptionText.setText(entry.description);
            holder.timeText.setText(entry.getFormattedTime());
            holder.totalText.setText(entry.getFormattedTotal());
            holder.rxText.setText(entry.getFormattedRx());
            holder.txText.setText(entry.getFormattedTx());

            // Set icon based on type
            int iconRes = getIconForType(entry.type);
            holder.typeIcon.setImageResource(iconRes);
        }

        @Override
        public int getItemCount() {
            return entries.size();
        }

        private int getIconForType(String type) {
            if (type == null) return R.drawable.ic_network;
            
            switch (type.toLowerCase()) {
                case "send":
                case "transaction":
                    return R.drawable.ic_send;
                case "receive":
                    return R.drawable.ic_receive;
                case "balance":
                case "fetch":
                    return R.drawable.ic_refresh;
                case "contract":
                case "token":
                    return R.drawable.ic_token;
                default:
                    return R.drawable.ic_network;
            }
        }

        class ViewHolder extends RecyclerView.ViewHolder {
            final ImageView typeIcon;
            final TextView typeText;
            final TextView descriptionText;
            final TextView timeText;
            final TextView totalText;
            final TextView rxText;
            final TextView txText;

            ViewHolder(View itemView) {
                super(itemView);
                typeIcon = itemView.findViewById(R.id.usage_type_icon);
                typeText = itemView.findViewById(R.id.usage_type_text);
                descriptionText = itemView.findViewById(R.id.usage_description_text);
                timeText = itemView.findViewById(R.id.usage_time_text);
                totalText = itemView.findViewById(R.id.usage_total_text);
                rxText = itemView.findViewById(R.id.usage_rx_text);
                txText = itemView.findViewById(R.id.usage_tx_text);
            }
        }
    }
}
