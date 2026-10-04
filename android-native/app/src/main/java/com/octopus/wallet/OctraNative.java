package com.octopus.wallet;

public class OctraNative {
    
    private static OctraNative instance;
    
    static {
        System.loadLibrary("octra_wallet_native");
    }
    
    private OctraNative() {}
    
    public static synchronized OctraNative getInstance() {
        if (instance == null) {
            instance = new OctraNative();
        }
        return instance;
    }
    
    public native void init(String dataDir);
    
    public native boolean hasEncryptedWallet();
    public native boolean isWalletLoaded();
    
    public native String createWallet(String pin);
    
    public native String importWallet(String privateKey, String pin);
    
    public native String unlockWallet(String pin);
    
    public native void lockWallet();
    
    public native String getWalletInfo();

    public native String getPrivateKey();

    public native String getViewPublicKey();
    
    public native String signTransaction(String toAddress, String amount, int nonce, String message);

    public native String signContractCallTx(String tokenAddress, String toAddress,
                                            String amount, int nonce, String ou);
    
    public native String signGenericContractCallTx(String contractAddress, String method,
                                                   String paramsJson, String amount, int nonce, String ou);
    
    public native String signEncryptTx(String amount, int nonce, String cipher, 
                                        String zeroProof, String amountCommitment, String blinding);
    
    public native String signDecryptTx(String amount, int nonce, String cipher,
                                        String zeroProof, String amountCommitment, String blinding);

    public native String signBalanceRequest();

    public native String changePin(String currentPin, String newPin);
    
    public native String saveSettings(String rpcUrl, String explorerUrl);

    public native byte[] generateRandomBytes(int len);
    public native String base64Encode(byte[] data);
    public native byte[] base64Decode(String data);
    public native String sha256(byte[] data);

    // pvac pubkey registration
    public native String getPvacPubkey();
    public native String signPvacRegister();
    public native String getPublicKeyB64();
    public native long decryptEncryptedBalanceCipher(String cipher);

    // stealth send
    public native String stealthPrepare(String theirViewPubkeyB64, String recipientAddr);
    public native String signStealthSendTx(String amount, int nonce,
                                            String currentEncCipher,
                                            String ephPubB64,
                                            String stealthTagHex,
                                            String claimPubHex,
                                            String encAmountB64,
                                            String blindingB64,
                                            String amtCommitB64);

    // HD wallet support
    public native String importWalletMnemonic(String mnemonic, String pin);
    public native String importWalletMnemonicWithVersion(String mnemonic, String pin, int hdVersion);
    public native String deriveAddressFromMnemonic(String mnemonic, int hdVersion);
    public native String deriveHdAccount(String masterSeed, int index,
                                          String rpcUrl, String explorerUrl, String pin);
    public native String getWalletHdInfo();

    // AES-KAT for PVAC
    public native String computeAesKat();

    // Key Switch transaction
    public native String signKeySwitchTx();

    // ---------- Cache Functions (Features 2-4) ----------
    public native String getCachedFee();
    public native void cacheFee(String feeJson);
    public native String getTxCache(String key);
    public native void putTxCache(String key, String value);

    // ---------- Polling (Feature 6) ----------
    public native boolean isPolling();
    public native void startPolling();
    public native void stopPolling();

    // ---------- Stealth Scanning (Feature 5) ----------
    public native boolean isStealthScanning();
    public native void startStealthScan();

    // ---------- FHE and General Transaction Signing (Feature Porting) ----------
    public native String fheEncrypt(long value);
    public native String fheDecrypt(String ciphertext);
    public native String signGeneralTransaction(String toAddress, String amount, int nonce, String ou, String opType, String message, String encryptedData);
}
