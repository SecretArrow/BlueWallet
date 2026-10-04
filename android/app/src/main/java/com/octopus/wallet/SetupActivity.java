package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONException;
import org.json.JSONObject;

public class SetupActivity extends AppCompatActivity {
    
    private LinearLayout choiceView;
    private LinearLayout importView;
    private LinearLayout pinSetupView;
    
    private EditText privateKeyInput;
    private EditText pinInput;
    private EditText pinConfirmInput;
    
    private boolean isImporting = false;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(resolveThemeRes());
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_setup);
        
        initViews();
    }

    private int resolveThemeRes() {
        return ThemeManager.resolveThemeRes(this);
    }
    
    private void initViews() {
        choiceView = findViewById(R.id.choice_view);
        importView = findViewById(R.id.import_view);
        pinSetupView = findViewById(R.id.pin_setup_view);
        
        privateKeyInput = findViewById(R.id.private_key_input);
        pinInput = findViewById(R.id.pin_input);
        pinConfirmInput = findViewById(R.id.pin_confirm_input);
        
        Button createButton = findViewById(R.id.create_button);
        Button importButton = findViewById(R.id.import_button);
        Button doImportButton = findViewById(R.id.do_import_button);
        Button backFromImportButton = findViewById(R.id.back_from_import_button);
        Button setPinButton = findViewById(R.id.set_pin_button);
        Button backFromPinButton = findViewById(R.id.back_from_pin_button);
        
        createButton.setOnClickListener(v -> {
            // Launch CreateMnemonicActivity for seed phrase wallet creation
            startActivity(new Intent(this, CreateMnemonicActivity.class));
        });
        
        importButton.setOnClickListener(v -> showImport());
        
        doImportButton.setOnClickListener(v -> {
            String privateKey = privateKeyInput.getText().toString().trim();
            if (privateKey.isEmpty()) {
                showError("Please enter a private key");
                return;
            }
            isImporting = true;
            showPinSetup();
        });
        
        backFromImportButton.setOnClickListener(v -> showChoice());
        
        setPinButton.setOnClickListener(v -> doSetPin());
        
        backFromPinButton.setOnClickListener(v -> {
            if (isImporting) {
                showImport();
            } else {
                showChoice();
            }
        });
    }
    
    private void showChoice() {
        choiceView.setVisibility(View.VISIBLE);
        importView.setVisibility(View.GONE);
        pinSetupView.setVisibility(View.GONE);
    }
    
    private void showImport() {
        choiceView.setVisibility(View.GONE);
        importView.setVisibility(View.VISIBLE);
        pinSetupView.setVisibility(View.GONE);
    }
    
    private void showPinSetup() {
        choiceView.setVisibility(View.GONE);
        importView.setVisibility(View.GONE);
        pinSetupView.setVisibility(View.VISIBLE);
        pinInput.setText("");
        pinConfirmInput.setText("");
    }
    
    private void doSetPin() {
        String pin = pinInput.getText().toString();
        String pinConfirm = pinConfirmInput.getText().toString();
        
        if (pin.length() != 6) {
            showError("PIN must be exactly 6 digits");
            return;
        }
        
        if (!pin.matches("\\d{6}")) {
            showError("PIN must contain only digits");
            return;
        }
        
        if (!pin.equals(pinConfirm)) {
            showError("PINs do not match");
            return;
        }
        
        try {
            String result;
            if (isImporting) {
                String privateKey = privateKeyInput.getText().toString().trim();
                result = OctraNative.getInstance().importWallet(privateKey, pin);
            } else {
                result = OctraNative.getInstance().createWallet(pin);
            }
            
            JSONObject json = new JSONObject(result);
            
            if (json.has("error")) {
                showError(json.getString("error"));
                return;
            }

            PinStore.setDefaultPin(this, pin);
            
            String address = json.getString("address");
            showSuccess("Wallet " + (isImporting ? "imported" : "created") + ": " + address);
            
            startActivity(new Intent(this, MainActivity.class));
            finish();
            
        } catch (JSONException e) {
            showError("Failed to create wallet");
        }
    }
    
    private void showError(String message) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show();
    }
    
    private void showSuccess(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }
}
