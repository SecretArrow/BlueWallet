#include "crypto_utils.hpp"
#include "json.hpp"
#include "pvac_bridge.hpp"
#include "stealth.hpp"
#include "stealth_scanner_simple.hpp"
#include "tx_builder.hpp"
#include "wallet.hpp"
#include "txcache_simple.hpp"
#include "rpc_client.hpp"
#include <cctype>
#include <ctime>
#include <jni.h>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <chrono>

using json = nlohmann::json;

static std::unique_ptr<octra::Wallet> g_wallet;
static std::mutex g_mtx;
static std::string g_data_dir;
static std::string g_pin;
static octra::PvacBridge g_pvac;
static bool g_pvac_ok = false;

// Cache mechanisms (features 2-4)
static TxCache g_txcache;
static json g_fee_cache;
static double g_fee_cache_ts = 0.0;
static std::mutex g_fee_mtx;

static std::unordered_map<std::string, std::vector<uint8_t>> g_pk_cache;
static std::mutex g_pk_mtx;

static std::optional<std::vector<uint8_t>> pk_cache_get(const std::string& addr) {
    std::lock_guard<std::mutex> lk(g_pk_mtx);
    auto it = g_pk_cache.find(addr);
    if (it == g_pk_cache.end()) return std::nullopt;
    return it->second;
}

static void pk_cache_put(const std::string& addr, const std::vector<uint8_t>& pk) {
    if (pk.size() != 32) return;
    std::lock_guard<std::mutex> lk(g_pk_mtx);
    if (g_pk_cache.size() > 2048) g_pk_cache.clear();
    g_pk_cache[addr] = pk;
}

static double now_ts() {
    auto d = std::chrono::system_clock::now().time_since_epoch();
    return std::chrono::duration<double>(d).count();
}

// Stealth scanning (feature 5)
static std::unique_ptr<octra::StealthScanner> g_scanner;
static std::mutex g_scanner_mtx;
static std::atomic<bool> g_scanning{false};

// Auto-polling thread (feature 6)
static std::atomic<bool> g_polling{false};
static std::unique_ptr<std::thread> g_poll_thread;

static void init_pvac_for_loaded_wallet() {
  g_pvac_ok = false;
  g_pvac.reset();
  if (!g_wallet) {
    return;
  }
  g_pvac_ok = g_pvac.init(g_wallet->priv_b64);
}

static bool is_valid_pin(const std::string &pin) {
  if (pin.size() != 6) {
    return false;
  }
  for (char c : pin) {
    if (!std::isdigit(static_cast<unsigned char>(c))) {
      return false;
    }
  }
  return true;
}

extern "C" {

JNIEXPORT void JNICALL Java_com_octopus_wallet_OctraNative_init(JNIEnv *env,
                                                             jobject thiz,
                                                             jstring data_dir) {
  const char *dir = env->GetStringUTFChars(data_dir, nullptr);
  g_data_dir = std::string(dir);
  env->ReleaseStringUTFChars(data_dir, dir);
  LOGD("Native layer initialized with data dir: %s", g_data_dir.c_str());
}

JNIEXPORT jboolean JNICALL
Java_com_octopus_wallet_OctraNative_hasEncryptedWallet(JNIEnv *env, jobject thiz) {
  return octra::has_encrypted_wallet(g_data_dir) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_octopus_wallet_OctraNative_hasLegacyWallet(JNIEnv *env, jobject thiz) {
  return octra::has_legacy_wallet(g_data_dir) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_octopus_wallet_OctraNative_isWalletLoaded(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  return g_wallet != nullptr ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_createWallet(
    JNIEnv *env, jobject thiz, jstring pin_str) {
  std::lock_guard<std::mutex> lock(g_mtx);
  try {
    const char *pin = env->GetStringUTFChars(pin_str, nullptr);
    std::string pin_s(pin);
    env->ReleaseStringUTFChars(pin_str, pin);

    if (!is_valid_pin(pin_s)) {
      return env->NewStringUTF("{\"error\":\"PIN must be 6 digits\"}");
    }

    std::string wallet_path = g_data_dir + "/wallet.oct";
    g_wallet = std::make_unique<octra::Wallet>(
        octra::create_wallet(wallet_path, pin_s));
    g_pin = pin_s;
    init_pvac_for_loaded_wallet();

    json result;
    result["address"] = g_wallet->addr;
    result["public_key"] = g_wallet->pub_b64;
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_importWallet(
    JNIEnv *env, jobject thiz, jstring priv_str, jstring pin_str) {
  std::lock_guard<std::mutex> lock(g_mtx);
  try {
    const char *priv = env->GetStringUTFChars(priv_str, nullptr);
    const char *pin = env->GetStringUTFChars(pin_str, nullptr);
    std::string priv_s(priv);
    std::string pin_s(pin);
    env->ReleaseStringUTFChars(priv_str, priv);
    env->ReleaseStringUTFChars(pin_str, pin);

    if (!is_valid_pin(pin_s)) {
      return env->NewStringUTF("{\"error\":\"PIN must be 6 digits\"}");
    }

    std::string wallet_path = g_data_dir + "/wallet.oct";
    g_wallet = std::make_unique<octra::Wallet>(
        octra::import_wallet(wallet_path, priv_s, pin_s));
    g_pin = pin_s;
    init_pvac_for_loaded_wallet();

    json result;
    result["address"] = g_wallet->addr;
    result["public_key"] = g_wallet->pub_b64;
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_unlockWallet(
    JNIEnv *env, jobject thiz, jstring pin_str) {
  std::lock_guard<std::mutex> lock(g_mtx);
  try {
    const char *pin = env->GetStringUTFChars(pin_str, nullptr);
    std::string pin_s(pin);
    env->ReleaseStringUTFChars(pin_str, pin);

    std::string wallet_path = g_data_dir + "/wallet.oct";
    g_wallet = std::make_unique<octra::Wallet>(
        octra::load_wallet_encrypted(wallet_path, pin_s));
    g_pin = pin_s;
    init_pvac_for_loaded_wallet();

    json result;
    result["address"] = g_wallet->addr;
    result["public_key"] = g_wallet->pub_b64;
    result["rpc_url"] = g_wallet->rpc_url;
    result["explorer_url"] = g_wallet->explorer_url;
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT void JNICALL
Java_com_octopus_wallet_OctraNative_lockWallet(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (g_wallet) {
    octra::secure_zero(g_wallet->sk, 64);
    octra::secure_zero(g_wallet->pk, 32);
    g_wallet.reset();
  }
  if (!g_pin.empty()) {
    octra::secure_zero(&g_pin[0], g_pin.size());
    g_pin.clear();
  }
  g_pvac.reset();
  g_pvac_ok = false;
}

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_getWalletInfo(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }

  json result;
  result["address"] = g_wallet->addr;
  result["public_key"] = g_wallet->pub_b64;
  result["rpc_url"] = g_wallet->rpc_url;
  result["explorer_url"] = g_wallet->explorer_url;
  return env->NewStringUTF(result.dump().c_str());
}

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_getPrivateKey(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("");
  }
  return env->NewStringUTF(g_wallet->priv_b64.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_getViewPublicKey(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("");
  }

  uint8_t view_sk[32], view_pk[32];
  octra::derive_view_keypair(g_wallet->sk, view_sk, view_pk);
  std::string result = octra::base64_encode(view_pk, 32);
  octra::secure_zero(view_sk, 32);
  return env->NewStringUTF(result.c_str());
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_signTransaction(
    JNIEnv *env, jobject thiz, jstring to_addr, jstring amount, jint nonce,
    jstring message) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }

  try {
    const char *to = env->GetStringUTFChars(to_addr, nullptr);
    const char *amt = env->GetStringUTFChars(amount, nullptr);
    const char *msg =
        message ? env->GetStringUTFChars(message, nullptr) : nullptr;

    octra::Transaction tx;
    tx.from = g_wallet->addr;
    tx.to_ = std::string(to);
    tx.amount = std::string(amt);
    tx.nonce = nonce;
    tx.ou = "10000";
    tx.timestamp = static_cast<double>(std::time(nullptr)) + 0.0;
    tx.op_type = "standard";
    if (msg)
      tx.message = std::string(msg);

    octra::sign_transaction(tx, g_wallet->sk);
    tx.public_key = g_wallet->pub_b64;

    env->ReleaseStringUTFChars(to_addr, to);
    env->ReleaseStringUTFChars(amount, amt);
    if (msg)
      env->ReleaseStringUTFChars(message, msg);

    json result = octra::build_tx_json(tx);
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_signContractCallTx(
    JNIEnv *env, jobject thiz, jstring token_addr, jstring to_addr,
    jstring amount, jint nonce, jstring ou) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }

  try {
    const char *token = env->GetStringUTFChars(token_addr, nullptr);
    const char *to = env->GetStringUTFChars(to_addr, nullptr);
    const char *amt = env->GetStringUTFChars(amount, nullptr);
    const char *ou_str = ou ? env->GetStringUTFChars(ou, nullptr) : nullptr;

    std::string token_s(token ? token : "");
    std::string to_s(to ? to : "");
    std::string amt_s(amt ? amt : "0");
    std::string ou_s(ou_str ? ou_str : "1000");

    env->ReleaseStringUTFChars(token_addr, token);
    env->ReleaseStringUTFChars(to_addr, to);
    env->ReleaseStringUTFChars(amount, amt);
    if (ou_str)
      env->ReleaseStringUTFChars(ou, ou_str);

    if (token_s.empty() || to_s.empty()) {
      return env->NewStringUTF(
          "{\"error\":\"token address or recipient missing\"}");
    }

    long long amount_val = 0;
    try {
      amount_val = std::stoll(amt_s);
    } catch (...) {
      return env->NewStringUTF("{\"error\":\"invalid amount\"}");
    }
    if (amount_val <= 0) {
      return env->NewStringUTF("{\"error\":\"amount must be positive\"}");
    }

    octra::Transaction tx;
    tx.from = g_wallet->addr;
    tx.to_ = token_s;
    tx.amount = "0";
    tx.nonce = nonce;
    tx.ou = ou_s.empty() ? "1000" : ou_s;
    tx.timestamp = static_cast<double>(std::time(nullptr)) + 0.0;
    tx.op_type = "call";
    tx.encrypted_data = "transfer";

    json params = json::array({to_s, amount_val});
    tx.message = params.dump();

    octra::sign_transaction(tx, g_wallet->sk);
    tx.public_key = g_wallet->pub_b64;

    json result = octra::build_tx_json(tx);
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_signGenericContractCallTx(
    JNIEnv *env, jobject thiz, jstring contract_addr, jstring method,
    jstring params_json, jstring amount, jint nonce, jstring ou) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }

  try {
    const char *contract = env->GetStringUTFChars(contract_addr, nullptr);
    const char *meth = env->GetStringUTFChars(method, nullptr);
    const char *params = params_json ? env->GetStringUTFChars(params_json, nullptr) : nullptr;
    const char *amt = env->GetStringUTFChars(amount, nullptr);
    const char *ou_str = ou ? env->GetStringUTFChars(ou, nullptr) : nullptr;

    std::string contract_s(contract ? contract : "");
    std::string method_s(meth ? meth : "");
    std::string params_s(params ? params : "[]");
    std::string amt_s(amt ? amt : "0");
    std::string ou_s(ou_str ? ou_str : "1000");

    env->ReleaseStringUTFChars(contract_addr, contract);
    env->ReleaseStringUTFChars(method, meth);
    if (params)
      env->ReleaseStringUTFChars(params_json, params);
    env->ReleaseStringUTFChars(amount, amt);
    if (ou_str)
      env->ReleaseStringUTFChars(ou, ou_str);

    if (contract_s.empty() || method_s.empty()) {
      return env->NewStringUTF("{\"error\":\"contract address or method missing\"}");
    }

    octra::Transaction tx;
    tx.from = g_wallet->addr;
    tx.to_ = contract_s;
    tx.amount = amt_s;
    tx.nonce = nonce;
    tx.ou = ou_s;
    tx.timestamp = static_cast<double>(std::time(nullptr)) + 0.0;
    tx.op_type = "call";
    tx.encrypted_data = method_s;
    tx.message = params_s;

    octra::sign_transaction(tx, g_wallet->sk);
    tx.public_key = g_wallet->pub_b64;

    json result = octra::build_tx_json(tx);
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_signEncryptTx(
    JNIEnv *env, jobject thiz, jstring amount, jint nonce, jstring cipher,
    jstring zero_proof, jstring amount_commitment, jstring blinding) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }
  if (!g_pvac_ok) {
    return env->NewStringUTF("{\"error\":\"pvac not available\"}");
  }

  try {
    const char *amt = env->GetStringUTFChars(amount, nullptr);
    const char *cph = env->GetStringUTFChars(cipher, nullptr);
    const char *zp = env->GetStringUTFChars(zero_proof, nullptr);
    const char *ac = env->GetStringUTFChars(amount_commitment, nullptr);
    const char *bl = env->GetStringUTFChars(blinding, nullptr);

    std::string amt_s(amt ? amt : "0");
    std::string cph_s(cph ? cph : "");
    std::string zp_s(zp ? zp : "");
    std::string ac_s(ac ? ac : "");
    std::string bl_s(bl ? bl : "");

    env->ReleaseStringUTFChars(amount, amt);
    env->ReleaseStringUTFChars(cipher, cph);
    env->ReleaseStringUTFChars(zero_proof, zp);
    env->ReleaseStringUTFChars(amount_commitment, ac);
    env->ReleaseStringUTFChars(blinding, bl);

    uint64_t amount_u64 = std::stoull(amt_s);
    if (amount_u64 == 0) {
      return env->NewStringUTF("{\"error\":\"invalid amount\"}");
    }

    if (cph_s.empty() || zp_s.empty() || ac_s.empty() || bl_s.empty()) {
      uint8_t seed[32];
      octra::random_bytes(seed, 32);
      pvac_cipher ct = g_pvac.encrypt(amount_u64, seed);
      if (!ct) {
        return env->NewStringUTF("{\"error\":\"failed to encrypt amount\"}");
      }

      uint8_t blind_buf[32];
      octra::random_bytes(blind_buf, 32);
      auto commit = g_pvac.pedersen_commit(amount_u64, blind_buf);
      pvac_zero_proof proof =
          g_pvac.make_zero_proof_bound(ct, amount_u64, blind_buf);
      if (!proof) {
        g_pvac.free_cipher(ct);
        return env->NewStringUTF("{\"error\":\"failed to build zero proof\"}");
      }

      cph_s = g_pvac.encode_cipher(ct);
      ac_s = octra::base64_encode(commit.data(), commit.size());
      zp_s = g_pvac.encode_zero_proof(proof);
      bl_s = octra::base64_encode(blind_buf, 32);

      g_pvac.free_zero_proof(proof);
      g_pvac.free_cipher(ct);
    }

    json enc_data;
    enc_data["cipher"] = cph_s;
    enc_data["amount_commitment"] = ac_s;
    enc_data["zero_proof"] = zp_s;
    enc_data["blinding"] = bl_s;

    octra::Transaction tx;
    tx.from = g_wallet->addr;
    tx.to_ = g_wallet->addr;
    tx.amount = amt_s;
    tx.nonce = nonce;
    tx.ou = "10000";
    tx.timestamp = static_cast<double>(std::time(nullptr)) + 0.0;
    tx.op_type = "encrypt";
    tx.encrypted_data = enc_data.dump();

    octra::sign_transaction(tx, g_wallet->sk);
    tx.public_key = g_wallet->pub_b64;

    json result = octra::build_tx_json(tx);
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_signDecryptTx(
    JNIEnv *env, jobject thiz, jstring amount, jint nonce, jstring cipher,
    jstring zero_proof, jstring amount_commitment, jstring blinding) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }
  if (!g_pvac_ok) {
    return env->NewStringUTF("{\"error\":\"pvac not available\"}");
  }

  try {
    const char *amt = env->GetStringUTFChars(amount, nullptr);
    const char *cph = env->GetStringUTFChars(cipher, nullptr);
    const char *zp = env->GetStringUTFChars(zero_proof, nullptr);
    const char *ac = env->GetStringUTFChars(amount_commitment, nullptr);
    const char *bl = env->GetStringUTFChars(blinding, nullptr);

    std::string amt_s(amt ? amt : "0");
    std::string cph_s(cph ? cph : "");
    std::string zp_s(zp ? zp : "");
    std::string ac_s(ac ? ac : "");
    std::string bl_s(bl ? bl : "");

    env->ReleaseStringUTFChars(amount, amt);
    env->ReleaseStringUTFChars(cipher, cph);
    env->ReleaseStringUTFChars(zero_proof, zp);
    env->ReleaseStringUTFChars(amount_commitment, ac);
    env->ReleaseStringUTFChars(blinding, bl);

    uint64_t amount_u64 = std::stoull(amt_s);
    if (amount_u64 == 0) {
      return env->NewStringUTF("{\"error\":\"invalid amount\"}");
    }

    if (cph_s.empty() || zp_s.empty() || ac_s.empty() || bl_s.empty()) {
      uint8_t seed[32];
      octra::random_bytes(seed, 32);
      pvac_cipher ct = g_pvac.encrypt(amount_u64, seed);
      if (!ct) {
        return env->NewStringUTF("{\"error\":\"failed to encrypt amount\"}");
      }

      uint8_t blind_buf[32];
      octra::random_bytes(blind_buf, 32);
      auto commit = g_pvac.pedersen_commit(amount_u64, blind_buf);
      pvac_zero_proof proof =
          g_pvac.make_zero_proof_bound(ct, amount_u64, blind_buf);
      if (!proof) {
        g_pvac.free_cipher(ct);
        return env->NewStringUTF("{\"error\":\"failed to build zero proof\"}");
      }

      cph_s = g_pvac.encode_cipher(ct);
      ac_s = octra::base64_encode(commit.data(), commit.size());
      zp_s = g_pvac.encode_zero_proof(proof);
      bl_s = octra::base64_encode(blind_buf, 32);

      g_pvac.free_zero_proof(proof);
      g_pvac.free_cipher(ct);
    }

    json enc_data;
    enc_data["cipher"] = cph_s;
    enc_data["amount_commitment"] = ac_s;
    enc_data["zero_proof"] = zp_s;
    enc_data["blinding"] = bl_s;

    // Build aggregated range proof for new balance (matching webcli)
    int64_t enc_bal = g_pvac.get_balance(cph_s);
    if (enc_bal < (int64_t)amount_u64) {
      char msg[128];
      snprintf(msg, sizeof(msg),
               "insufficient encrypted balance: have %ld, need %lu",
               (long)enc_bal, (unsigned long)amount_u64);
      json err;
      err["error"] = std::string(msg);
      return env->NewStringUTF(err.dump().c_str());
    }

    // Create new balance cipher and aggregated range proof
    pvac_cipher current_ct = g_pvac.decode_cipher(cph_s);
    if (!current_ct) {
      return env->NewStringUTF(
          "{\"error\":\"failed to decode current cipher\"}");
    }

    uint8_t seed[32];
    octra::random_bytes(seed, 32);
    pvac_cipher delta_ct = g_pvac.encrypt(amount_u64, seed);
    if (!delta_ct) {
      g_pvac.free_cipher(current_ct);
      return env->NewStringUTF("{\"error\":\"failed to encrypt delta\"}");
    }

    pvac_cipher new_ct = g_pvac.ct_sub(current_ct, delta_ct);
    uint64_t new_val = (uint64_t)(enc_bal - (int64_t)amount_u64);

    // Aggregated range proof for new balance (more efficient than simple proof)
    pvac_agg_range_proof arp =
        g_pvac.make_aggregated_range_proof(new_ct, new_val);
    if (!arp) {
      g_pvac.free_cipher(new_ct);
      g_pvac.free_cipher(delta_ct);
      g_pvac.free_cipher(current_ct);
      return env->NewStringUTF(
          "{\"error\":\"failed to build aggregated range proof\"}");
    }

    std::string rp_bal_str = g_pvac.encode_agg_range_proof(arp);
    enc_data["range_proof_balance"] = rp_bal_str;

    g_pvac.free_agg_range_proof(arp);
    g_pvac.free_cipher(new_ct);
    g_pvac.free_cipher(delta_ct);
    g_pvac.free_cipher(current_ct);

    octra::Transaction tx;
    tx.from = g_wallet->addr;
    tx.to_ = g_wallet->addr;
    tx.amount = amt_s;
    tx.nonce = nonce;
    tx.ou = "10000";
    tx.timestamp = static_cast<double>(std::time(nullptr)) + 0.0;
    tx.op_type = "decrypt";
    tx.encrypted_data = enc_data.dump();

    octra::sign_transaction(tx, g_wallet->sk);
    tx.public_key = g_wallet->pub_b64;

    json result = octra::build_tx_json(tx);
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_signBalanceRequest(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("");
  }

  std::string sig = octra::sign_balance_request(g_wallet->addr, g_wallet->sk);
  return env->NewStringUTF(sig.c_str());
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_changePin(
    JNIEnv *env, jobject thiz, jstring current_pin, jstring new_pin) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }

  try {
    const char *cur = env->GetStringUTFChars(current_pin, nullptr);
    const char *newp = env->GetStringUTFChars(new_pin, nullptr);
    std::string cur_s(cur);
    std::string new_s(newp);
    env->ReleaseStringUTFChars(current_pin, cur);
    env->ReleaseStringUTFChars(new_pin, newp);

    if (cur_s != g_pin) {
      return env->NewStringUTF("{\"error\":\"wrong current PIN\"}");
    }

    if (!is_valid_pin(new_s)) {
      return env->NewStringUTF("{\"error\":\"new PIN must be 6 digits\"}");
    }

    std::string wallet_path = g_data_dir + "/wallet.oct";
    octra::change_pin(wallet_path, *g_wallet, new_s);
    octra::secure_zero(&g_pin[0], g_pin.size());
    g_pin = new_s;

    return env->NewStringUTF("{\"ok\":true}");
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_saveSettings(
    JNIEnv *env, jobject thiz, jstring rpc_url, jstring explorer_url) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }

  try {
    const char *rpc = env->GetStringUTFChars(rpc_url, nullptr);
    const char *exp =
        explorer_url ? env->GetStringUTFChars(explorer_url, nullptr) : nullptr;
    std::string rpc_s(rpc);
    std::string exp_s = exp ? std::string(exp) : g_wallet->explorer_url;
    env->ReleaseStringUTFChars(rpc_url, rpc);
    if (exp)
      env->ReleaseStringUTFChars(explorer_url, exp);

    g_wallet->explorer_url = exp_s;
    std::string wallet_path = g_data_dir + "/wallet.oct";
    octra::save_settings(wallet_path, *g_wallet, rpc_s, g_pin);

    json result;
    result["ok"] = true;
    result["rpc_url"] = g_wallet->rpc_url;
    result["explorer_url"] = g_wallet->explorer_url;
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jbyteArray JNICALL
Java_com_octopus_wallet_OctraNative_generateRandomBytes(JNIEnv *env, jobject thiz,
                                                     jint len) {
  std::vector<uint8_t> buf(len);
  octra::random_bytes(buf.data(), len);
  jbyteArray result = env->NewByteArray(len);
  env->SetByteArrayRegion(result, 0, len,
                          reinterpret_cast<jbyte *>(buf.data()));
  return result;
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_base64Encode(
    JNIEnv *env, jobject thiz, jbyteArray data) {
  jsize len = env->GetArrayLength(data);
  std::vector<uint8_t> buf(len);
  env->GetByteArrayRegion(data, 0, len, reinterpret_cast<jbyte *>(buf.data()));
  std::string result = octra::base64_encode(buf.data(), buf.size());
  return env->NewStringUTF(result.c_str());
}

JNIEXPORT jbyteArray JNICALL Java_com_octopus_wallet_OctraNative_base64Decode(
    JNIEnv *env, jobject thiz, jstring data) {
  const char *str = env->GetStringUTFChars(data, nullptr);
  std::vector<uint8_t> buf = octra::base64_decode(std::string(str));
  env->ReleaseStringUTFChars(data, str);
  jbyteArray result = env->NewByteArray(buf.size());
  env->SetByteArrayRegion(result, 0, buf.size(),
                          reinterpret_cast<jbyte *>(buf.data()));
  return result;
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_sha256(
    JNIEnv *env, jobject thiz, jbyteArray data) {
  jsize len = env->GetArrayLength(data);
  std::vector<uint8_t> buf(len);
  env->GetByteArrayRegion(data, 0, len, reinterpret_cast<jbyte *>(buf.data()));
  auto hash = octra::sha256(buf.data(), buf.size());
  std::string result = octra::hex_encode(hash.data(), 32);
  return env->NewStringUTF(result.c_str());
}

/* ---------- pvac pubkey registration helpers ---------- */

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_getPvacPubkey(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet || !g_pvac_ok) {
    return env->NewStringUTF("");
  }
  std::string pk_b64 = g_pvac.serialize_pubkey_b64();
  return env->NewStringUTF(pk_b64.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_signPvacRegister(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("");
  }
  std::string sig = octra::sign_register_request(g_wallet->addr, g_wallet->sk);
  return env->NewStringUTF(sig.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_getPublicKeyB64(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("");
  }
  return env->NewStringUTF(g_wallet->pub_b64.c_str());
}

JNIEXPORT jlong JNICALL
Java_com_octopus_wallet_OctraNative_decryptEncryptedBalanceCipher(JNIEnv *env,
                                                               jobject thiz,
                                                               jstring cipher) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet || !g_pvac_ok || cipher == nullptr) {
    return 0;
  }
  try {
    const char *c = env->GetStringUTFChars(cipher, nullptr);
    std::string cipher_s(c ? c : "0");
    env->ReleaseStringUTFChars(cipher, c);
    int64_t val = g_pvac.get_balance(cipher_s);
    return static_cast<jlong>(val);
  } catch (...) {
    return 0;
  }
}

/* ---------- stealth send helpers ---------- */

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_stealthPrepare(
    JNIEnv *env, jobject thiz, jstring their_view_pubkey_b64,
    jstring recipient_addr) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }
  try {
    const char *vp = env->GetStringUTFChars(their_view_pubkey_b64, nullptr);
    const char *ra = env->GetStringUTFChars(recipient_addr, nullptr);
    std::string vpub_b64(vp);
    std::string recip(ra);
    env->ReleaseStringUTFChars(their_view_pubkey_b64, vp);
    env->ReleaseStringUTFChars(recipient_addr, ra);

    auto vpub_raw = octra::base64_decode(vpub_b64);
    if (vpub_raw.size() != 32) {
      return env->NewStringUTF("{\"error\":\"invalid view pubkey\"}");
    }

    // ECDH x25519 key exchange
    uint8_t eph_sk[32], eph_pk[32];
    octra::random_bytes(eph_sk, 32);
    crypto_scalarmult_base(eph_pk, eph_sk);
    auto shared = octra::ecdh_shared_secret(eph_sk, vpub_raw.data());

    // stealth tag + claim key
    auto stag = octra::compute_stealth_tag(shared);
    auto claim_sec = octra::compute_claim_secret(shared);
    auto claim_pub = octra::compute_claim_pub(claim_sec, recip);

    // generate random blinding
    uint8_t blinding[32];
    octra::random_bytes(blinding, 32);

    json result;
    result["eph_pub_b64"] = octra::base64_encode(eph_pk, 32);
    result["shared_secret_b64"] = octra::base64_encode(shared.data(), 32);
    result["stealth_tag_hex"] = octra::hex_encode(stag.data(), 16);
    result["claim_pub_hex"] = octra::hex_encode(claim_pub.data(), 32);
    result["blinding_b64"] = octra::base64_encode(blinding, 32);
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_signStealthSendTx(
    JNIEnv *env, jobject thiz, jstring amount, jint nonce,
    jstring current_enc_cipher, jstring eph_pub_b64, jstring stealth_tag_hex,
    jstring claim_pub_hex, jstring enc_amount_b64, jstring blinding_b64,
    jstring amt_commit_b64) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }
  if (!g_pvac_ok) {
    return env->NewStringUTF("{\"error\":\"pvac not available\"}");
  }

  try {
    auto jstr = [&](jstring s) -> std::string {
      if (!s)
        return "";
      const char *c = env->GetStringUTFChars(s, nullptr);
      std::string r(c ? c : "");
      env->ReleaseStringUTFChars(s, c);
      return r;
    };

    std::string amt_s = jstr(amount);
    std::string enc_cipher_s = jstr(current_enc_cipher);
    std::string eph_s = jstr(eph_pub_b64);
    std::string stag_s = jstr(stealth_tag_hex);
    std::string cpub_s = jstr(claim_pub_hex);
    std::string enc_amt_s = jstr(enc_amount_b64);
    std::string blind_s = jstr(blinding_b64);
    std::string acommit_s = jstr(amt_commit_b64);

    uint64_t amount_u64 = std::stoull(amt_s);
    if (amount_u64 == 0) {
      return env->NewStringUTF("{\"error\":\"invalid amount\"}");
    }

    // Check encrypted balance sufficiency
    int64_t enc_bal = g_pvac.get_balance(enc_cipher_s);
    if (enc_bal < (int64_t)amount_u64) {
      char msg[128];
      snprintf(msg, sizeof(msg),
               "insufficient encrypted balance: have %ld, need %lu",
               (long)enc_bal, (unsigned long)amount_u64);
      json err;
      err["error"] = std::string(msg);
      return env->NewStringUTF(err.dump().c_str());
    }

    // FHE encrypt delta
    uint8_t seed[32];
    octra::random_bytes(seed, 32);
    pvac_cipher ct_delta = g_pvac.encrypt(amount_u64, seed);
    if (!ct_delta) {
      return env->NewStringUTF("{\"error\":\"failed to FHE encrypt delta\"}");
    }
    std::string delta_cipher_str = g_pvac.encode_cipher(ct_delta);
    auto commitment = g_pvac.commit_ct(ct_delta);
    std::string commitment_b64 = octra::base64_encode(commitment.data(), 32);

    // Range proofs (parallel)
    pvac_cipher current_ct = g_pvac.decode_cipher(enc_cipher_s);
    if (!current_ct) {
      g_pvac.free_cipher(ct_delta);
      return env->NewStringUTF(
          "{\"error\":\"failed to decode current cipher\"}");
    }
    pvac_cipher new_ct = g_pvac.ct_sub(current_ct, ct_delta);
    uint64_t new_val = (uint64_t)(enc_bal - (int64_t)amount_u64);

    pvac_range_proof rp_delta = nullptr;
    pvac_range_proof rp_bal = nullptr;

    std::thread t_rp_delta([&]() {
      rp_delta =
          pvac_make_range_proof(g_pvac.pk(), g_pvac.sk(), ct_delta, amount_u64);
    });
    std::thread t_rp_bal([&]() {
      rp_bal = pvac_make_range_proof(g_pvac.pk(), g_pvac.sk(), new_ct, new_val);
    });
    t_rp_delta.join();
    t_rp_bal.join();

    if (!rp_delta || !rp_bal) {
      g_pvac.free_cipher(ct_delta);
      g_pvac.free_cipher(current_ct);
      g_pvac.free_cipher(new_ct);
      if (rp_delta)
        g_pvac.free_range_proof(rp_delta);
      if (rp_bal)
        g_pvac.free_range_proof(rp_bal);
      return env->NewStringUTF("{\"error\":\"failed to build range proofs\"}");
    }

    std::string rp_delta_str = g_pvac.encode_range_proof(rp_delta);
    std::string rp_bal_str = g_pvac.encode_range_proof(rp_bal);
    g_pvac.free_range_proof(rp_delta);
    g_pvac.free_range_proof(rp_bal);
    g_pvac.free_cipher(ct_delta);
    g_pvac.free_cipher(current_ct);
    g_pvac.free_cipher(new_ct);

    // Build stealth_data
    // Compute Pedersen commitment if not provided
    if (acommit_s.empty() && !blind_s.empty()) {
      auto blind_raw = octra::base64_decode(blind_s);
      if (blind_raw.size() == 32) {
        auto pc = g_pvac.pedersen_commit(amount_u64, blind_raw.data());
        acommit_s = octra::base64_encode(pc.data(), 32);
      }
    }

    json stealth_data;
    stealth_data["version"] = 5;
    stealth_data["delta_cipher"] = delta_cipher_str;
    stealth_data["commitment"] = commitment_b64;
    stealth_data["range_proof_delta"] = rp_delta_str;
    stealth_data["range_proof_balance"] = rp_bal_str;
    stealth_data["eph_pub"] = eph_s;
    stealth_data["stealth_tag"] = stag_s;
    stealth_data["enc_amount"] = enc_amt_s;
    stealth_data["claim_pub"] = cpub_s;
    stealth_data["amount_commitment"] = acommit_s;

    // Build and sign transaction
    octra::Transaction tx;
    tx.from = g_wallet->addr;
    tx.to_ = "stealth";
    tx.amount = "0";
    tx.nonce = nonce;
    tx.ou = "5000";
    tx.timestamp = static_cast<double>(std::time(nullptr)) + 0.0;
    tx.op_type = "stealth";
    tx.encrypted_data = stealth_data.dump();

    octra::sign_transaction(tx, g_wallet->sk);
    tx.public_key = g_wallet->pub_b64;

    json result = octra::build_tx_json(tx);
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_importWalletMnemonic(
    JNIEnv *env, jobject thiz, jstring mnemonic_str, jstring pin_str) {
  std::lock_guard<std::mutex> lock(g_mtx);
  try {
    const char *mnemonic = env->GetStringUTFChars(mnemonic_str, nullptr);
    const char *pin = env->GetStringUTFChars(pin_str, nullptr);
    std::string mnemonic_s(mnemonic);
    std::string pin_s(pin);
    env->ReleaseStringUTFChars(mnemonic_str, mnemonic);
    env->ReleaseStringUTFChars(pin_str, pin);

    if (!is_valid_pin(pin_s)) {
      return env->NewStringUTF("{\"error\":\"PIN must be 6 digits\"}");
    }

    std::string wallet_path = g_data_dir + "/wallet.oct";
    g_wallet = std::make_unique<octra::Wallet>(
        octra::import_wallet_mnemonic(wallet_path, mnemonic_s, pin_s, 2));
    g_pin = pin_s;
    init_pvac_for_loaded_wallet();

    json result;
    result["address"] = g_wallet->addr;
    result["public_key"] = g_wallet->pub_b64;
    result["master_seed"] = g_wallet->master_seed_b64;
    result["hd_index"] = g_wallet->hd_index;
    result["hd_version"] = g_wallet->hd_version;
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_importWalletMnemonicWithVersion(
    JNIEnv *env, jobject thiz, jstring mnemonic_str, jstring pin_str, jint hd_version) {
  std::lock_guard<std::mutex> lock(g_mtx);
  try {
    const char *mnemonic = env->GetStringUTFChars(mnemonic_str, nullptr);
    const char *pin = env->GetStringUTFChars(pin_str, nullptr);
    std::string mnemonic_s(mnemonic);
    std::string pin_s(pin);
    env->ReleaseStringUTFChars(mnemonic_str, mnemonic);
    env->ReleaseStringUTFChars(pin_str, pin);

    if (!is_valid_pin(pin_s)) {
      return env->NewStringUTF("{\"error\":\"PIN must be 6 digits\"}");
    }

    std::string wallet_path = g_data_dir + "/wallet.oct";
    g_wallet = std::make_unique<octra::Wallet>(
        octra::import_wallet_mnemonic(wallet_path, mnemonic_s, pin_s, (int)hd_version));
    g_pin = pin_s;
    init_pvac_for_loaded_wallet();

    json result;
    result["address"] = g_wallet->addr;
    result["public_key"] = g_wallet->pub_b64;
    result["master_seed"] = g_wallet->master_seed_b64;
    result["hd_index"] = g_wallet->hd_index;
    result["hd_version"] = g_wallet->hd_version;
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_deriveAddressFromMnemonic(
    JNIEnv *env, jobject thiz, jstring mnemonic_str, jint hd_version) {
  try {
    const char *mnemonic = env->GetStringUTFChars(mnemonic_str, nullptr);
    std::string mnemonic_s(mnemonic);
    env->ReleaseStringUTFChars(mnemonic_str, mnemonic);

    std::string addr = octra::addr_from_mnemonic(mnemonic_s, (int)hd_version);
    return env->NewStringUTF(addr.c_str());
  } catch (const std::exception &e) {
    return env->NewStringUTF("");
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_deriveHdAccount(
    JNIEnv *env, jobject thiz, jstring master_seed_str, jint index,
    jstring rpc_url, jstring explorer_url, jstring pin_str) {
  std::lock_guard<std::mutex> lock(g_mtx);
  try {
    const char *master_seed = env->GetStringUTFChars(master_seed_str, nullptr);
    const char *rpc = env->GetStringUTFChars(rpc_url, nullptr);
    const char *explorer = env->GetStringUTFChars(explorer_url, nullptr);
    const char *pin = env->GetStringUTFChars(pin_str, nullptr);
    std::string master_seed_s(master_seed);
    std::string rpc_s(rpc);
    std::string explorer_s(explorer);
    std::string pin_s(pin);
    env->ReleaseStringUTFChars(master_seed_str, master_seed);
    env->ReleaseStringUTFChars(rpc_url, rpc);
    env->ReleaseStringUTFChars(explorer_url, explorer);
    env->ReleaseStringUTFChars(pin_str, pin);

    if (!is_valid_pin(pin_s)) {
      return env->NewStringUTF("{\"error\":\"PIN must be 6 digits\"}");
    }

    std::string wallet_path =
        g_data_dir + "/wallet_" + std::to_string(index) + ".oct";
    g_wallet = std::make_unique<octra::Wallet>(
        octra::derive_hd_account(wallet_path, master_seed_s, (uint32_t)index,
                                 rpc_s, explorer_s, pin_s, 2));
    g_pin = pin_s;
    init_pvac_for_loaded_wallet();

    json result;
    result["address"] = g_wallet->addr;
    result["public_key"] = g_wallet->pub_b64;
    result["master_seed"] = g_wallet->master_seed_b64;
    result["hd_index"] = g_wallet->hd_index;
    result["hd_version"] = g_wallet->hd_version;
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_getWalletHdInfo(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }

  json result;
  result["address"] = g_wallet->addr;
  result["public_key"] = g_wallet->pub_b64;
  result["master_seed"] = g_wallet->master_seed_b64;
  result["hd_index"] = g_wallet->hd_index;
  result["hd_version"] = g_wallet->hd_version;
  result["has_master_seed"] = g_wallet->has_master_seed();
  return env->NewStringUTF(result.dump().c_str());
}

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_computeAesKat(JNIEnv *env, jobject thiz) {
  uint8_t kat[16];
  octra::compute_aes_kat(kat);

  static const char hex[] = "0123456789abcdef";
  char hex_str[33];
  for (int i = 0; i < 16; i++) {
    hex_str[i * 2] = hex[(kat[i] >> 4) & 0xF];
    hex_str[i * 2 + 1] = hex[kat[i] & 0xF];
  }
  hex_str[32] = '\0';

  json result;
  result["aes_kat"] = std::string(hex_str);
  return env->NewStringUTF(result.dump().c_str());
}

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_signKeySwitchTx(JNIEnv *env, jobject thiz) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }
  if (!g_pvac_ok) {
    return env->NewStringUTF("{\"error\":\"pvac not available\"}");
  }

  try {
    // Serialize PVAC pubkey
    size_t pk_len = 0;
    uint8_t *pk_data = pvac_serialize_pubkey(g_pvac.pk(), &pk_len);
    if (!pk_data || pk_len == 0) {
      return env->NewStringUTF("{\"error\":\"failed to serialize pubkey\"}");
    }
    std::string pk_b64 = octra::base64_encode(pk_data, pk_len);

    // Compute AES-KAT
    uint8_t kat[16];
    octra::compute_aes_kat(kat);
    std::string kat_hex = octra::hex_encode(kat, 16);

    // Compute message with pubkey hash
    auto hash = octra::sha256(pk_data, pk_len);
    free(pk_data);
    char hex[17];
    for (int i = 0; i < 8; i++)
      snprintf(hex + i * 2, 3, "%02x", hash[i]);
    std::string msg =
        std::string("encryption key switch | new_key:") + std::string(hex);

    // Build key_switch transaction (matching webcli structure)
    octra::Transaction tx;
    tx.from = g_wallet->addr;
    tx.to_ = g_wallet->addr; // key_switch is self-transfer
    tx.amount = "0";
    tx.nonce = 0; // Will be set by RPC
    tx.ou = "3000";
    tx.timestamp = static_cast<double>(std::time(nullptr)) + 0.0;
    tx.op_type = "key_switch";
    tx.message = msg;
    tx.encrypted_data =
        "{\"new_pubkey\":\"" + pk_b64 + "\",\"aes_kat\":\"" + kat_hex + "\"}";

    // Sign transaction
    octra::sign_transaction(tx, g_wallet->sk);

    json result;
    result["from"] = tx.from;
    result["to"] = tx.to_;
    result["amount"] = tx.amount;
    result["nonce"] = tx.nonce;
    result["ou"] = tx.ou;
    result["op_type"] = tx.op_type;
    result["message"] = tx.message;
    result["encrypted_data"] = tx.encrypted_data;
    result["signature"] = tx.signature;
    result["public_key"] = g_wallet->pub_b64;
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

/* ---------- Cache Functions (Features 2-4) ---------- */

JNIEXPORT jstring JNICALL 
Java_com_octopus_wallet_OctraNative_getCachedFee(JNIEnv *env, jobject thiz) {
    std::lock_guard<std::mutex> lock(g_fee_mtx);
    if (g_fee_cache.is_null() || (now_ts() - g_fee_cache_ts > 60.0)) {
        return env->NewStringUTF("");
    }
    return env->NewStringUTF(g_fee_cache.dump().c_str());
}

JNIEXPORT void JNICALL 
Java_com_octopus_wallet_OctraNative_cacheFee(JNIEnv *env, jobject thiz, jstring fee_json) {
    const char *str = env->GetStringUTFChars(fee_json, nullptr);
    std::lock_guard<std::mutex> lock(g_fee_mtx);
    try {
        g_fee_cache = json::parse(str);
        g_fee_cache_ts = now_ts();
    } catch (...) {}
    env->ReleaseStringUTFChars(fee_json, str);
}

JNIEXPORT jstring JNICALL
Java_com_octopus_wallet_OctraNative_getTxCache(JNIEnv *env, jobject thiz, jstring key) {
    const char *k = env->GetStringUTFChars(key, nullptr);
    std::string result = g_txcache.get(std::string(k));
    env->ReleaseStringUTFChars(key, k);
    return env->NewStringUTF(result.c_str());
}

JNIEXPORT void JNICALL
Java_com_octopus_wallet_OctraNative_putTxCache(JNIEnv *env, jobject thiz, jstring key, jstring value) {
    const char *k = env->GetStringUTFChars(key, nullptr);
    const char *v = env->GetStringUTFChars(value, nullptr);
    g_txcache.put(std::string(k), std::string(v));
    env->ReleaseStringUTFChars(key, k);
    env->ReleaseStringUTFChars(value, v);
}

JNIEXPORT jboolean JNICALL 
Java_com_octopus_wallet_OctraNative_isPolling(JNIEnv *env, jobject thiz) {
    return g_polling ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL 
Java_com_octopus_wallet_OctraNative_startPolling(JNIEnv *env, jobject thiz) {
    if (g_polling || !g_wallet) return;
    g_polling = true;
    g_poll_thread = std::make_unique<std::thread>([=]() {
        // Polling logic here - query RPC periodically
        while (g_polling) {
            // Check for new transactions, update cache, etc.
            std::this_thread::sleep_for(std::chrono::seconds(30));
        }
    });
    g_poll_thread->detach();
}

JNIEXPORT void JNICALL 
Java_com_octopus_wallet_OctraNative_stopPolling(JNIEnv *env, jobject thiz) {
    g_polling = false;
    if (g_poll_thread && g_poll_thread->joinable()) {
        g_poll_thread->join();
    }
}

/* ---------- Stealth Scanning (Feature 5) ---------- */

JNIEXPORT jboolean JNICALL 
Java_com_octopus_wallet_OctraNative_isStealthScanning(JNIEnv *env, jobject thiz) {
    return g_scanning ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL 
Java_com_octopus_wallet_OctraNative_startStealthScan(JNIEnv *env, jobject thiz) {
    std::lock_guard<std::mutex> lock(g_scanner_mtx);
    if (g_scanning || !g_wallet) return;
    g_scanning = true;
    g_scanner = std::make_unique<octra::StealthScanner>(g_wallet->priv_b64);
    std::thread([=]() {
        if (g_scanner) {
            g_scanner->scan();
        }
        std::lock_guard<std::mutex> lk(g_scanner_mtx);
        g_scanning = false;
    }).detach();
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_fheEncrypt(
    JNIEnv *env, jobject thiz, jlong value) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_pvac_ok) {
    return env->NewStringUTF("{\"error\":\"pvac not available\"}");
  }
  try {
    uint8_t seed[32];
    octra::random_bytes(seed, 32);
    pvac_cipher ct = g_pvac.encrypt(static_cast<uint64_t>(value), seed);
    auto data = g_pvac.serialize_cipher(ct);
    std::string b64 = octra::base64_encode(data.data(), data.size());
    
    uint8_t blinding[32];
    octra::random_bytes(blinding, 32);
    auto amount_commitment = g_pvac.pedersen_commit(static_cast<uint64_t>(value), blinding);
    std::string amount_commitment_b64 = octra::base64_encode(amount_commitment.data(), 32);
    
    pvac_zero_proof proof = g_pvac.make_zero_proof_bound(ct, static_cast<uint64_t>(value), blinding);
    std::string zero_proof = g_pvac.encode_zero_proof(proof);
    
    g_pvac.free_zero_proof(proof);
    g_pvac.free_cipher(ct);
    
    json result;
    result["ciphertext"] = b64;
    result["amount_commitment"] = amount_commitment_b64;
    result["zero_proof"] = zero_proof;
    result["proof_kind"] = "bound_zero_v1";
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_fheDecrypt(
    JNIEnv *env, jobject thiz, jstring ciphertext) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_pvac_ok) {
    return env->NewStringUTF("{\"error\":\"pvac not available\"}");
  }
  const char *cipher_str = env->GetStringUTFChars(ciphertext, nullptr);
  if (!cipher_str) {
    return env->NewStringUTF("{\"error\":\"invalid ciphertext parameter\"}");
  }
  std::string b64(cipher_str);
  env->ReleaseStringUTFChars(ciphertext, cipher_str);
  
  try {
    auto raw = octra::base64_decode(b64);
    if (raw.empty()) {
      return env->NewStringUTF("{\"error\":\"invalid base64\"}");
    }
    pvac_cipher ct = g_pvac.deserialize_cipher(raw.data(), raw.size());
    if (!ct) {
      return env->NewStringUTF("{\"error\":\"invalid ciphertext\"}");
    }
    uint64_t lo = 0, hi = 0;
    g_pvac.decrypt_fp(ct, lo, hi);
    g_pvac.free_cipher(ct);
    
    int64_t val;
    if (hi == 0) {
      val = static_cast<int64_t>(lo);
    } else {
      __uint128_t p = (__uint128_t(1) << 127) - 1;
      __uint128_t full = (__uint128_t(hi) << 64) | lo;
      if (full > p / 2) val = -static_cast<int64_t>(p - full);
      else val = static_cast<int64_t>(lo);
    }
    
    json result;
    result["value"] = val;
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

JNIEXPORT jstring JNICALL Java_com_octopus_wallet_OctraNative_signGeneralTransaction(
    JNIEnv *env, jobject thiz, jstring to_addr, jstring amount, jint nonce,
    jstring ou, jstring op_type, jstring message, jstring encrypted_data) {
  std::lock_guard<std::mutex> lock(g_mtx);
  if (!g_wallet) {
    return env->NewStringUTF("{\"error\":\"wallet not loaded\"}");
  }
  if (!to_addr || !amount || !ou || !op_type) {
    return env->NewStringUTF("{\"error\":\"missing required parameters: to_addr, amount, ou, and op_type must not be null\"}");
  }

  try {
    const char *to = env->GetStringUTFChars(to_addr, nullptr);
    const char *amt = env->GetStringUTFChars(amount, nullptr);
    const char *ou_val = env->GetStringUTFChars(ou, nullptr);
    const char *op = env->GetStringUTFChars(op_type, nullptr);
    const char *msg = message ? env->GetStringUTFChars(message, nullptr) : nullptr;
    const char *enc = encrypted_data ? env->GetStringUTFChars(encrypted_data, nullptr) : nullptr;

    octra::Transaction tx;
    tx.from = g_wallet->addr;
    tx.to_ = std::string(to);
    tx.amount = std::string(amt);
    tx.nonce = nonce;
    tx.ou = std::string(ou_val);
    tx.timestamp = static_cast<double>(std::time(nullptr)) + 0.0;
    tx.op_type = std::string(op);
    if (msg)
      tx.message = std::string(msg);
    if (enc)
      tx.encrypted_data = std::string(enc);

    octra::sign_transaction(tx, g_wallet->sk);
    tx.public_key = g_wallet->pub_b64;

    env->ReleaseStringUTFChars(to_addr, to);
    env->ReleaseStringUTFChars(amount, amt);
    env->ReleaseStringUTFChars(ou, ou_val);
    env->ReleaseStringUTFChars(op_type, op);
    if (msg)
      env->ReleaseStringUTFChars(message, msg);
    if (enc)
      env->ReleaseStringUTFChars(encrypted_data, enc);

    json result = octra::build_tx_json(tx);
    return env->NewStringUTF(result.dump().c_str());
  } catch (const std::exception &e) {
    json err;
    err["error"] = e.what();
    return env->NewStringUTF(err.dump().c_str());
  }
}

}
