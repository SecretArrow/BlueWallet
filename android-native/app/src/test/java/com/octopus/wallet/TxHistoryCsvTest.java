package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

/**
 * Pure-JVM tests for the RFC 4180 transaction history CSV builder: escaping, header layout, CRLF
 * record terminators and field resolution from the cached tx JSON.
 */
public class TxHistoryCsvTest {

  private static final String HEADER_LINE =
      "date,direction,type,op_type,amount,from,to,memo,fee,status,tx_hash,block_hash";

  private static TxHistoryEntity entity(String hash, String json, long timestamp) {
    return TxHistoryEntity.create("w1", hash, json, timestamp);
  }

  @Test
  public void emptyList_isHeaderOnly() throws Exception {
    assertEquals(HEADER_LINE + "\r\n", TxHistoryCsv.build(null));
    assertEquals(HEADER_LINE + "\r\n", TxHistoryCsv.build(new java.util.ArrayList<>()));
  }

  @Test
  public void headerRow_isFirstLine_withCrlf() throws Exception {
    String csv = TxHistoryCsv.build(new java.util.ArrayList<>());
    assertTrue(csv.startsWith(HEADER_LINE));
    assertTrue(csv.endsWith("\r\n"));
  }

  @Test
  public void rows_preserveInputOrder() throws Exception {
    JSONObject a = new JSONObject().put("amount", "1").put("type", "sent");
    JSONObject b = new JSONObject().put("amount", "2").put("type", "sent");
    String csv =
        TxHistoryCsv.build(
            java.util.Arrays.asList(
                entity("h1", a.toString(), 1L), entity("h2", b.toString(), 2L)));
    assertTrue(csv.indexOf("h1") < csv.indexOf("h2"));
  }

  @Test
  public void everyRecordEndsWithCrlf_noBareLineFeeds() throws Exception {
    JSONObject plain = new JSONObject().put("memo", "no special chars");
    String csv =
        TxHistoryCsv.build(
            java.util.Arrays.asList(
                entity("h1", plain.toString(), 1000L), entity("h2", plain.toString(), 2000L)));
    assertTrue(csv.endsWith("\r\n"));
    // Two data rows + header → exactly three CRLF terminators, and after
    // removing them no LF or CR may remain.
    assertEquals(3, csv.split("\r\n", -1).length - 1);
    String stripped = csv.replace("\r\n", "");
    assertFalse(stripped.contains("\n"));
    assertFalse(stripped.contains("\r"));
  }

  @Test
  public void fieldContainingComma_isQuoted() throws Exception {
    JSONObject tx = new JSONObject().put("message", "lunch, coffee");
    String csv =
        TxHistoryCsv.build(java.util.Collections.singletonList(entity("h1", tx.toString(), 0L)));
    assertTrue(csv.contains("\"lunch, coffee\""));
  }

  @Test
  public void quotes_areDoubledInsideQuotedField() throws Exception {
    JSONObject tx = new JSONObject().put("message", "say \"hi\"");
    String csv =
        TxHistoryCsv.build(java.util.Collections.singletonList(entity("h1", tx.toString(), 0L)));
    assertTrue(csv.contains("\"say \"\"hi\"\"\""));
  }

  @Test
  public void newlineInsideField_isQuotedAndPreserved() throws Exception {
    JSONObject tx = new JSONObject().put("message", "line1\nline2");
    String csv =
        TxHistoryCsv.build(java.util.Collections.singletonList(entity("h1", tx.toString(), 0L)));
    assertTrue(csv.contains("\"line1\nline2\""));
  }

  @Test
  public void plainFields_areEmittedUnquoted() throws Exception {
    JSONObject tx =
        new JSONObject()
            .put("type", "sent")
            .put("op_type", "standard")
            .put("amount", "1500000")
            .put("from", "oct_from")
            .put("to", "oct_to")
            .put("status", "confirmed");
    String csv =
        TxHistoryCsv.build(java.util.Collections.singletonList(entity("hash1", tx.toString(), 0L)));
    // date empty (timestamp 0) → row starts with the direction column.
    assertTrue(csv.contains("\r\noutgoing,sent,standard,1500000,oct_from,oct_to,"));
    assertTrue(csv.contains(",confirmed,hash1,"));
    assertFalse(csv.contains("\""));
  }

  @Test
  public void direction_usesSelfAddressAndType() throws Exception {
    JSONObject sent = new JSONObject().put("type", "sent").put("from", "oct_alice");
    JSONObject received = new JSONObject().put("type", "received").put("from", "oct_alice");
    String csv =
        TxHistoryCsv.build(
            java.util.Arrays.asList(
                entity("h1", sent.toString(), 0L), entity("h2", received.toString(), 0L)),
            "oct_me");
    assertTrue(csv.contains("outgoing,sent,"));
    assertTrue(csv.contains("incoming,received,"));

    // Without a self address, unknown types pass through unchanged.
    JSONObject encrypted = new JSONObject().put("type", "encrypted").put("from", "oct_alice");
    String bare =
        TxHistoryCsv.build(
            java.util.Collections.singletonList(entity("h3", encrypted.toString(), 0L)));
    assertTrue(bare.contains("encrypted,encrypted,"));
  }

  @Test
  public void amount_resolvesRawChainAndDefaults() throws Exception {
    JSONObject raw = new JSONObject().put("amount_raw", "2500000");
    JSONObject none = new JSONObject().put("hash", "h-none");
    String csv =
        TxHistoryCsv.build(
            java.util.Arrays.asList(
                entity("h1", raw.toString(), 0L), entity("h2", none.toString(), 0L)));
    assertTrue(csv.contains(",2500000,"));
    // Missing amount falls back to 0; missing status defaults to pending.
    assertTrue(csv.contains(",0,"));
    assertTrue(csv.contains(",pending,h2,"));
  }

  @Test
  public void date_isIso8601Utc_andEmptyWhenUnknown() throws Exception {
    java.util.Calendar cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"));
    cal.clear();
    cal.set(2026, java.util.Calendar.FEBRUARY, 2, 2, 40, 0);
    long ts = cal.getTimeInMillis();
    String csv = TxHistoryCsv.build(java.util.Collections.singletonList(entity("h1", "{}", ts)));
    assertTrue(csv.contains("2026-02-02T02:40:00.000Z"));

    String unknown =
        TxHistoryCsv.build(java.util.Collections.singletonList(entity("h2", "{}", 0L)));
    // Row starts with an empty date column.
    assertTrue(unknown.contains("\r\n,"));
  }

  @Test
  public void entityFields_usedWhenJsonLacksThem() throws Exception {
    // txHash comes from the entity itself; type/op_type default to standard.
    String csv =
        TxHistoryCsv.build(
            java.util.Collections.singletonList(entity("entityhash", "{}", 0L)), "oct_me");
    assertTrue(csv.contains("standard,standard,0,,,,,pending,entityhash,"));
  }
}
