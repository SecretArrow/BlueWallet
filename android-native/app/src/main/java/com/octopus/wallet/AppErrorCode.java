package com.octopus.wallet;

import java.util.Locale;

public final class AppErrorCode {
    private AppErrorCode() {
    }

    public static String withCode(String component, String message) {
        String safeComponent = sanitizeComponent(component);
        String safeMessage = message == null || message.trim().isEmpty() ? "Unknown error" : message.trim();
        return safeMessage + " (Code: " + codeFor(safeComponent, safeMessage) + ")";
    }

    public static String fromException(String component, String fallbackMessage, Throwable error) {
        String base = fallbackMessage == null || fallbackMessage.trim().isEmpty()
                ? "Operation failed"
                : fallbackMessage.trim();
        if (error != null && error.getMessage() != null && !error.getMessage().trim().isEmpty()) {
            base = base + ": " + error.getMessage().trim();
        }
        return withCode(component, base);
    }

    public static String codeFor(String component, String detail) {
        String safeComponent = sanitizeComponent(component);
        String payload = (safeComponent + "|" + (detail == null ? "" : detail)).toLowerCase(Locale.US);
        int hash = payload.hashCode() & 0x7fffffff;
        int shortHash = hash % 100000;
        return "ERR-" + safeComponent + "-" + String.format(Locale.US, "%05d", shortHash);
    }

    private static String sanitizeComponent(String component) {
        String raw = component == null ? "APP" : component.trim().toUpperCase(Locale.US);
        if (raw.isEmpty()) {
            raw = "APP";
        }
        raw = raw.replaceAll("[^A-Z0-9]", "");
        if (raw.isEmpty()) {
            raw = "APP";
        }
        if (raw.length() > 12) {
            raw = raw.substring(0, 12);
        }
        return raw;
    }
}
