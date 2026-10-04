package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.widget.EditText;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;

public class AddressBookEntryActivity extends BaseTxActivity {

    public static final String EXTRA_EDITING = "editing";
    public static final String EXTRA_ENTRY_ID = "entry_id";
    public static final String EXTRA_LABEL = "label";
    public static final String EXTRA_ADDRESS = "address";
    public static final String EXTRA_ADDRESS_LOCKED = "address_locked";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_address_book_entry);

        boolean editing = getIntent().getBooleanExtra(EXTRA_EDITING, false);
        String title = editing ? "Edit Address" : "Add Address";
        setupToolbar(R.id.address_book_entry_toolbar, title);

        TextView header = findViewById(R.id.address_book_entry_title);
        EditText labelInput = findViewById(R.id.address_book_entry_label_input);
        EditText addressInput = findViewById(R.id.address_book_entry_address_input);
        MaterialButton saveButton = findViewById(R.id.address_book_entry_save_button);

        header.setText(title);

        String entryId = safe(getIntent().getStringExtra(EXTRA_ENTRY_ID));
        String initialLabel = safe(getIntent().getStringExtra(EXTRA_LABEL));
        String initialAddress = safe(getIntent().getStringExtra(EXTRA_ADDRESS));
        boolean addressLocked = getIntent().getBooleanExtra(EXTRA_ADDRESS_LOCKED, false);

        labelInput.setText(initialLabel);
        addressInput.setText(initialAddress);
        addressInput.setEnabled(!addressLocked);

        saveButton.setOnClickListener(v -> {
            String label = safe(labelInput.getText() == null ? "" : labelInput.getText().toString()).trim();
            String address = safe(addressInput.getText() == null ? "" : addressInput.getText().toString()).trim();

            if (address.isEmpty()) {
                showError("Address cannot be empty");
                return;
            }
            if (!address.startsWith("oct") || address.length() != 47) {
                showError("Invalid Octra address format");
                return;
            }

            Intent data = new Intent();
            data.putExtra(EXTRA_EDITING, editing);
            data.putExtra(EXTRA_ENTRY_ID, entryId);
            data.putExtra(EXTRA_LABEL, label);
            data.putExtra(EXTRA_ADDRESS, address);
            setResult(RESULT_OK, data);
            finish();
        });
    }

    private static String safe(String v) {
        return v == null ? "" : v;
    }
}
