package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;

public class ConfirmActionActivity extends BaseTxActivity {

    public static final String EXTRA_TITLE = "title";
    public static final String EXTRA_MESSAGE = "message";
    public static final String EXTRA_POSITIVE = "positive";
    public static final String EXTRA_NEGATIVE = "negative";
    public static final String EXTRA_REQUIRE_EXPLICIT = "require_explicit";
    public static final String EXTRA_NEGATIVE_FINISH_AFFINITY = "negative_finish_affinity";

    public static final String EXTRA_CONFIRMED = "confirmed";

    private boolean requireExplicit;
    private boolean negativeFinishAffinity;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_confirm_action);

        String title = getIntent().getStringExtra(EXTRA_TITLE);
        String message = getIntent().getStringExtra(EXTRA_MESSAGE);
        String positiveText = getIntent().getStringExtra(EXTRA_POSITIVE);
        String negativeText = getIntent().getStringExtra(EXTRA_NEGATIVE);

        requireExplicit = getIntent().getBooleanExtra(EXTRA_REQUIRE_EXPLICIT, false);
        negativeFinishAffinity = getIntent().getBooleanExtra(EXTRA_NEGATIVE_FINISH_AFFINITY, false);

        TextView titleView = findViewById(R.id.confirm_action_title);
        TextView messageView = findViewById(R.id.confirm_action_message);
        MaterialButton positiveButton = findViewById(R.id.confirm_action_positive);
        MaterialButton negativeButton = findViewById(R.id.confirm_action_negative);

        titleView.setText(title == null || title.trim().isEmpty() ? "Please Confirm" : title.trim());
        messageView.setText(message == null ? "" : message);

        if (positiveText == null || positiveText.trim().isEmpty()) {
            positiveButton.setText("Continue");
        } else {
            positiveButton.setText(positiveText.trim());
        }

        if (negativeText == null || negativeText.trim().isEmpty()) {
            negativeButton.setVisibility(View.GONE);
        } else {
            negativeButton.setVisibility(View.VISIBLE);
            negativeButton.setText(negativeText.trim());
        }

        positiveButton.setOnClickListener(v -> {
            Intent data = new Intent();
            data.putExtra(EXTRA_CONFIRMED, true);
            setResult(RESULT_OK, data);
            finish();
        });

        negativeButton.setOnClickListener(v -> {
            Intent data = new Intent();
            data.putExtra(EXTRA_CONFIRMED, false);
            setResult(RESULT_CANCELED, data);
            if (negativeFinishAffinity) {
                finishAffinity();
            } else {
                finish();
            }
        });

        setFinishOnTouchOutside(!requireExplicit);
    }

    @Override
    public void onBackPressed() {
        if (requireExplicit) {
            return;
        }
        super.onBackPressed();
    }
}
