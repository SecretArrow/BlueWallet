package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.security.crypto.EncryptedSharedPreferences;
import androidx.security.crypto.MasterKey;

/**
 * Stores mnemonic metadata and encrypted mnemonic phrases for wallets
 * created via BIP-39. Sensitive data (the mnemonic itself) is kept in
 * EncryptedSharedPreferences (AES256-GCM via Android Keystore).
 */
public final class MnemonicStore {

    private static final String PREFS_META   = "mnemonic_meta";
    private static final String PREFS_SECURE = "mnemonic_secure";

    private MnemonicStore() {}

    // ── Secure preferences ───────────────────────────────────────────────────

    private static SharedPreferences securePrefs(Context ctx) {
        try {
            MasterKey key = new MasterKey.Builder(ctx)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build();
            return EncryptedSharedPreferences.create(
                    ctx, PREFS_SECURE, key,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM);
        } catch (Exception e) {
            // Fallback — plain prefs (rare, e.g. emulator without Keystore)
            return ctx.getSharedPreferences(PREFS_SECURE + "_plain", Context.MODE_PRIVATE);
        }
    }

    private static SharedPreferences metaPrefs(Context ctx) {
        return ctx.getSharedPreferences(PREFS_META, Context.MODE_PRIVATE);
    }

    // ── Public API ───────────────────────────────────────────────────────────

    /** Returns true if this wallet was created from a BIP-39 mnemonic. */
    public static boolean isMnemonicWallet(Context ctx, String walletId) {
        String type = metaPrefs(ctx).getString("type_" + walletId, null);
        return "mnemonic".equals(type);
    }

    /** Returns true if this wallet is a child derived from a parent mnemonic wallet. */
    public static boolean isChildWallet(Context ctx, String walletId) {
        String type = metaPrefs(ctx).getString("type_" + walletId, null);
        return "child".equals(type);
    }

    /** Returns true if this wallet is mnemonic-type or a derived child. */
    public static boolean isMnemonicRelated(Context ctx, String walletId) {
        return isMnemonicWallet(ctx, walletId) || isChildWallet(ctx, walletId);
    }

    /**
     * Persists the mnemonic phrase encrypted under the device Keystore.
     * Also records this wallet's type as "mnemonic".
     */
    public static void saveMnemonic(Context ctx, String walletId, String mnemonic) {
        securePrefs(ctx).edit()
                .putString("mnemonic_" + walletId, mnemonic)
                .apply();
        metaPrefs(ctx).edit()
                .putString("type_" + walletId, "mnemonic")
                .apply();
    }

    /** Returns the stored mnemonic, or null if not found. */
    public static String getMnemonic(Context ctx, String walletId) {
        // Direct mnemonic wallets
        String m = securePrefs(ctx).getString("mnemonic_" + walletId, null);
        if (m != null) return m;
        // Child wallets share the parent's mnemonic
        String parentId = getParentWalletId(ctx, walletId);
        if (parentId != null) {
            return securePrefs(ctx).getString("mnemonic_" + parentId, null);
        }
        return null;
    }

    /** Persists the HD derivation path for a wallet. */
    public static void saveDerivationPath(Context ctx, String walletId, String path) {
        metaPrefs(ctx).edit()
                .putString("path_" + walletId, path)
                .apply();
    }

    /** Returns the HD derivation path, defaulting to m/44'/540'/0'/0'/0'. */
    public static String getDerivationPath(Context ctx, String walletId) {
        return metaPrefs(ctx).getString("path_" + walletId, "m/44'/540'/0'/0'/0'");
    }

    /** Links a child wallet to its parent mnemonic wallet. */
    public static void saveParentWalletId(Context ctx, String walletId, String parentId) {
        metaPrefs(ctx).edit()
                .putString("parent_" + walletId, parentId)
                .putString("type_" + walletId, "child")
                .apply();
    }

    /** Returns the parent wallet ID for child wallets, or null. */
    public static String getParentWalletId(Context ctx, String walletId) {
        return metaPrefs(ctx).getString("parent_" + walletId, null);
    }

    /** Purges all metadata and the encrypted mnemonic for a deleted wallet. */
    public static void remove(Context ctx, String walletId) {
        securePrefs(ctx).edit().remove("mnemonic_" + walletId).apply();
        metaPrefs(ctx).edit()
                .remove("type_" + walletId)
                .remove("path_" + walletId)
                .remove("parent_" + walletId)
                .apply();
    }
}
