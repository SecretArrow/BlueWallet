package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

public class WalletsActivity extends BaseTxActivity {

    private RecyclerView walletsList;
    private WalletIdAdapter adapter;
    private List<String> walletIds;

    private final ActivityResultLauncher<Intent> deleteWalletLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() != RESULT_OK || result.getData() == null) {
                    return;
                }
                String walletId = result.getData().getStringExtra(ConfirmDeleteWalletActivity.EXTRA_WALLET_ID);
                if (walletId == null || walletId.trim().isEmpty()) {
                    return;
                }
                deleteWalletAndRefresh(walletId.trim());
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_wallets);
        setupToolbar(R.id.wallets_toolbar, "Wallets");

        walletsList = findViewById(R.id.wallets_list);
        walletsList.setLayoutManager(new LinearLayoutManager(this));
        walletIds = new ArrayList<>(WalletProfileStore.getWalletIds(this));
        adapter = new WalletIdAdapter(walletIds);
        walletsList.setAdapter(adapter);
    }

    private void confirmRemoveWallet(String walletId, int position) {
        List<String> allIds = WalletProfileStore.getWalletIds(this);
        if (allIds.size() <= 1) {
            ErrorDisplayHelper.showWarning(walletsList, "Cannot remove the last wallet");
            return;
        }
        Intent intent = new Intent(this, ConfirmDeleteWalletActivity.class);
        intent.putExtra(ConfirmDeleteWalletActivity.EXTRA_WALLET_ID, walletId);
        deleteWalletLauncher.launch(intent);
    }

    private void deleteWalletAndRefresh(String walletId) {
        try {
            File walletDir = WalletProfileStore.getWalletDir(this, walletId);
            deleteDir(walletDir);
        } catch (Exception ignored) {
        }
        WalletAddressStore.removeAddress(getApplicationContext(), walletId);
        WalletProfileStore.removeWallet(this, walletId);
        walletIds.clear();
        walletIds.addAll(WalletProfileStore.getWalletIds(this));
        adapter.notifyDataSetChanged();
        ErrorDisplayHelper.showInfo(walletsList, "Wallet removed");
    }

    private void deleteDir(File dir) {
        if (dir == null || !dir.exists()) return;
        File[] files = dir.listFiles();
        if (files != null) {
            for (File f : files) {
                if (f.isDirectory()) deleteDir(f);
                else f.delete();
            }
        }
        dir.delete();
    }

    private final class WalletIdAdapter extends RecyclerView.Adapter<WalletIdAdapter.VH> {
        private final List<String> ids;

        WalletIdAdapter(List<String> ids) {
            this.ids = ids;
        }

        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(parent.getContext())
                    .inflate(R.layout.item_wallet, parent, false);
            return new VH(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            String walletId = ids.get(position);
            holder.nameText.setText(walletId);

            String address = WalletAddressStore.getAddress(getApplicationContext(), walletId);
            if (address != null && !address.isEmpty()) {
                holder.addressText.setVisibility(View.VISIBLE);
                holder.addressText.setText(address);
            } else {
                holder.addressText.setVisibility(View.GONE);
            }

            // Show/hide delete button (can't delete the last wallet)
            boolean canDelete = ids.size() > 1;
            holder.deleteButton.setVisibility(canDelete ? View.VISIBLE : View.GONE);
            holder.deleteButton.setOnClickListener(v -> confirmRemoveWallet(walletId, position));

            holder.itemView.setOnClickListener(v -> {
                Intent intent = new Intent(WalletsActivity.this, ViewKeysActivity.class);
                intent.putExtra("wallet_id", walletId);
                startActivity(intent);
            });
        }

        @Override
        public int getItemCount() {
            return ids.size();
        }

        final class VH extends RecyclerView.ViewHolder {
            final TextView nameText;
            final TextView addressText;
            final ImageButton deleteButton;
            VH(View itemView) {
                super(itemView);
                nameText = itemView.findViewById(R.id.wallet_name_text);
                addressText = itemView.findViewById(R.id.wallet_address_text);
                deleteButton = itemView.findViewById(R.id.wallet_delete_button);
            }
        }
    }
}
