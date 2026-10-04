package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.widget.EditText;
import android.widget.TextView;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;

public class AddNetworkActivity extends BaseTxActivity {

    public static final String EXTRA_EDITING = "editing";
    public static final String EXTRA_NAME = "name";
    public static final String EXTRA_RPC = "rpc";
    public static final String EXTRA_EXPLORER = "explorer";

    private boolean editing;
    private EditText nameInput;
    private EditText rpcInput;
    private EditText explorerInput;
    private Intent pendingCommitData;

    private final ActivityResultLauncher<Intent> confirmLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (pendingCommitData == null) {
                    return;
                }
                Intent data = pendingCommitData;
                pendingCommitData = null;
                if (result.getResultCode() == RESULT_OK) {
                    setResult(RESULT_OK, data);
                    finish();
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_add_network);

        editing = getIntent().getBooleanExtra(EXTRA_EDITING, false);

        setupToolbar(R.id.add_network_toolbar, editing ? "Edit Network" : "Add Network");

        TextView title = findViewById(R.id.add_network_title);
        nameInput = findViewById(R.id.add_network_name_input);
        rpcInput = findViewById(R.id.add_network_rpc_input);
        explorerInput = findViewById(R.id.add_network_explorer_input);

        title.setText(editing ? "Edit Network" : "Add Network");

        if (editing) {
            nameInput.setText(getIntent().getStringExtra(EXTRA_NAME));
            nameInput.setEnabled(false);
            rpcInput.setText(getIntent().getStringExtra(EXTRA_RPC));
            explorerInput.setText(getIntent().getStringExtra(EXTRA_EXPLORER));
        }

        findViewById(R.id.add_network_save_button).setOnClickListener(v -> trySave());
    }

    private void trySave() {
        String name = valueOf(nameInput);
        String rpc = valueOf(rpcInput);
        String explorer = valueOf(explorerInput);

        if (name.isEmpty() || rpc.isEmpty()) {
            showError("Network name and RPC URL are required");
            return;
        }

        String normalizedRpc = UrlSecurityValidator.normalizeRpcUrl(rpc);
        if (normalizedRpc == null || !UrlSecurityValidator.isValidRpcUrl(normalizedRpc)) {
            showError("RPC URL is invalid. Use http:// or https:// with a valid host.");
            return;
        }

        String normalizedExplorer = UrlSecurityValidator.normalizeExplorerUrl(explorer);
        if (normalizedExplorer == null || !UrlSecurityValidator.isValidExplorerUrl(normalizedExplorer)) {
            showError("Explorer URL is invalid. Use a valid https:// URL.");
            return;
        }

        Runnable commit = () -> {
            Intent data = new Intent();
            data.putExtra(EXTRA_EDITING, editing);
            data.putExtra(EXTRA_NAME, name);
            data.putExtra(EXTRA_RPC, normalizedRpc);
            data.putExtra(EXTRA_EXPLORER, normalizedExplorer);
            setResult(RESULT_OK, data);
            finish();
        };

        if (UrlSecurityValidator.isCleartextRpc(normalizedRpc)) {
            Intent data = new Intent();
            data.putExtra(EXTRA_EDITING, editing);
            data.putExtra(EXTRA_NAME, name);
            data.putExtra(EXTRA_RPC, normalizedRpc);
            data.putExtra(EXTRA_EXPLORER, normalizedExplorer);
            pendingCommitData = data;

            Intent confirmIntent = new Intent(this, ConfirmActionActivity.class);
            confirmIntent.putExtra(ConfirmActionActivity.EXTRA_TITLE, "Unencrypted RPC Connection");
            confirmIntent.putExtra(ConfirmActionActivity.EXTRA_MESSAGE,
                    "This RPC endpoint uses HTTP. Network traffic may be visible to others. Continue only if you trust this network.");
            confirmIntent.putExtra(ConfirmActionActivity.EXTRA_POSITIVE, "Continue");
            confirmIntent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE, "Cancel");
            confirmLauncher.launch(confirmIntent);
            return;
        }

        commit.run();
    }

    private String valueOf(EditText input) {
        return input.getText() == null ? "" : input.getText().toString().trim();
    }
}
