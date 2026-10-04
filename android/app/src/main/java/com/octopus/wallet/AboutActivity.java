package com.octopus.wallet;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.pm.PackageInfo;
import android.os.Bundle;
import android.widget.TextView;

public class AboutActivity extends BaseTxActivity {
    private static final String DONATION_ADDRESS = "oct5ZPf49ZYNnA1hopXe9EcDbiBPhgwJyudxLaLhHefEmFt";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_about);
        setupToolbar(R.id.about_toolbar, "About");

        TextView versionText = findViewById(R.id.about_version_text);
        TextView donationAddressText = findViewById(R.id.about_donation_address_text);

        versionText.setText(getVersionText());
        donationAddressText.setText(DONATION_ADDRESS);

        findViewById(R.id.about_copy_button).setOnClickListener(v -> copyDonationAddress());
    }

    private String getVersionText() {
        try {
            PackageInfo packageInfo = getPackageManager().getPackageInfo(getPackageName(), 0);
            String versionName = packageInfo.versionName == null ? "-" : packageInfo.versionName;
            return "Version " + versionName;
        } catch (Exception e) {
            return "Version -";
        }
    }

    private void copyDonationAddress() {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("Donation Address", DONATION_ADDRESS));
        showSuccess("Donation address copied");
    }
}
