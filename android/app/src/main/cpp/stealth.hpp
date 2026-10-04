#pragma once
#include <cstdint>
#include <cstring>
#include <string>
#include <array>
#include <vector>
#include <optional>
#include "crypto_utils.hpp"

extern "C" {
#include "tweetnacl.h"
}

namespace octra {

inline std::array<uint8_t, 32> ecdh_shared_secret(const uint8_t our_sk[32],
                                                   const uint8_t their_pub[32]) {
    uint8_t raw[32];
    crypto_scalarmult(raw, our_sk, their_pub);
    return sha256(raw, 32);
}

inline std::array<uint8_t, 16> compute_stealth_tag(const std::array<uint8_t, 32>& shared) {
    const char* domain = "OCTRA_STEALTH_TAG_V1";
    std::vector<uint8_t> buf(32 + strlen(domain));
    memcpy(buf.data(), shared.data(), 32);
    memcpy(buf.data() + 32, domain, strlen(domain));
    auto h = sha256(buf.data(), buf.size());
    std::array<uint8_t, 16> tag;
    memcpy(tag.data(), h.data(), 16);
    return tag;
}

inline std::array<uint8_t, 32> compute_claim_secret(const std::array<uint8_t, 32>& shared) {
    const char* domain = "OCTRA_CLAIM_SECRET_V1";
    std::vector<uint8_t> buf(32 + strlen(domain));
    memcpy(buf.data(), shared.data(), 32);
    memcpy(buf.data() + 32, domain, strlen(domain));
    return sha256(buf.data(), buf.size());
}

inline std::array<uint8_t, 32> compute_claim_pub(const std::array<uint8_t, 32>& claim_secret,
                                                  const std::string& addr) {
    const char* domain = "OCTRA_CLAIM_BIND_V1";
    std::vector<uint8_t> buf(32 + addr.size() + strlen(domain));
    memcpy(buf.data(), claim_secret.data(), 32);
    memcpy(buf.data() + 32, addr.data(), addr.size());
    memcpy(buf.data() + 32 + addr.size(), domain, strlen(domain));
    return sha256(buf.data(), buf.size());
}

struct StealthDecrypted {
    uint64_t amount;
    std::array<uint8_t, 32> blinding;
};

inline void derive_view_keypair(const uint8_t ed_sk[64],
                                uint8_t x_sk[32],
                                uint8_t x_pk[32]) {
    ed25519_sk_to_curve25519(ed_sk, x_sk);
    crypto_scalarmult_base(x_pk, x_sk);
}

}
