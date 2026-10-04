#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#ifdef ANDROID_BUILD
#include <android/log.h>
#define LOG_TAG "OctraWallet"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGD(...)
#define LOGE(...)
#endif

extern "C" {
#include "tweetnacl.h"
extern void randombytes(unsigned char *, unsigned long long);
}

namespace octra {

namespace detail {

static inline uint32_t rotr(uint32_t x, int n) {
  return (x >> n) | (x << (32 - n));
}

static inline uint32_t ch(uint32_t x, uint32_t y, uint32_t z) {
  return (x & y) ^ (~x & z);
}

static inline uint32_t maj(uint32_t x, uint32_t y, uint32_t z) {
  return (x & y) ^ (x & z) ^ (y & z);
}

static inline uint32_t sig0(uint32_t x) {
  return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
}

static inline uint32_t sig1(uint32_t x) {
  return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
}

static inline uint32_t gam0(uint32_t x) {
  return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
}

static inline uint32_t gam1(uint32_t x) {
  return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
}

static const uint32_t K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

} // namespace detail

std::array<uint8_t, 32> sha256(const uint8_t *data, size_t len);
std::array<uint8_t, 32> sha256(const std::string &s);

std::string base64_encode(const uint8_t *data, size_t len);
std::vector<uint8_t> base64_decode(const std::string &s);

std::string base58_encode(const uint8_t *data, size_t len);

std::string hex_encode(const uint8_t *data, size_t len);
std::vector<uint8_t> hex_decode(const std::string &s);

void random_bytes(uint8_t *out, size_t len);

void ed25519_sk_to_curve25519(const uint8_t ed_sk[64], uint8_t x_sk[32]);
void ed25519_pk_to_curve25519(const uint8_t ed_sk[64], uint8_t x_pk[32]);

void secure_zero(void *ptr, size_t len);

void keypair_from_seed(const uint8_t seed[32], uint8_t sk[64], uint8_t pk[32]);

std::array<uint8_t, 32> derive_key_from_pin(const std::string &pin,
                                            const uint8_t salt[32],
                                            int iterations = 100000);

std::vector<uint8_t> wallet_encrypt(const uint8_t *plaintext, size_t len,
                                    const std::string &pin);

std::vector<uint8_t> wallet_decrypt(const uint8_t *data, size_t total_len,
                                    const std::string &pin);

// HD wallet derivation
std::array<uint8_t, 32> derive_hd_seed(const uint8_t master_seed[64],
                                       uint32_t index, int hd_version = 2);

// BIP39 mnemonic
std::array<uint8_t, 64> mnemonic_to_seed(const std::string &mnemonic,
                                         const std::string &passphrase = "");
std::string generate_mnemonic_12();
bool validate_mnemonic(const std::string &mnemonic);

// AES-KAT for PVAC
void compute_aes_kat(uint8_t out[16]);

} // namespace octra
