#include "wallet.hpp"
#include "crypto_utils.hpp"
#include <iterator>
#include <sys/stat.h>

namespace octra {

bool has_encrypted_wallet(const std::string &data_dir) {
  std::string path = data_dir + "/wallet.oct";
  std::ifstream f(path, std::ios::binary);
  return f.good();
}

bool has_legacy_wallet(const std::string &data_dir) {
  std::string path = data_dir + "/wallet.json";
  std::ifstream f(path);
  return f.good();
}

void save_wallet_encrypted(const std::string &path, const Wallet &w,
                           const std::string &pin) {
  nlohmann::json j;
  j["priv"] = w.priv_b64;
  j["addr"] = w.addr;
  j["rpc"] = w.rpc_url;
  j["explorer"] = w.explorer_url;
  std::string plaintext = j.dump();
  auto enc = wallet_encrypt(reinterpret_cast<const uint8_t *>(plaintext.data()),
                            plaintext.size(), pin);
  secure_zero(&plaintext[0], plaintext.size());
  {
    std::ofstream f(path, std::ios::binary);
    if (!f)
      throw std::runtime_error("cannot write wallet file");
    f.write(reinterpret_cast<const char *>(enc.data()), enc.size());
  }
}

Wallet load_wallet_encrypted(const std::string &path, const std::string &pin) {
  std::ifstream f(path, std::ios::binary);
  if (!f)
    throw std::runtime_error("cannot open wallet file");
  std::vector<uint8_t> data((std::istreambuf_iterator<char>(f)),
                            std::istreambuf_iterator<char>());
  f.close();

  auto plain = wallet_decrypt(data.data(), data.size(), pin);
  if (plain.empty())
    throw std::runtime_error("wrong pin");

  std::string json_str(plain.begin(), plain.end());
  secure_zero(plain.data(), plain.size());

  nlohmann::json j = nlohmann::json::parse(json_str);
  secure_zero(&json_str[0], json_str.size());

  Wallet w;
  w.priv_b64 = j.at("priv").get<std::string>();
  w.addr = j.at("addr").get<std::string>();
  w.rpc_url = j.value("rpc", "http://165.227.225.79:8080");
  w.explorer_url = j.value("explorer", "https://devnet.octrascan.io");

  auto raw = base64_decode(w.priv_b64);
  if (raw.size() >= 64) {
    memcpy(w.sk, raw.data(), 64);
    memcpy(w.pk, w.sk + 32, 32);
  } else if (raw.size() >= 32) {
    keypair_from_seed(raw.data(), w.sk, w.pk);
  } else {
    throw std::runtime_error("invalid private key");
  }
  w.pub_b64 = base64_encode(w.pk, 32);
  return w;
}

Wallet create_wallet(const std::string &path, const std::string &pin) {
  Wallet w;
  for (int i = 0; i < 100; i++) {
    crypto_sign_keypair(w.pk, w.sk);
    std::string a = derive_address(w.pk);
    if (a.size() == 47) {
      w.addr = a;
      w.priv_b64 = base64_encode(w.sk, 32);
      w.pub_b64 = base64_encode(w.pk, 32);
      w.rpc_url = "http://165.227.225.79:8080";
      save_wallet_encrypted(path, w, pin);
      return w;
    }
  }
  throw std::runtime_error("failed to generate valid address");
}

Wallet import_wallet(const std::string &path, const std::string &priv_b64_raw,
                     const std::string &pin) {
  std::string clean;
  for (char c : priv_b64_raw) {
    if (c != '\n' && c != '\r' && c != ' ' && c != '\t')
      clean += c;
  }
  auto raw = base64_decode(clean);
  Wallet w;
  if (raw.size() >= 64) {
    memcpy(w.sk, raw.data(), 64);
    memcpy(w.pk, w.sk + 32, 32);
  } else if (raw.size() >= 32) {
    keypair_from_seed(raw.data(), w.sk, w.pk);
  } else {
    throw std::runtime_error("invalid private key length");
  }
  w.addr = derive_address(w.pk);
  if (w.addr.size() != 47 || w.addr.substr(0, 3) != "oct")
    throw std::runtime_error("derived address is invalid");
  w.priv_b64 = base64_encode(w.sk, 32);
  w.pub_b64 = base64_encode(w.pk, 32);
  w.rpc_url = "http://165.227.225.79:8080";
  save_wallet_encrypted(path, w, pin);
  return w;
}

void save_settings(const std::string &path, Wallet &w,
                   const std::string &new_rpc, const std::string &pin) {
  w.rpc_url = new_rpc;
  save_wallet_encrypted(path, w, pin);
}

void change_pin(const std::string &path, Wallet &w,
                const std::string &new_pin) {
  save_wallet_encrypted(path, w, new_pin);
}

Wallet derive_hd_account(const std::string &path,
                         const std::string &master_seed_b64, uint32_t index,
                         const std::string &rpc_url,
                         const std::string &explorer_url,
                         const std::string &pin, int hd_version) {
  auto master_raw = base64_decode(master_seed_b64);
  if (master_raw.size() != 64)
    throw std::runtime_error("invalid master seed");

  auto hd_seed = derive_hd_seed(master_raw.data(), index, hd_version);

  Wallet w;
  keypair_from_seed(hd_seed.data(), w.sk, w.pk);
  secure_zero(hd_seed.data(), 32);

  w.addr = derive_address(w.pk);
  if (w.addr.size() != 47 || w.addr.substr(0, 3) != "oct")
    throw std::runtime_error("derived address is invalid");

  w.priv_b64 = base64_encode(w.sk, 32);
  w.pub_b64 = base64_encode(w.pk, 32);
  w.rpc_url = rpc_url;
  w.explorer_url = explorer_url;
  w.master_seed_b64 = master_seed_b64;
  w.hd_index = (int)index;
  w.hd_version = hd_version;

  save_wallet_encrypted(path, w, pin);

  secure_zero(master_raw.data(), master_raw.size());
  return w;
}

Wallet import_wallet_mnemonic(const std::string &path,
                              const std::string &mnemonic,
                              const std::string &pin, int hd_version) {
  if (!validate_mnemonic(mnemonic))
    throw std::runtime_error("invalid seed phrase");

  auto seed = mnemonic_to_seed(mnemonic);
  auto hd_seed = derive_hd_seed(seed.data(), 0, hd_version);

  Wallet w;
  keypair_from_seed(hd_seed.data(), w.sk, w.pk);
  secure_zero(hd_seed.data(), 32);

  w.addr = derive_address(w.pk);
  if (w.addr.size() != 47 || w.addr.substr(0, 3) != "oct")
    throw std::runtime_error("derived address is invalid");

  w.priv_b64 = base64_encode(w.sk, 32);
  w.pub_b64 = base64_encode(w.pk, 32);
  w.rpc_url = "http://165.227.225.79:8080";
  w.master_seed_b64 = base64_encode(seed.data(), 64);
  w.mnemonic = mnemonic;
  w.hd_index = 0;
  w.hd_version = hd_version;

  save_wallet_encrypted(path, w, pin);
  secure_zero(seed.data(), 64);
  return w;
}

std::string addr_from_mnemonic(const std::string &mnemonic, int hd_version) {
  auto seed = mnemonic_to_seed(mnemonic);
  auto hd_seed = derive_hd_seed(seed.data(), 0, hd_version);
  uint8_t sk[64], pk[32];
  keypair_from_seed(hd_seed.data(), sk, pk);
  secure_zero(hd_seed.data(), 32);
  secure_zero(seed.data(), 64);
  auto addr = derive_address(pk);
  secure_zero(sk, 64);
  return addr;
}

} // namespace octra
