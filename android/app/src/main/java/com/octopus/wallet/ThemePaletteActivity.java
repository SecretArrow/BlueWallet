package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.widget.ArrayAdapter;
import android.widget.Spinner;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.appbar.MaterialToolbar;

import java.util.ArrayList;
import java.util.List;

public class ThemePaletteActivity extends AppCompatActivity {

    private Spinner themeSpinner;

    @Override
    protected void onResume() {
        super.onResume();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    protected void onPause() {
        super.onPause();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    public void onUserInteraction() {
        super.onUserInteraction();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_theme_palette);

        MaterialToolbar toolbar = findViewById(R.id.theme_palette_toolbar);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setDisplayShowHomeEnabled(true);
        }
        toolbar.setNavigationOnClickListener(v -> finish());

        themeSpinner = findViewById(R.id.theme_palette_spinner);
        setupSpinner();

        findViewById(R.id.theme_palette_apply_button).setOnClickListener(v -> applyTheme());
        findViewById(R.id.theme_palette_cancel_button).setOnClickListener(v -> finish());
    }

    private void setupSpinner() {
        List<String> themes = new ArrayList<>();
        themes.add("Zenith (minimal)");
        themes.add("Moonbloom (dark)");
        themes.add("Frostline (cool)");
        themes.add("Signal (vibrant)");
        themes.add("NightPulse (dark)");
        themes.add("ObsidianGrid (dark)");
        themes.add("NeonForge (dark)");
        themes.add("IvoryCircuit (light)");
        themes.add("SolarPaper (light)");
        themes.add("MistTerminal (light)");

        ArrayAdapter<String> adapter = new ArrayAdapter<>(this, R.layout.spinner_item_wallet, themes);
        adapter.setDropDownViewResource(R.layout.spinner_item_wallet_dropdown);
        themeSpinner.setAdapter(adapter);

        String current = ThemeManager.getCurrentTheme(this);
        int index;
        if (ThemeManager.THEME_MOONBLOOM.equals(current)) {
            index = 1;
        } else if (ThemeManager.THEME_FROSTLINE.equals(current) || "light".equals(current)) {
            index = 2;
        } else if (ThemeManager.THEME_SIGNAL.equals(current) || "pastel".equals(current)) {
            index = 3;
        } else if (ThemeManager.THEME_NIGHTPULSE.equals(current)) {
            index = 4;
        } else if (ThemeManager.THEME_OBSIDIANGRID.equals(current)) {
            index = 5;
        } else if (ThemeManager.THEME_NEONFORGE.equals(current)) {
            index = 6;
        } else if (ThemeManager.THEME_IVORYCIRCUIT.equals(current)) {
            index = 7;
        } else if (ThemeManager.THEME_SOLARPAPER.equals(current)) {
            index = 8;
        } else if (ThemeManager.THEME_MISTTERMINAL.equals(current)) {
            index = 9;
        } else {
            index = 0;
        }
        themeSpinner.setSelection(index);
    }

    private void applyTheme() {
        int selected = themeSpinner.getSelectedItemPosition();
        String key;
        if (selected == 1) {
            key = ThemeManager.THEME_MOONBLOOM;
        } else if (selected == 2) {
            key = ThemeManager.THEME_FROSTLINE;
        } else if (selected == 3) {
            key = ThemeManager.THEME_SIGNAL;
        } else if (selected == 4) {
            key = ThemeManager.THEME_NIGHTPULSE;
        } else if (selected == 5) {
            key = ThemeManager.THEME_OBSIDIANGRID;
        } else if (selected == 6) {
            key = ThemeManager.THEME_NEONFORGE;
        } else if (selected == 7) {
            key = ThemeManager.THEME_IVORYCIRCUIT;
        } else if (selected == 8) {
            key = ThemeManager.THEME_SOLARPAPER;
        } else if (selected == 9) {
            key = ThemeManager.THEME_MISTTERMINAL;
        } else {
            key = ThemeManager.THEME_ZENITH;
        }

        ThemeManager.setCurrentTheme(this, key);
        Intent data = new Intent();
        data.putExtra("theme_changed", true);
        setResult(RESULT_OK, data);
        finish();
    }
}
