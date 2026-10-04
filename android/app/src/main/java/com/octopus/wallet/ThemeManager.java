package com.octopus.wallet;

import android.content.Context;

public final class ThemeManager {
    public static final String PREFS_UI = "ui_prefs";
    public static final String KEY_THEME = "theme";

    public static final String THEME_ZENITH = "zenith";
    public static final String THEME_MOONBLOOM = "moonbloom";
    public static final String THEME_FROSTLINE = "frostline";
    public static final String THEME_SIGNAL = "signal";
    public static final String THEME_NIGHTPULSE = "nightpulse";
    public static final String THEME_OBSIDIANGRID = "obsidiangrid";
    public static final String THEME_NEONFORGE = "neonforge";
    public static final String THEME_IVORYCIRCUIT = "ivorycircuit";
    public static final String THEME_SOLARPAPER = "solarpaper";
    public static final String THEME_MISTTERMINAL = "mistterminal";

    private ThemeManager() {
    }

    public static int resolveThemeRes(Context context) {
        String theme = getCurrentTheme(context);
        if (THEME_MOONBLOOM.equals(theme)) {
            return R.style.Theme_OctraWallet_Moonbloom;
        }
        if (THEME_FROSTLINE.equals(theme) || "light".equals(theme)) {
            return R.style.Theme_OctraWallet_Frostline;
        }
        if (THEME_SIGNAL.equals(theme) || "pastel".equals(theme)) {
            return R.style.Theme_OctraWallet_Signal;
        }
        if (THEME_NIGHTPULSE.equals(theme)) {
            return R.style.Theme_OctraWallet_NightPulse;
        }
        if (THEME_OBSIDIANGRID.equals(theme)) {
            return R.style.Theme_OctraWallet_ObsidianGrid;
        }
        if (THEME_NEONFORGE.equals(theme)) {
            return R.style.Theme_OctraWallet_NeonForge;
        }
        if (THEME_IVORYCIRCUIT.equals(theme)) {
            return R.style.Theme_OctraWallet_IvoryCircuit;
        }
        if (THEME_SOLARPAPER.equals(theme)) {
            return R.style.Theme_OctraWallet_SolarPaper;
        }
        if (THEME_MISTTERMINAL.equals(theme)) {
            return R.style.Theme_OctraWallet_MistTerminal;
        }
        return R.style.Theme_OctraWallet_Zenith;
    }

    public static String getCurrentTheme(Context context) {
        return context.getSharedPreferences(PREFS_UI, Context.MODE_PRIVATE)
                .getString(KEY_THEME, THEME_ZENITH);
    }

    public static void setCurrentTheme(Context context, String themeKey) {
        context.getSharedPreferences(PREFS_UI, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_THEME, themeKey)
                .apply();
    }
}
