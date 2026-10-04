package com.octopus.wallet;

import android.content.Context;

import org.json.JSONObject;

public class WalletKeysLoader {
    public static WalletKeys loadKeys(Context context, String walletId) {
        return loadKeys(context, walletId, null);
    }

    public static WalletKeys loadKeys(Context context, String walletId, String pinInput) {
        WalletKeys keys = new WalletKeys();
        String previousWalletId = WalletProfileStore.getSelectedWalletId(context);
        String previousPin = PinStore.getDefaultPin(context);
        try {
            String id = walletId == null || walletId.trim().isEmpty() ? WalletProfileStore.getSelectedWalletId(context) : walletId;
            java.io.File walletDir = WalletProfileStore.getWalletDir(context, id);
            OctraNative.getInstance().lockWallet();
            OctraNative.getInstance().init(walletDir.getAbsolutePath());
            // Attempt to unlock with entered PIN first, then default PIN as fallback.
            String pin = pinInput == null ? "" : pinInput.trim();
            boolean unlocked = false;
            if (pin != null && pin.matches("\\d{6}")) {
                try {
                    String res = OctraNative.getInstance().unlockWallet(pin);
                    JSONObject jr = new JSONObject(res);
                    unlocked = !jr.has("error");
                } catch (Exception ignored) {}
            }

            if (!unlocked) {
                String defaultPin = PinStore.getDefaultPin(context);
                if (defaultPin != null && defaultPin.matches("\\d{6}")) {
                    try {
                        String res = OctraNative.getInstance().unlockWallet(defaultPin);
                        JSONObject jr = new JSONObject(res);
                        unlocked = !jr.has("error");
                    } catch (Exception ignored) {}
                }
            }

            String infoJson = OctraNative.getInstance().getWalletInfo();
            JSONObject info = new JSONObject(infoJson);
            keys.address = info.optString("address", "-");
            keys.pubkey = info.optString("public_key", "-");
            if (unlocked) {
                try {
                    keys.viewPubkey = OctraNative.getInstance().getViewPublicKey();
                } catch (Exception ignored) {
                    keys.viewPubkey = "-";
                }
                try {
                    keys.privkey = OctraNative.getInstance().getPrivateKey();
                } catch (Exception ignored) {
                    keys.privkey = "-";
                }
            } else {
                keys.viewPubkey = "";
                keys.privkey = "";
            }
        } catch (Exception e) {
            keys.address = "-";
            keys.pubkey = "-";
            keys.viewPubkey = "";
            keys.privkey = "";
        } finally {
            try {
                // Restore previously selected wallet context.
                String restoreId = previousWalletId == null || previousWalletId.trim().isEmpty()
                        ? WalletProfileStore.getSelectedWalletId(context)
                        : previousWalletId;
                java.io.File restoreDir = WalletProfileStore.getWalletDir(context, restoreId);
                OctraNative.getInstance().lockWallet();
                OctraNative.getInstance().init(restoreDir.getAbsolutePath());
                if (previousPin != null && previousPin.matches("\\d{6}")) {
                    OctraNative.getInstance().unlockWallet(previousPin);
                }
            } catch (Exception ignored) {
            }
        }
        return keys;
    }
}

class WalletKeys {
    public String address;
    public String pubkey;
    public String viewPubkey;
    public String privkey;
}
