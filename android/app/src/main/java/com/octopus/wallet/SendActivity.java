package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.EditText;
import android.widget.TextView;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;

public class SendActivity extends BaseTxActivity {
    public static final String EXTRA_TOKEN_ADDRESS  = "token_address";
    public static final String EXTRA_TOKEN_SYMBOL   = "token_symbol";
    public static final String EXTRA_TOKEN_DECIMALS = "token_decimals";
    public static final String EXTRA_TOKEN_NAME     = "token_name";
    /** Pre-fill the recipient field; used by deep links (octra://send?to=...) and address book. */
    public static final String EXTRA_PREFILL_TO     = "prefill_to";
    /** Pre-fill the amount field; used by deep links (octra://send?amount=...). */
    public static final String EXTRA_PREFILL_AMOUNT = "prefill_amount";

    private View submitButton;
    private EditText toInput;
    private long recommendedFee = 1000L;
    private boolean isTokenMode = false;
    private String tokenAddress = "";
    private String tokenSymbol = "OCT";
    private String tokenName = "";
    private int tokenDecimals = 6;
    private Runnable pendingSendAction;

    private final ActivityResultLauncher<Intent> progressLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() == RESULT_OK && result.getData() != null) {
                    // Auto-refresh balance in background (silent, no loading indicator)
                    refreshBalanceSilent();
                    setResult(RESULT_OK, result.getData());
                    finish();
                }
            });

    private final ActivityResultLauncher<Intent> qrScanLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() == RESULT_OK && result.getData() != null) {
                    String qrText = result.getData().getStringExtra(QrScanActivity.EXTRA_QR_TEXT);
                    if (qrText != null && !qrText.trim().isEmpty() && toInput != null) {
                        toInput.setText(qrText.trim());
                    }
                }
            });

    private final ActivityResultLauncher<Intent> confirmLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                Runnable action = pendingSendAction;
                pendingSendAction = null;
                if (action == null) {
                    return;
                }
                if (result.getResultCode() == RESULT_OK) {
                    action.run();
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_send);
        setupToolbar(R.id.tx_toolbar, "Send");

        toInput = findViewById(R.id.send_to_input);
        EditText amountInput = findViewById(R.id.send_amount_input);
        EditText messageInput = findViewById(R.id.send_message_input);
        EditText customFeeInput = findViewById(R.id.send_custom_fee_input);
        com.google.android.material.checkbox.MaterialCheckBox customFeeCheck = findViewById(R.id.send_custom_fee_check);
        submitButton = findViewById(R.id.send_submit_button);

        // Resolve token mode if provided
        tokenAddress = getIntent().getStringExtra(EXTRA_TOKEN_ADDRESS);
        tokenSymbol = getIntent().getStringExtra(EXTRA_TOKEN_SYMBOL);
        tokenName = getIntent().getStringExtra(EXTRA_TOKEN_NAME);
        tokenDecimals = getIntent().getIntExtra(EXTRA_TOKEN_DECIMALS, 6);
        isTokenMode = tokenAddress != null && !tokenAddress.trim().isEmpty();
        if (tokenSymbol == null || tokenSymbol.trim().isEmpty()) {
            tokenSymbol = isTokenMode ? "TOKEN" : "OCT";
        }

        TextView titleText = findViewById(R.id.send_title_text);
        TextView subtitleText = findViewById(R.id.send_subtitle_text);
        if (isTokenMode) {
            if (titleText != null) {
                titleText.setText("Send " + tokenSymbol);
            }
            if (subtitleText != null) {
                subtitleText.setText("Send a " + tokenSymbol + " token transfer to the recipient.");
            }
            amountInput.setHint("Amount (" + tokenSymbol + ")");
            messageInput.setVisibility(android.view.View.GONE);
        } else {
            if (titleText != null) {
                titleText.setText("Send OCT");
            }
            if (subtitleText != null) {
                subtitleText.setText("Enter recipient, amount, then send the transaction.");
            }
            amountInput.setHint("Amount (OCT)");
            messageInput.setVisibility(android.view.View.VISIBLE);
        }

        if (isTokenMode) {
            if (submitButton instanceof com.google.android.material.button.MaterialButton) {
                ((com.google.android.material.button.MaterialButton) submitButton)
                        .setText("Send " + tokenSymbol);
            }
        }

        // Handle pre-fill from deep link (octra://send?to=...&amount=...) or address book.
        String prefillTo = getIntent().getStringExtra(EXTRA_PREFILL_TO);
        String prefillAmount = getIntent().getStringExtra(EXTRA_PREFILL_AMOUNT);
        if (prefillTo != null && !prefillTo.trim().isEmpty()) {
            toInput.setText(prefillTo.trim());
        }
        if (prefillAmount != null && !prefillAmount.trim().isEmpty()) {
            amountInput.setText(prefillAmount.trim());
        }

        // Show available balance
        if (isTokenMode) {
            loadTokenBalance(findViewById(R.id.send_available_balance_text),
                    tokenAddress, tokenSymbol, tokenDecimals);
        } else {
            loadPublicBalance(findViewById(R.id.send_available_balance_text));
        }

        if (customFeeInput != null) {
            customFeeInput.setText(String.valueOf(recommendedFee));
        }

        // Amount preview
        View amountPreviewCard = findViewById(R.id.send_amount_preview_card);
        TextView amountPreviewText = findViewById(R.id.send_amount_preview_text);
        amountInput.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                String text = s == null ? "" : s.toString().trim();
                if (text.isEmpty()) {
                    amountPreviewCard.setVisibility(View.GONE);
                } else {
                    try {
                        double val = Double.parseDouble(text);
                        if (val > 0) {
                            amountPreviewCard.setVisibility(View.VISIBLE);
                            amountPreviewText.setText(text + " " + (isTokenMode ? tokenSymbol : "OCT"));
                        } else {
                            amountPreviewCard.setVisibility(View.GONE);
                        }
                    } catch (Exception e) {
                        amountPreviewCard.setVisibility(View.GONE);
                    }
                }
            }
            @Override
            public void afterTextChanged(Editable s) {}
        });

        customFeeCheck.setOnCheckedChangeListener((buttonView, isChecked) -> {
            customFeeInput.setEnabled(isChecked);
            if (!isChecked) {
                customFeeInput.setText(String.valueOf(recommendedFee));
            }
        });

        ioExecutor().execute(() -> {
            long suggested = fetchRecommendedFee(getCurrentRpcUrl(), "standard", recommendedFee);
            recommendedFee = suggested;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (customFeeInput != null && !customFeeCheck.isChecked()) {
                    customFeeInput.setText(String.valueOf(suggested));
                }
            });
        });

        findViewById(R.id.send_submit_button).setOnClickListener(v -> {
            String to = toInput.getText().toString().replaceAll("\\s+", "").trim();
            String amountText = amountInput.getText().toString().trim();
            String message = messageInput.getText().toString().trim();
            String customFeeText = customFeeInput.getText().toString().trim();

            if (customFeeCheck.isChecked()) {
                try {
                    long fee = Long.parseLong(customFeeText.isEmpty() ? "0" : customFeeText);
                    if (fee <= 0) {
                        showError("Custom gas fee must be greater than 0");
                        return;
                    }
                } catch (Exception e) {
                    showError("Custom gas fee is invalid");
                    return;
                }
            }

            if (to.isEmpty() || to.length() != 47 || !to.startsWith("oct")) {
                showError("Recipient address is invalid");
                return;
            }

            long amountRaw;
            try {
                java.math.BigDecimal inputBd = new java.math.BigDecimal(amountText);
                if (inputBd.compareTo(java.math.BigDecimal.ZERO) <= 0) {
                    showError("Amount must be greater than 0");
                    return;
                }
                if (isTokenMode) {
                    java.math.BigDecimal raw = inputBd
                            .multiply(java.math.BigDecimal.TEN.pow(tokenDecimals));
                    amountRaw = raw.setScale(0, java.math.RoundingMode.DOWN).longValue();
                } else {
                    amountRaw = inputBd.multiply(java.math.BigDecimal.valueOf(1_000_000))
                            .setScale(0, java.math.RoundingMode.HALF_UP).longValue();
                }
            } catch (Exception e) {
                showError("Amount is invalid");
                return;
            }

            if (amountRaw <= 0) {
                showError("Amount must be greater than 0");
                return;
            }

            final long confirmedAmountRaw = amountRaw;
            final String confirmedTo = to;
            final String confirmedMessage = message;
            final String confirmedFeeText = customFeeText;
            final boolean useCustomFee = customFeeCheck.isChecked();
            final String confirmedAmountDisplay = amountText + " " + (isTokenMode ? tokenSymbol : "OCT");

            showSendConfirmation(confirmedTo, confirmedAmountRaw, confirmedAmountDisplay,
                    confirmedFeeText, useCustomFee, () -> {
                String currentTxId = (isTokenMode ? "tx_token_" : "tx_send_") + System.currentTimeMillis();
                if (isTokenMode) {
                    String metaJson = buildTokenMetaJson(confirmedTo, confirmedAmountRaw,
                            confirmedMessage, confirmedFeeText);
                    TxForegroundService.startTx(SendActivity.this, TxForegroundService.ACTION_TOKEN_SEND,
                            currentTxId, confirmedTo, confirmedAmountRaw, metaJson);
                } else {
                    TxForegroundService.startTx(SendActivity.this, TxForegroundService.ACTION_SEND,
                            currentTxId, confirmedTo, confirmedAmountRaw, confirmedMessage);
                }

                Intent progressIntent = new Intent(SendActivity.this, TxProgressActivity.class);
                progressIntent.putExtra(TxProgressActivity.EXTRA_TX_ID, currentTxId);
                progressIntent.putExtra(TxProgressActivity.EXTRA_TX_TYPE,
                        isTokenMode ? TxForegroundService.ACTION_TOKEN_SEND : TxForegroundService.ACTION_SEND);
                progressLauncher.launch(progressIntent);

                toInput.setText("");
                amountInput.setText("");
                messageInput.setText("");
            });
        });

        com.google.android.material.floatingactionbutton.FloatingActionButton txManagerFab =
                findViewById(R.id.send_fab_tx_manager);
        if (txManagerFab != null) {
            txManagerFab.setOnClickListener(v ->
                    startActivity(new Intent(this, TransactionsManagerActivity.class)));
        }
    }

    private String buildTokenMetaJson(String to, long amountRaw, String note, String feeText) {
        try {
            org.json.JSONObject obj = new org.json.JSONObject();
            obj.put("token_address", tokenAddress == null ? "" : tokenAddress.trim());
            obj.put("token_symbol", tokenSymbol == null ? "" : tokenSymbol.trim());
            obj.put("token_name", tokenName == null ? "" : tokenName.trim());
            obj.put("token_decimals", tokenDecimals);
            obj.put("to", to == null ? "" : to.trim());
            obj.put("amount_raw", String.valueOf(Math.max(0L, amountRaw)));
            if (note != null && !note.trim().isEmpty()) {
                obj.put("note", note.trim());
            }
            if (feeText != null && !feeText.trim().isEmpty()) {
                obj.put("fee", feeText.trim());
            }
            return obj.toString();
        } catch (Exception e) {
            return "";
        }
    }

    private void showSendConfirmation(String to, long amountRaw, String amountDisplay,
                                       String feeText, boolean useCustomFee, Runnable onConfirm) {
        long displayFeeRaw;
        try {
            long parsed = Long.parseLong(
                    feeText == null || feeText.trim().isEmpty() ? "0" : feeText.trim());
            displayFeeRaw = useCustomFee && parsed > 0 ? parsed : recommendedFee;
        } catch (Exception e) {
            displayFeeRaw = recommendedFee;
        }

        String toShort = to.length() > 24
                ? to.substring(0, 10) + "\u2026" + to.substring(to.length() - 8) : to;
        String feeDisplay = WalletRepository.formatOct(displayFeeRaw) + " OCT";

        StringBuilder msg = new StringBuilder()
                .append("Recipient:\n").append(toShort)
                .append("\n\nAmount:  ").append(amountDisplay)
                .append("\nNetwork fee:  ").append(feeDisplay);
        if (!isTokenMode) {
            long totalRaw = amountRaw + displayFeeRaw;
            msg.append("\nTotal deducted:  ").append(WalletRepository.formatOct(totalRaw)).append(" OCT");
        }

        pendingSendAction = onConfirm;
        Intent intent = new Intent(this, ConfirmActionActivity.class);
        intent.putExtra(ConfirmActionActivity.EXTRA_TITLE, "Confirm Transaction");
        intent.putExtra(ConfirmActionActivity.EXTRA_MESSAGE, msg.toString());
        intent.putExtra(ConfirmActionActivity.EXTRA_POSITIVE, "Send");
        intent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE, "Cancel");
        confirmLauncher.launch(intent);
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.send_toolbar_menu, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == R.id.action_scan_qr) {
            Intent intent = new Intent(this, QrScanActivity.class);
            qrScanLauncher.launch(intent);
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    /**
     * Refreshes balance in the background without showing any loading indicator.
     * Used for auto-refresh after successful transactions.
     */
    private void refreshBalanceSilent() {
        java.util.concurrent.ExecutorService executor = java.util.concurrent.Executors.newSingleThreadExecutor();
        executor.execute(() -> {
            try {
                // Fetch balance silently via WalletRepository
                String rpcUrl = getCurrentRpcUrl();
                String address = getCurrentWalletAddress();
                if (rpcUrl != null && address != null) {
                    repo().fetchBalance(rpcUrl, address);
                }
            } catch (Exception e) {
                // Silently ignore errors - this is a background refresh
            }
        });
    }

    /**
     * Returns the current wallet address from the selected wallet profile.
     */
    private String getCurrentWalletAddress() {
        try {
            String walletId = WalletProfileStore.getSelectedWalletId(this);
            if (walletId != null) {
                return WalletAddressStore.getAddress(this, walletId);
            }
        } catch (Exception e) {
            // Ignore errors
        }
        return null;
    }

}
