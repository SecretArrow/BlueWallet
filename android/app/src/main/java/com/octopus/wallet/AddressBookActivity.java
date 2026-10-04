package com.octopus.wallet;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.TextView;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.floatingactionbutton.FloatingActionButton;

import java.util.ArrayList;
import java.util.List;

/**
 * Address Book — view, add, edit, and delete saved wallet addresses.
 * Launched from the Send screen (pick mode) or Settings (manage mode).
 *
 * Extras in:
 *   EXTRA_PICK_MODE = true  →  tapping an entry returns RESULT_OK with RESULT_ADDRESS
 *
 * Extras out (pick mode):
 *   RESULT_ADDRESS = selected address string
 */
public class AddressBookActivity extends BaseTxActivity {

    public static final String EXTRA_PICK_MODE    = "pick_mode";
    public static final String RESULT_ADDRESS     = "selected_address";

    private final List<AddressBookStore.Entry> displayedEntries = new ArrayList<>();
    private boolean pickMode = false;
    private AddressAdapter adapter;
    private RecyclerView recyclerView;
    private TextView emptyText;
    private AddressBookStore.Entry pendingDeleteEntry;

    private final ActivityResultLauncher<Intent> entryEditorLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() != RESULT_OK || result.getData() == null) {
                    return;
                }
                Intent data = result.getData();
                boolean editing = data.getBooleanExtra(AddressBookEntryActivity.EXTRA_EDITING, false);
                String entryId = safe(data.getStringExtra(AddressBookEntryActivity.EXTRA_ENTRY_ID));
                String label = safe(data.getStringExtra(AddressBookEntryActivity.EXTRA_LABEL)).trim();
                String address = safe(data.getStringExtra(AddressBookEntryActivity.EXTRA_ADDRESS)).trim();
                if (address.isEmpty() || !address.startsWith("oct") || address.length() != 47) {
                    showError("Invalid Octra address format");
                    return;
                }
                String displayLabel = label.isEmpty() ? shortenAddress(address) : label;
                if (editing) {
                    AddressBookStore.updateLabel(this, entryId, displayLabel);
                } else {
                    AddressBookStore.addEntry(this, displayLabel, address);
                }
                loadEntries();
            });

    private final ActivityResultLauncher<Intent> confirmLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                AddressBookStore.Entry entry = pendingDeleteEntry;
                pendingDeleteEntry = null;
                if (entry == null) return;
                if (result.getResultCode() == RESULT_OK) {
                    AddressBookStore.deleteEntry(this, entry.id);
                    loadEntries();
                    showSuccess("Address removed");
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_address_book);
        pickMode = getIntent().getBooleanExtra(EXTRA_PICK_MODE, false);
        setupToolbar(R.id.address_book_toolbar, pickMode ? "Select Address" : "Address Book");

        recyclerView = findViewById(R.id.address_book_recycler);
        emptyText    = findViewById(R.id.address_book_empty);
        FloatingActionButton fab = findViewById(R.id.address_book_fab);

        recyclerView.setLayoutManager(new LinearLayoutManager(this));
        adapter = new AddressAdapter();
        recyclerView.setAdapter(adapter);

        EditText searchInput = findViewById(R.id.address_book_search);
        if (searchInput != null) {
            searchInput.addTextChangedListener(new TextWatcher() {
                @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
                @Override public void afterTextChanged(Editable s) {}
                @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                    filterEntries(s == null ? "" : s.toString());
                }
            });
        }

        fab.setOnClickListener(v -> openEntryEditor(null));
        loadEntries();
    }

    @Override
    protected void onResume() {
        super.onResume();
        loadEntries();
    }

    // ── Data ───────────────────────────────────────────────────────────────

    private void loadEntries() {
        List<AddressBookStore.Entry> all = AddressBookStore.getEntries(this);
        displayedEntries.clear();
        displayedEntries.addAll(all);
        adapter.notifyDataSetChanged();
        emptyText.setVisibility(displayedEntries.isEmpty() ? View.VISIBLE : View.GONE);
        recyclerView.setVisibility(displayedEntries.isEmpty() ? View.GONE : View.VISIBLE);
    }

    private void filterEntries(String query) {
        String q = query.trim().toLowerCase();
        List<AddressBookStore.Entry> all = AddressBookStore.getEntries(this);
        displayedEntries.clear();
        if (q.isEmpty()) {
            displayedEntries.addAll(all);
        } else {
            for (AddressBookStore.Entry e : all) {
                if (e.label.toLowerCase().contains(q) || e.address.toLowerCase().contains(q)) {
                    displayedEntries.add(e);
                }
            }
        }
        adapter.notifyDataSetChanged();
        emptyText.setVisibility(displayedEntries.isEmpty() ? View.VISIBLE : View.GONE);
        recyclerView.setVisibility(displayedEntries.isEmpty() ? View.GONE : View.VISIBLE);
    }

    private void openEntryEditor(AddressBookStore.Entry existing) {
        Intent intent = new Intent(this, AddressBookEntryActivity.class);
        boolean editing = existing != null;
        intent.putExtra(AddressBookEntryActivity.EXTRA_EDITING, editing);
        if (editing) {
            intent.putExtra(AddressBookEntryActivity.EXTRA_ENTRY_ID, safe(existing.id));
            intent.putExtra(AddressBookEntryActivity.EXTRA_LABEL, safe(existing.label));
            intent.putExtra(AddressBookEntryActivity.EXTRA_ADDRESS, safe(existing.address));
            intent.putExtra(AddressBookEntryActivity.EXTRA_ADDRESS_LOCKED,
                    existing.id != null && !existing.id.isEmpty());
        }
        entryEditorLauncher.launch(intent);
    }

    private void showDeleteConfirm(AddressBookStore.Entry entry) {
        pendingDeleteEntry = entry;
        Intent intent = new Intent(this, ConfirmActionActivity.class);
        intent.putExtra(ConfirmActionActivity.EXTRA_TITLE, "Delete Address");
        intent.putExtra(ConfirmActionActivity.EXTRA_MESSAGE,
                "Remove \"" + entry.label + "\" from your address book?");
        intent.putExtra(ConfirmActionActivity.EXTRA_POSITIVE, "Delete");
        intent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE, "Cancel");
        confirmLauncher.launch(intent);
    }

    private void onEntryClicked(AddressBookStore.Entry entry) {
        if (pickMode) {
            Intent result = new Intent();
            result.putExtra(RESULT_ADDRESS, entry.address);
            setResult(RESULT_OK, result);
            finish();
        } else {
            // Copy address to clipboard
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (cm != null) {
                cm.setPrimaryClip(ClipData.newPlainText("Octra Address", entry.address));
                scheduleClipboardClear(entry.address);
            }
            showSuccess("Address copied to clipboard");
        }
    }

    // ── Clipboard auto-clear (30 s) ────────────────────────────────────────

    private void scheduleClipboardClear(String copiedValue) {
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            try {
                ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                if (cm == null) return;
                ClipData current = cm.getPrimaryClip();
                if (current == null || current.getItemCount() == 0) return;
                String currentText = current.getItemAt(0).coerceToText(this).toString();
                if (currentText.equals(copiedValue)) {
                    cm.setPrimaryClip(ClipData.newPlainText("", ""));
                }
            } catch (Exception ignored) {}
        }, 30_000L);
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private String shortenAddress(String address) {
        if (address == null || address.length() <= 16) return address == null ? "" : address;
        return address.substring(0, 8) + "..." + address.substring(address.length() - 8);
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }

    // ── Adapter ───────────────────────────────────────────────────────────

    private final class AddressAdapter extends RecyclerView.Adapter<AddressAdapter.VH> {

        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(AddressBookActivity.this)
                    .inflate(R.layout.item_address_book, parent, false);
            return new VH(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            AddressBookStore.Entry entry = displayedEntries.get(position);
            holder.labelText.setText(entry.label.isEmpty() ? "Unnamed" : entry.label);
            holder.addressText.setText(
                    entry.address.length() > 20
                    ? entry.address.substring(0, 10) + "…" + entry.address.substring(entry.address.length() - 10)
                    : entry.address);

            holder.editButton.setOnClickListener(v -> openEntryEditor(entry));
            holder.deleteButton.setOnClickListener(v -> showDeleteConfirm(entry));
            holder.itemView.setOnClickListener(v -> onEntryClicked(entry));
        }

        @Override
        public int getItemCount() { return displayedEntries.size(); }

        final class VH extends RecyclerView.ViewHolder {
            final TextView labelText;
            final TextView addressText;
            final ImageButton editButton;
            final ImageButton deleteButton;

            VH(View itemView) {
                super(itemView);
                labelText   = itemView.findViewById(R.id.entry_label);
                addressText = itemView.findViewById(R.id.entry_address);
                editButton  = itemView.findViewById(R.id.entry_edit_button);
                deleteButton = itemView.findViewById(R.id.entry_delete_button);
            }
        }
    }
}
