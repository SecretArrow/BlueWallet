package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;

public class NetworkActionActivity extends BaseTxActivity {

    public static final String EXTRA_NAME = "name";
    public static final String EXTRA_IS_ACTIVE = "is_active";

    public static final String EXTRA_ACTION = "action";
    public static final String ACTION_ACTIVATE = "activate";
    public static final String ACTION_EDIT = "edit";
    public static final String ACTION_DELETE = "delete";

    private String profileName;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_network_action);
        setupToolbar(R.id.network_action_toolbar, "Network Actions");

        String name = getIntent().getStringExtra(EXTRA_NAME);
        boolean isActive = getIntent().getBooleanExtra(EXTRA_IS_ACTIVE, false);
        profileName = name == null ? "" : name.trim();

        TextView title = findViewById(R.id.network_action_title);
        MaterialButton activate = findViewById(R.id.network_action_activate);
        MaterialButton edit = findViewById(R.id.network_action_edit);
        MaterialButton delete = findViewById(R.id.network_action_delete);

        title.setText(name == null || name.trim().isEmpty() ? "Selected network" : name.trim());
        activate.setText(isActive ? "Activate (Active)" : "Activate");

        activate.setOnClickListener(v -> returnAction(ACTION_ACTIVATE));
        edit.setOnClickListener(v -> returnAction(ACTION_EDIT));
        delete.setOnClickListener(v -> returnAction(ACTION_DELETE));
    }

    private void returnAction(String action) {
        Intent data = new Intent();
        data.putExtra(EXTRA_ACTION, action);
        data.putExtra(EXTRA_NAME, profileName);
        setResult(RESULT_OK, data);
        finish();
    }
}
