package com.octopus.wallet;

import android.content.Context;

import org.json.JSONObject;

public final class WalletPinVerifier {
    private WalletPinVerifier() {
    }

    public static boolean verify(Context context, String walletId, String pin) {
        if (pin == null || !pin.matches("\\d{6}")) {
            return false;
        }

        String previousWalletId = WalletProfileStore.getSelectedWalletId(context);
        String previousPin = PinStore.getDefaultPin(context);

        try {
            String targetWalletId = walletId == null || walletId.trim().isEmpty()
                    ? WalletProfileStore.getSelectedWalletId(context)
                    : walletId;
            java.io.File targetDir = WalletProfileStore.getWalletDir(context, targetWalletId);

            OctraNative.getInstance().lockWallet();
            OctraNative.getInstance().init(targetDir.getAbsolutePath());
            String unlockRes = OctraNative.getInstance().unlockWallet(pin);
            JSONObject unlockJson = new JSONObject(unlockRes);
            return !unlockJson.has("error");
        } catch (Exception e) {
            return false;
        } finally {
            try {
                String restoreWalletId = previousWalletId == null || previousWalletId.trim().isEmpty()
                        ? WalletProfileStore.getSelectedWalletId(context)
                        : previousWalletId;
                java.io.File restoreDir = WalletProfileStore.getWalletDir(context, restoreWalletId);
                OctraNative.getInstance().lockWallet();
                OctraNative.getInstance().init(restoreDir.getAbsolutePath());
                if (previousPin != null && previousPin.matches("\\d{6}")) {
                    OctraNative.getInstance().unlockWallet(previousPin);
                }
            } catch (Exception ignored) {
            }
        }
    }
}
