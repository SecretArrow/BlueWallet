package com.octopus.wallet;

import android.content.Context;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javax.crypto.Mac;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * BIP-39 mnemonic generation + validation and Ed25519
 * hierarchical-deterministic key derivation.
 *
 * Flow:
 *   1. generate()  → random 12-word BIP-39 mnemonic (128-bit entropy)
 *   2. mnemonicToSeed()  → 64-byte BIP-39 seed via PBKDF2-HMAC-SHA512
 *   3. derivePrivateKeyBase64()  → 32-byte HD child seed (base64)
 *      → pass to OctraNative.importWallet(base64, pin)
 *
 * Note: Uses simplified HD derivation with hardened indices (0x80000000).
 *       Path format: m/44'/540'/0'/0'/0' (all components hardened)
 */
public class Bip39 {

    private final String[] wordList;
    private final Map<String, Integer> wordIndex;

    public Bip39(Context context) {
        List<String> words = new ArrayList<>(2048);
        try (InputStream is = context.getResources().openRawResource(R.raw.bip39_wordlist);
             BufferedReader reader = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String w = line.trim();
                if (!w.isEmpty()) words.add(w);
            }
        } catch (IOException e) {
            throw new RuntimeException("Failed to load BIP-39 wordlist", e);
        }
        wordList = words.toArray(new String[0]);
        wordIndex = new HashMap<>(wordList.length * 2);
        for (int i = 0; i < wordList.length; i++) {
            wordIndex.put(wordList[i], i);
        }
    }

    // ── Public API ──────────────────────────────────────────────────────────

    /** Generates a random 12-word BIP-39 mnemonic (128-bit entropy). */
    public String generate() {
        byte[] entropy = new byte[16];
        new SecureRandom().nextBytes(entropy);
        return entropyToMnemonic(entropy);
    }

    /** Returns true if the mnemonic is valid (word list + checksum). */
    public boolean validate(String mnemonic) {
        try {
            mnemonicToEntropy(mnemonic);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Produces the 32-byte SLIP-0010 child seed (base64-encoded) from a mnemonic
     * and derivation path. Pass this value to OctraNative.importWallet().
     *
     * @param mnemonic  12-word BIP-39 phrase
     * @param path      SLIP-0010 path, e.g. "m/44'/540'/0'/0'/0'"
     * @return          base64-encoded 32-byte Ed25519 seed
     */
    public String derivePrivateKeyBase64(String mnemonic, String path) {
        byte[] bip39Seed = mnemonicToSeed(mnemonic, "");
        byte[][] master = deriveMasterKey(bip39Seed);
        byte[] key = master[0];
        byte[] chain = master[1];

        for (int index : parsePath(path)) {
            byte[][] child = deriveChildKey(key, chain, index);
            key = child[0];
            chain = child[1];
        }
        return android.util.Base64.encodeToString(key, android.util.Base64.NO_WRAP);
    }

    /**
     * Parses a derivation path string and returns the component indices
     * (without the hardened bit — deriveChildKey adds it internally).
     */
    public int[] parsePath(String path) {
        String p = path.trim();
        if (p.startsWith("m/") || p.startsWith("M/")) p = p.substring(2);
        else if (p.equalsIgnoreCase("m")) return new int[0];

        String[] parts = p.split("/");
        int[] result = new int[parts.length];
        for (int i = 0; i < parts.length; i++) {
            String part = parts[i].trim();
            if (part.isEmpty()) throw new IllegalArgumentException("Empty path component");
            boolean hardened = part.endsWith("'");
            String num = hardened ? part.substring(0, part.length() - 1) : part;
            int n;
            try {
                n = Integer.parseInt(num);
            } catch (NumberFormatException e) {
                throw new IllegalArgumentException("Invalid path component: " + part);
            }
            if (n < 0) throw new IllegalArgumentException("Negative index: " + part);
            result[i] = n;
        }
        return result;
    }

    // ── BIP-39 internals ─────────────────────────────────────────────────────

    private String entropyToMnemonic(byte[] entropy) {
        byte[] hash = sha256(entropy);
        // 128 entropy bits + 4 checksum bits = 132 bits → 12 words of 11 bits
        boolean[] bits = new boolean[132];
        for (int i = 0; i < 128; i++) {
            bits[i] = ((entropy[i / 8] >> (7 - (i % 8))) & 1) == 1;
        }
        for (int i = 0; i < 4; i++) {
            bits[128 + i] = ((hash[0] >> (7 - i)) & 1) == 1;
        }
        StringBuilder sb = new StringBuilder();
        for (int w = 0; w < 12; w++) {
            int idx = 0;
            for (int b = 0; b < 11; b++) idx = (idx << 1) | (bits[w * 11 + b] ? 1 : 0);
            if (w > 0) sb.append(' ');
            sb.append(wordList[idx]);
        }
        return sb.toString();
    }

    private byte[] mnemonicToEntropy(String mnemonic) {
        String[] words = mnemonic.trim().split("\\s+");
        if (words.length != 12) throw new IllegalArgumentException("Expected 12 words");

        boolean[] bits = new boolean[132];
        for (int w = 0; w < 12; w++) {
            Integer idx = wordIndex.get(words[w]);
            if (idx == null) throw new IllegalArgumentException("Unknown word: " + words[w]);
            for (int b = 10; b >= 0; b--) bits[w * 11 + (10 - b)] = ((idx >> b) & 1) == 1;
        }
        byte[] entropy = new byte[16];
        for (int i = 0; i < 16; i++) {
            int val = 0;
            for (int b = 0; b < 8; b++) val = (val << 1) | (bits[i * 8 + b] ? 1 : 0);
            entropy[i] = (byte) val;
        }
        // Verify checksum
        byte[] hash = sha256(entropy);
        for (int b = 0; b < 4; b++) {
            if (((hash[0] >> (7 - b)) & 1) != (bits[128 + b] ? 1 : 0))
                throw new IllegalArgumentException("Checksum mismatch");
        }
        return entropy;
    }

    /** BIP-39: PBKDF2-HMAC-SHA512(mnemonic, "mnemonic", 2048, 64 bytes). */
    private byte[] mnemonicToSeed(String mnemonic, String passphrase) {
        try {
            char[] pw = mnemonic.toCharArray();
            byte[] salt = ("mnemonic" + (passphrase == null ? "" : passphrase))
                    .getBytes(StandardCharsets.UTF_8);
            PBEKeySpec spec = new PBEKeySpec(pw, salt, 2048, 512);
            byte[] key = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA512")
                    .generateSecret(spec).getEncoded();
            spec.clearPassword();
            return key;
        } catch (Exception e) {
            throw new RuntimeException("PBKDF2 failed", e);
        }
    }

    // ── SLIP-0010 Ed25519 ─────────────────────────────────────────────────────

    /** SLIP-0010 master key: HMAC-SHA512(key="ed25519 seed", data=seed). */
    private byte[][] deriveMasterKey(byte[] seed) {
        byte[] I = hmacSha512("ed25519 seed".getBytes(StandardCharsets.UTF_8), seed);
        return new byte[][]{Arrays.copyOfRange(I, 0, 32), Arrays.copyOfRange(I, 32, 64)};
    }

    /** SLIP-0010 hardened child key derivation (index is forced hardened). */
    private byte[][] deriveChildKey(byte[] key, byte[] chain, int index) {
        int i = index | 0x80000000;
        byte[] data = new byte[37];
        data[0] = 0x00;
        System.arraycopy(key, 0, data, 1, 32);
        data[33] = (byte) ((i >>> 24) & 0xff);
        data[34] = (byte) ((i >>> 16) & 0xff);
        data[35] = (byte) ((i >>> 8) & 0xff);
        data[36] = (byte) (i & 0xff);
        byte[] I = hmacSha512(chain, data);
        return new byte[][]{Arrays.copyOfRange(I, 0, 32), Arrays.copyOfRange(I, 32, 64)};
    }

    // ── Crypto helpers ────────────────────────────────────────────────────────

    private byte[] sha256(byte[] data) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(data);
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }

    private byte[] hmacSha512(byte[] key, byte[] data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA512");
            mac.init(new SecretKeySpec(key, "HmacSHA512"));
            return mac.doFinal(data);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
