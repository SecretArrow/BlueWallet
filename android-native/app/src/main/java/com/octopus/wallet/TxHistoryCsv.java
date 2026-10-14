package com.octopus.wallet;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;
import org.json.JSONObject;

/**
 * RFC 4180-compliant CSV builder for cached transaction history rows.
 *
 * <p>Mirrors the Flutter exporter's column layout: {@code
 * date,direction,type,op_type,amount,from,to,memo,fee,status,tx_hash,block_hash}. Fields containing
 * a comma, double quote, CR or LF are quoted and embedded quotes are doubled; every record
 * (including the header) ends with CRLF.
 *
 * <p>Pure JVM code (only {@code org.json}), so it is fully unit-testable.
 */
public final class TxHistoryCsv {

  private static final String[] HEADER = {
    "date",
    "direction",
    "type",
    "op_type",
    "amount",
    "from",
    "to",
    "memo",
    "fee",
    "status",
    "tx_hash",
    "block_hash",
  };

  private static final String DEFAULT_TYPE = "standard";
  private static final String DEFAULT_STATUS = "pending";

  private TxHistoryCsv() {}

  /**
   * Builds the CSV document for {@code rows} (kept in the given order).
   *
   * @param rows cached Room history rows; {@code null} is treated as empty
   */
  public static String build(List<TxHistoryEntity> rows) {
    return build(rows, null);
  }

  /**
   * Builds the CSV document for {@code rows} (kept in the given order).
   *
   * @param rows cached Room history rows; {@code null} is treated as empty
   * @param selfAddress the active wallet address; when known it drives the {@code direction} column
   *     the same way the history list does (sender == self, or type {@code sent} → outgoing)
   */
  public static String build(List<TxHistoryEntity> rows, String selfAddress) {
    StringBuilder out = new StringBuilder();
    appendRow(out, HEADER);
    if (rows == null) {
      return out.toString();
    }
    for (TxHistoryEntity row : rows) {
      if (row == null) {
        continue;
      }
      appendRow(out, rowValues(row, selfAddress));
    }
    return out.toString();
  }

  /** Escapes one CSV field per RFC 4180 (quote when needed, double quotes). */
  static String escapeField(String value) {
    if (value == null) {
      return "";
    }
    boolean needsQuotes =
        value.indexOf(',') >= 0
            || value.indexOf('"') >= 0
            || value.indexOf('\n') >= 0
            || value.indexOf('\r') >= 0;
    if (!needsQuotes) {
      return value;
    }
    return '"' + value.replace("\"", "\"\"") + '"';
  }

  private static void appendRow(StringBuilder out, String[] fields) {
    for (int i = 0; i < fields.length; i++) {
      if (i > 0) {
        out.append(',');
      }
      out.append(escapeField(fields[i]));
    }
    out.append('\r').append('\n');
  }

  private static String[] rowValues(TxHistoryEntity row, String selfAddress) {
    JSONObject tx = parseJson(row.txJson);

    String hash = firstNonEmpty(row.txHash, opt(tx, "hash"), opt(tx, "tx_hash"));
    String type = firstNonEmpty(opt(tx, "type"));
    String opType = firstNonEmpty(opt(tx, "op_type"));
    String from = firstNonEmpty(opt(tx, "from"), opt(tx, "from_"), opt(tx, "sender"));
    String to =
        firstNonEmpty(opt(tx, "to"), opt(tx, "to_"), opt(tx, "recipient"), opt(tx, "receiver"));
    String amount =
        firstNonEmpty(
            opt(tx, "amount_raw"),
            opt(tx, "value_raw"),
            opt(tx, "raw_amount"),
            opt(tx, "value"),
            opt(tx, "amount"));
    String memo = firstNonEmpty(opt(tx, "message"), opt(tx, "memo"));
    String fee =
        firstNonEmpty(opt(tx, "fee"), opt(tx, "ou"), opt(tx, "fee_raw"), opt(tx, "ou_fee"));
    String status =
        firstNonEmpty(
            opt(tx, "status"),
            opt(tx, "state"),
            opt(tx, "tx_status"),
            opt(tx, "result"),
            opt(tx, "final_status"));

    return new String[] {
      isoDate(row.timestamp),
      direction(type, from, selfAddress),
      type.isEmpty() ? DEFAULT_TYPE : type,
      opType.isEmpty() ? DEFAULT_TYPE : opType,
      amount.isEmpty() ? "0" : amount,
      from,
      to,
      memo,
      fee,
      status.isEmpty() ? DEFAULT_STATUS : status,
      hash,
      opt(tx, "block_hash"),
    };
  }

  /** ISO 8601 / UTC date; empty when the sort timestamp is unknown. */
  private static String isoDate(long timestampMs) {
    if (timestampMs <= 0L) {
      return "";
    }
    SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
    sdf.setTimeZone(TimeZone.getTimeZone("UTC"));
    return sdf.format(new Date(timestampMs));
  }

  /**
   * Direction derivation matching the history list rows: with a known self address, sender == self
   * (or type {@code sent}) → {@code outgoing}, otherwise {@code incoming}. Without it, {@code
   * sent}/{@code received} map directly and other types pass through unchanged.
   */
  private static String direction(String type, String from, String selfAddress) {
    boolean selfKnown = selfAddress != null && !selfAddress.trim().isEmpty();
    if (selfKnown) {
      boolean isSent = "sent".equals(type) || from.equalsIgnoreCase(selfAddress.trim());
      return isSent ? "outgoing" : "incoming";
    }
    if ("sent".equals(type)) {
      return "outgoing";
    }
    if ("received".equals(type)) {
      return "incoming";
    }
    return type;
  }

  private static JSONObject parseJson(String json) {
    if (json == null || json.trim().isEmpty()) {
      return null;
    }
    try {
      return new JSONObject(json);
    } catch (Exception e) {
      return null;
    }
  }

  private static String opt(JSONObject tx, String key) {
    if (tx == null) {
      return "";
    }
    String value = tx.optString(key, "");
    return value == null ? "" : value.trim();
  }

  private static String firstNonEmpty(String... values) {
    for (String value : values) {
      if (value != null && !value.trim().isEmpty()) {
        return value.trim();
      }
    }
    return "";
  }
}
