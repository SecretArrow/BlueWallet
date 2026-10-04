#pragma once
#include "crypto_utils.hpp"
#include "json.hpp"
#include <cstdint>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <string>

extern "C" {
#include "tweetnacl.h"
}

namespace octra {

struct Wallet {
  std::string priv_b64;
  std::string addr;
  std::string rpc_url;
  std::string explorer_url = "https://devnet.octrascan.io";
  uint8_t sk[64];
  uint8_t pk[32];
  std::string pub_b64;
  std::string master_seed_b64;
  std::string mnemonic;
  int hd_index = 0;
  int hd_version = 1;

  bool has_master_seed() const { return !master_seed_b64.empty(); }

  ~Wallet() {
    secure_zero(sk, 64);
    secure_zero(pk, 32);
  }
};

inline std::string derive_address(const uint8_t pubkey[32]) {
  auto h = sha256(pubkey, 32);
  return "oct" + base58_encode(h.data(), 32);
}

bool has_encrypted_wallet(const std::string &data_dir);
bool has_legacy_wallet(const std::string &data_dir);

void save_wallet_encrypted(const std::string &path, const Wallet &w,
                           const std::string &pin);

Wallet load_wallet_encrypted(const std::string &path, const std::string &pin);

Wallet create_wallet(const std::string &path, const std::string &pin);

Wallet import_wallet(const std::string &path, const std::string &priv_b64_raw,
                     const std::string &pin);

void save_settings(const std::string &path, Wallet &w,
                   const std::string &new_rpc, const std::string &pin);

void change_pin(const std::string &path, Wallet &w, const std::string &new_pin);

// HD wallet functions
Wallet derive_hd_account(const std::string &path,
                         const std::string &master_seed_b64, uint32_t index,
                         const std::string &rpc_url,
                         const std::string &explorer_url,
                         const std::string &pin, int hd_version = 2);

Wallet import_wallet_mnemonic(const std::string &path,
                              const std::string &mnemonic,
                              const std::string &pin, int hd_version = 1);

std::string addr_from_mnemonic(const std::string &mnemonic, int hd_version);

} // namespace octra
