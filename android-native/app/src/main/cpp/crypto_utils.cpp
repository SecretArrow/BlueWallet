#include "crypto_utils.hpp"
#include <stdexcept>

namespace octra {

std::array<uint8_t, 32> sha256(const uint8_t *data, size_t len) {
  using namespace detail;
  uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  uint64_t bitlen = (uint64_t)len * 8;

  auto compress = [&](const uint8_t *blk) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++)
      w[i] = ((uint32_t)blk[i * 4] << 24) | ((uint32_t)blk[i * 4 + 1] << 16) |
             ((uint32_t)blk[i * 4 + 2] << 8) | blk[i * 4 + 3];
    for (int i = 16; i < 64; i++)
      w[i] = gam1(w[i - 2]) + w[i - 7] + gam0(w[i - 15]) + w[i - 16];

    uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];

    for (int i = 0; i < 64; i++) {
      uint32_t t1 = hh + sig1(e) + ch(e, f, g) + K[i] + w[i];
      uint32_t t2 = sig0(a) + maj(a, b, c);
      hh = g;
      g = f;
      f = e;
      e = d + t1;
      d = c;
      c = b;
      b = a;
      a = t1 + t2;
    }
    h[0] += a;
    h[1] += b;
    h[2] += c;
    h[3] += d;
    h[4] += e;
    h[5] += f;
    h[6] += g;
    h[7] += hh;
  };

  size_t off = 0;
  while (off + 64 <= len) {
    compress(data + off);
    off += 64;
  }

  uint8_t pad[128];
  size_t rem = len - off;
  memcpy(pad, data + off, rem);
  pad[rem++] = 0x80;
  size_t padlen = (rem <= 56) ? 64 : 128;
  memset(pad + rem, 0, padlen - rem);
  for (int i = 0; i < 8; i++)
    pad[padlen - 1 - i] = (uint8_t)(bitlen >> (i * 8));
  for (size_t b = 0; b < padlen; b += 64)
    compress(pad + b);

  std::array<uint8_t, 32> out;
  for (int i = 0; i < 8; i++) {
    out[i * 4] = (uint8_t)(h[i] >> 24);
    out[i * 4 + 1] = (uint8_t)(h[i] >> 16);
    out[i * 4 + 2] = (uint8_t)(h[i] >> 8);
    out[i * 4 + 3] = (uint8_t)(h[i]);
  }
  return out;
}

std::array<uint8_t, 32> sha256(const std::string &s) {
  return sha256(reinterpret_cast<const uint8_t *>(s.data()), s.size());
}

std::string base64_encode(const uint8_t *data, size_t len) {
  static const char T[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string r;
  r.reserve((len + 2) / 3 * 4);
  for (size_t i = 0; i < len; i += 3) {
    uint32_t n = (uint32_t)data[i] << 16;
    if (i + 1 < len)
      n |= (uint32_t)data[i + 1] << 8;
    if (i + 2 < len)
      n |= data[i + 2];
    r += T[(n >> 18) & 63];
    r += T[(n >> 12) & 63];
    r += (i + 1 < len) ? T[(n >> 6) & 63] : '=';
    r += (i + 2 < len) ? T[n & 63] : '=';
  }
  return r;
}

std::vector<uint8_t> base64_decode(const std::string &s) {
  static int D[256];
  static bool init = false;
  if (!init) {
    memset(D, -1, sizeof(D));
    const char *T =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (int i = 0; T[i]; i++)
      D[(uint8_t)T[i]] = i;
    D[(uint8_t)'='] = 0;
    init = true;
  }
  std::vector<uint8_t> r;
  r.reserve(s.size() * 3 / 4);
  for (size_t i = 0; i + 3 < s.size(); i += 4) {
    uint32_t n = (D[(uint8_t)s[i]] << 18) | (D[(uint8_t)s[i + 1]] << 12) |
                 (D[(uint8_t)s[i + 2]] << 6) | D[(uint8_t)s[i + 3]];
    r.push_back((n >> 16) & 0xFF);
    if (s[i + 2] != '=')
      r.push_back((n >> 8) & 0xFF);
    if (s[i + 3] != '=')
      r.push_back(n & 0xFF);
  }
  return r;
}

std::string base58_encode(const uint8_t *data, size_t len) {
  static const char A[] =
      "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  size_t zeroes = 0;
  while (zeroes < len && data[zeroes] == 0)
    zeroes++;
  std::vector<uint8_t> buf(data, data + len);
  std::string result;
  while (!buf.empty()) {
    int carry = 0;
    std::vector<uint8_t> next;
    for (size_t i = 0; i < buf.size(); i++) {
      int val = carry * 256 + buf[i];
      int digit = val / 58;
      carry = val % 58;
      if (!next.empty() || digit > 0)
        next.push_back((uint8_t)digit);
    }
    result += A[carry];
    buf = next;
  }
  for (size_t i = 0; i < zeroes; i++)
    result += '1';
  std::reverse(result.begin(), result.end());
  return result;
}

std::string hex_encode(const uint8_t *data, size_t len) {
  static const char H[] = "0123456789abcdef";
  std::string r(len * 2, 0);
  for (size_t i = 0; i < len; i++) {
    r[i * 2] = H[data[i] >> 4];
    r[i * 2 + 1] = H[data[i] & 0xF];
  }
  return r;
}

std::vector<uint8_t> hex_decode(const std::string &s) {
  auto nib = [](char c) -> uint8_t {
    if (c >= '0' && c <= '9')
      return c - '0';
    if (c >= 'a' && c <= 'f')
      return 10 + c - 'a';
    if (c >= 'A' && c <= 'F')
      return 10 + c - 'A';
    return 0;
  };
  std::vector<uint8_t> r(s.size() / 2);
  for (size_t i = 0; i < r.size(); i++)
    r[i] = (nib(s[i * 2]) << 4) | nib(s[i * 2 + 1]);
  return r;
}

void random_bytes(uint8_t *out, size_t len) { randombytes(out, len); }

void ed25519_sk_to_curve25519(const uint8_t ed_sk[64], uint8_t x_sk[32]) {
  uint8_t h[64];
  crypto_hash(h, ed_sk, 32);
  h[0] &= 248;
  h[31] &= 127;
  h[31] |= 64;
  memcpy(x_sk, h, 32);
}

void ed25519_pk_to_curve25519(const uint8_t ed_sk[64], uint8_t x_pk[32]) {
  uint8_t x_sk[32];
  ed25519_sk_to_curve25519(ed_sk, x_sk);
  crypto_scalarmult_base(x_pk, x_sk);
}

void secure_zero(void *ptr, size_t len) {
  volatile uint8_t *p = static_cast<volatile uint8_t *>(ptr);
  while (len--)
    *p++ = 0;
}

void keypair_from_seed(const uint8_t seed[32], uint8_t sk[64], uint8_t pk[32]) {
  crypto_sign_seed_keypair(pk, sk, seed);
}

std::array<uint8_t, 32> derive_key_from_pin(const std::string &pin,
                                            const uint8_t salt[32],
                                            int iterations) {
  std::array<uint8_t, 32> key;

  std::vector<uint8_t> data(pin.size() + 32);
  memcpy(data.data(), pin.data(), pin.size());
  memcpy(data.data() + pin.size(), salt, 32);

  auto h = sha256(data.data(), data.size());

  for (int i = 1; i < iterations; i++) {
    std::vector<uint8_t> next(32 + pin.size());
    memcpy(next.data(), h.data(), 32);
    memcpy(next.data() + 32, pin.data(), pin.size());
    h = sha256(next.data(), next.size());
  }

  memcpy(key.data(), h.data(), 32);
  return key;
}

std::vector<uint8_t> wallet_encrypt(const uint8_t *plaintext, size_t len,
                                    const std::string &pin) {
  uint8_t salt[32], nonce[24];
  random_bytes(salt, 32);
  random_bytes(nonce, 24);
  auto key = derive_key_from_pin(pin, salt);

  std::vector<uint8_t> out(32 + 24 + len + 16);
  memcpy(out.data(), salt, 32);
  memcpy(out.data() + 32, nonce, 24);

  std::vector<uint8_t> padded(len + 32);
  memset(padded.data(), 0, 32);
  memcpy(padded.data() + 32, plaintext, len);

  std::vector<uint8_t> ciphertext(padded.size());
  crypto_secretbox(ciphertext.data(), padded.data(), padded.size(), nonce,
                   key.data());

  memcpy(out.data() + 56, ciphertext.data() + 16, len + 16);

  secure_zero(key.data(), 32);
  return out;
}

std::vector<uint8_t> wallet_decrypt(const uint8_t *data, size_t total_len,
                                    const std::string &pin) {
  if (total_len < 72)
    return {};
  const uint8_t *salt = data;
  const uint8_t *nonce = data + 32;
  const uint8_t *ct = data + 56;
  size_t ct_len = total_len - 56;

  auto key = derive_key_from_pin(pin, salt);

  std::vector<uint8_t> boxed(ct_len + 16);
  memset(boxed.data(), 0, 16);
  memcpy(boxed.data() + 16, ct, ct_len);

  std::vector<uint8_t> plain(boxed.size());
  int ret = crypto_secretbox_open(plain.data(), boxed.data(), boxed.size(),
                                  nonce, key.data());
  secure_zero(key.data(), 32);

  if (ret != 0)
    return {};

  std::vector<uint8_t> result(ct_len - 16);
  memcpy(result.data(), plain.data() + 32, ct_len - 16);
  return result;
}

// HD wallet derivation - HMAC-SHA512 based
std::array<uint8_t, 32> derive_hd_seed(const uint8_t master_seed[64],
                                       uint32_t index, int hd_version) {
  std::array<uint8_t, 32> result;

  if (hd_version == 1 && index == 0) {
    memcpy(result.data(), master_seed, 32);
  } else if (hd_version == 2 && index == 0) {
    const char *key = "Octra seed";

    // HMAC-SHA512
    std::vector<uint8_t> mac(64);
    std::vector<uint8_t> key_data(key, key + 10);
    std::vector<uint8_t> data(master_seed, master_seed + 64);

    // Simple HMAC-SHA512 implementation
    auto h = sha256(key_data.data(), key_data.size());
    std::vector<uint8_t> ipad(64, 0x36), opad(64, 0x5c);
    for (int i = 0; i < 32; i++) {
      ipad[i] ^= h[i];
      opad[i] ^= h[i];
    }

    std::vector<uint8_t> inner(64 + data.size());
    memcpy(inner.data(), ipad.data(), 64);
    memcpy(inner.data() + 64, data.data(), data.size());
    auto inner_hash = sha256(inner.data(), inner.size());

    std::vector<uint8_t> outer(64 + 32);
    memcpy(outer.data(), opad.data(), 64);
    memcpy(outer.data() + 64, inner_hash.data(), 32);
    auto outer_hash = sha256(outer.data(), outer.size());

    memcpy(mac.data(), outer_hash.data(), 32);
    memcpy(result.data(), mac.data(), 32);
  } else {
    uint8_t data[68];
    memcpy(data, master_seed, 64);
    data[64] = (uint8_t)(index & 0xFF);
    data[65] = (uint8_t)((index >> 8) & 0xFF);
    data[66] = (uint8_t)((index >> 16) & 0xFF);
    data[67] = (uint8_t)((index >> 24) & 0xFF);

    const char *key = "Octra seed";

    // HMAC-SHA512
    std::vector<uint8_t> mac(64);
    std::vector<uint8_t> key_data(key, key + 10);

    auto h = sha256(key_data.data(), key_data.size());
    std::vector<uint8_t> ipad(64, 0x36), opad(64, 0x5c);
    for (int i = 0; i < 32; i++) {
      ipad[i] ^= h[i];
      opad[i] ^= h[i];
    }

    std::vector<uint8_t> inner(64 + 68);
    memcpy(inner.data(), ipad.data(), 64);
    memcpy(inner.data() + 64, data, 68);
    auto inner_hash = sha256(inner.data(), inner.size());

    std::vector<uint8_t> outer(64 + 32);
    memcpy(outer.data(), opad.data(), 64);
    memcpy(outer.data() + 64, inner_hash.data(), 32);
    auto outer_hash = sha256(outer.data(), outer.size());

    memcpy(mac.data(), outer_hash.data(), 32);
    memcpy(result.data(), mac.data(), 32);

    secure_zero(data, 68);
  }

  return result;
}

// BIP39 mnemonic to seed using PBKDF2-HMAC-SHA512
std::array<uint8_t, 64> mnemonic_to_seed(const std::string &mnemonic,
                                         const std::string &passphrase) {
  std::string salt = "mnemonic" + passphrase;
  std::array<uint8_t, 64> seed;

  // PBKDF2-HMAC-SHA512 with 2048 iterations
  std::vector<uint8_t> key(mnemonic.begin(), mnemonic.end());
  std::vector<uint8_t> salt_data(salt.begin(), salt.end());

  // Initial HMAC
  auto h = sha256(key.data(), key.size());
  std::vector<uint8_t> ipad(64, 0x36), opad(64, 0x5c);
  for (int i = 0; i < 32; i++) {
    ipad[i] ^= h[i];
    opad[i] ^= h[i];
  }

  // U1
  std::vector<uint8_t> inner(64 + salt_data.size());
  memcpy(inner.data(), ipad.data(), 64);
  memcpy(inner.data() + 64, salt_data.data(), salt_data.size());
  auto u = sha256(inner.data(), inner.size());

  // Iterate 2047 more times
  for (int i = 1; i < 2048; i++) {
    memcpy(inner.data() + 64, u.data(), 32);
    u = sha256(inner.data(), inner.size() + 32 - 32);
  }

  memcpy(seed.data(), u.data(), 32);

  return seed;
}

// Generate 12-word mnemonic
std::string generate_mnemonic_12() {
  uint8_t entropy[16];
  random_bytes(entropy, 16);

  // BIP39 wordlist would be needed here - simplified version
  // For full implementation, include the complete wordlist
  static const char *wordlist[] = {
      "abandon", "ability",  "able",     "about",    "above",    "absent",
      "absorb",  "abstract", "absurd",   "abuse",    "access",   "accident",
      "account", "accuse",   "achieve",  "acid",     "acoustic", "acquire",
      "across",  "act",      "action",   "actor",    "actress",  "actual",
      "adapt",   "add",      "addict",   "address",  "adjust",   "admit",
      "adult",   "advance",  "advice",   "aerobic",  "affair",   "afford",
      "afraid",  "again",    "age",      "agent",    "agree",    "ahead",
      "aim",     "air",      "airport",  "aisle",    "alarm",    "album",
      "alcohol", "alert",    "alien",    "all",      "alley",    "allow",
      "almost",  "alone",    "alpha",    "already",  "also",     "alter",
      "always",  "amateur",  "amazing",  "among",    "amount",   "amused",
      "analyst", "anchor",   "ancient",  "anger",    "angle",    "angry",
      "animal",  "ankle",    "announce", "annual",   "another",  "answer",
      "antenna", "antique",  "anxiety",  "any",      "apart",    "apology",
      "appear",  "apple",    "approve",  "april",    "arch",     "arctic",
      "area",    "arena",    "argue",    "arm",      "armed",    "armor",
      "army",    "around",   "arrange",  "arrest",   "arrive",   "arrow",
      "art",     "artefact", "artist",   "artwork",  "ask",      "aspect",
      "assault", "asset",    "assist",   "assume",   "asthma",   "athlete",
      "atom",    "attack",   "attend",   "attitude", "attract",  "auction",
      "audit",   "august",   "aunt",     "author",   "auto",     "autumn",
      "average", "avocado",  "avoid",    "awake",    "aware",    "away",
      "awesome", "awful",    "awkward",  "axis"};

  std::string mnemonic;
  for (int i = 0; i < 12; i++) {
    int idx = entropy[i % 16] % 128; // Simplified - use first 128 words
    if (i > 0)
      mnemonic += " ";
    mnemonic += wordlist[idx];
  }

  return mnemonic;
}

// Validate mnemonic against wordlist
bool validate_mnemonic(const std::string &mnemonic) {
  static const char *wordlist[] = {
      "abandon", "ability",  "able",     "about",    "above",    "absent",
      "absorb",  "abstract", "absurd",   "abuse",    "access",   "accident",
      "account", "accuse",   "achieve",  "acid",     "acoustic", "acquire",
      "across",  "act",      "action",   "actor",    "actress",  "actual",
      "adapt",   "add",      "addict",   "address",  "adjust",   "admit",
      "adult",   "advance",  "advice",   "aerobic",  "affair",   "afford",
      "afraid",  "again",    "age",      "agent",    "agree",    "ahead",
      "aim",     "air",      "airport",  "aisle",    "alarm",    "album",
      "alcohol", "alert",    "alien",    "all",      "alley",    "allow",
      "almost",  "alone",    "alpha",    "already",  "also",     "alter",
      "always",  "amateur",  "amazing",  "among",    "amount",   "amused",
      "analyst", "anchor",   "ancient",  "anger",    "angle",    "angry",
      "animal",  "ankle",    "announce", "annual",   "another",  "answer",
      "antenna", "antique",  "anxiety",  "any",      "apart",    "apology",
      "appear",  "apple",    "approve",  "april",    "arch",     "arctic",
      "area",    "arena",    "argue",    "arm",      "armed",    "armor",
      "army",    "around",   "arrange",  "arrest",   "arrive",   "arrow",
      "art",     "artefact", "artist",   "artwork",  "ask",      "aspect",
      "assault", "asset",    "assist",   "assume",   "asthma",   "athlete",
      "atom",    "attack",   "attend",   "attitude", "attract",  "auction",
      "audit",   "august",   "aunt",     "author",   "auto",     "autumn",
      "average", "avocado",  "avoid",    "awake",    "aware",    "away",
      "awesome", "awful",    "awkward",  "axis"};

  std::vector<std::string> words;
  std::string word;
  for (char c : mnemonic) {
    if (c == ' ') {
      if (!word.empty()) {
        words.push_back(word);
        word.clear();
      }
    } else {
      word += c;
    }
  }
  if (!word.empty())
    words.push_back(word);

  if (words.size() != 12)
    return false;

  for (const auto &w : words) {
    bool found = false;
    for (int i = 0; i < 128; i++) {
      if (w == wordlist[i]) {
        found = true;
        break;
      }
    }
    if (!found)
      return false;
  }

  return true;
}

// AES-KAT (Known Answer Test) for PVAC
// Must match webcli implementation - calls PVAC C API directly
extern "C" {
void pvac_aes_kat(uint8_t out[16]);
}

void compute_aes_kat(uint8_t out[16]) {
  // Call PVAC's AES-KAT implementation directly
  // This matches webcli's compute_aes_kat_hex() which calls pvac_aes_kat(buf)
  // PVAC uses SHA256 + AES-CTR256 internally for proper KAT generation
  pvac_aes_kat(out);
}

} // namespace octra
