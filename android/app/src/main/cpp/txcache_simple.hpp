/*
    Simplified TxCache for Android - In-memory version without LevelDB dependency
    Based on webcli/lib/txcache.hpp but uses std::unordered_map instead of LevelDB
*/

#pragma once
#include <string>
#include <vector>
#include <unordered_map>
#include <chrono>
#include "json.hpp"

class TxCache {
    std::unordered_map<std::string, std::string> cache_;
    std::string path_; // kept for API compatibility but not used for storage
    
public:
    bool open(const std::string& path) {
        path_ = path;
        return true; // Always succeeds for in-memory version
    }

    void close() { cache_.clear(); path_.clear(); }
    ~TxCache() { close(); }

    void clear() {
        cache_.clear();
    }

    void ensure_rpc(const std::string& rpc_url) {
        auto stored = get("meta:rpc_url");
        if (stored != rpc_url) {
            if (!stored.empty())
                fprintf(stderr, "txcache: rpc mismatch (%s != %s), clearing\n",
                        stored.c_str(), rpc_url.c_str());
            clear();
            put("meta:rpc_url", rpc_url);
        }
    }

    void put(const std::string& key, const std::string& val) {
        cache_[key] = val;
    }

    std::string get(const std::string& key) {
        auto it = cache_.find(key);
        if (it != cache_.end()) return it->second;
        return "";
    }

    int get_total(const std::string& addr) {
        auto v = get("total:" + addr);
        return v.empty() ? 0 : std::stoi(v);
    }

    void set_total(const std::string& addr, int total) {
        put("total:" + addr, std::to_string(total));
    }

    void store_tx(const nlohmann::json& tx) {
        std::string hash = tx.value("hash", "");
        if (hash.empty()) return;
        put("tx:" + hash, tx.dump());
        double ts = tx.value("timestamp", 0.0);
        char idx[128];
        snprintf(idx, sizeof(idx), "idx:%.6f:%s", ts, hash.c_str());
        put(idx, hash);
    }

    std::vector<nlohmann::json> get_txs(const std::string& addr, int max = 50) {
        std::vector<nlohmann::json> result;
        // Simple implementation - in production you'd want to index by address
        // For now, return empty vector as this is a simplified version
        return result;
    }

    void prune_old(int keep_last = 500) {
        // Simplified - no pruning needed for in-memory version
        // In production, you'd want to limit cache size
    }

    // Fee caching
    void cache_fee(const std::string& key, const std::string& fee_json) {
        put("fee:" + key, fee_json);
    }

    std::string get_cached_fee(const std::string& key) {
        return get("fee:" + key);
    }

    // PK caching
    void cache_pk(const std::string& address, const std::string& pk_json) {
        put("pk:" + address, pk_json);
    }

    std::string get_cached_pk(const std::string& address) {
        return get("pk:" + address);
    }
};
