#pragma once
#include <string>
#include <vector>
#include <atomic>
#include "json.hpp"

namespace octra {

struct RpcResult {
    bool ok;
    nlohmann::json result;
    std::string error;
};

class RpcClient {
    std::string host_;
    std::string path_;
    bool ssl_;
    int port_;
    std::atomic<int> id_{0};

    void parse_url(const std::string& url);

public:
    RpcClient();
    explicit RpcClient(const std::string& url);
    void set_url(const std::string& url);

    RpcResult call(const std::string& method,
                   const nlohmann::json& params = nlohmann::json::array(),
                   int timeout_sec = 30);

    RpcResult get_balance(const std::string& addr);
    RpcResult get_account(const std::string& addr, int limit = 20);
    RpcResult get_transaction(const std::string& hash);
    RpcResult submit_tx(const nlohmann::json& tx);
    RpcResult get_view_pubkey(const std::string& addr);
    RpcResult get_encrypted_balance(const std::string& addr,
                                    const std::string& sig_b64,
                                    const std::string& pub_b64);
    RpcResult get_encrypted_cipher(const std::string& addr);
    RpcResult register_pvac_pubkey(const std::string& addr,
                                   const std::string& pk_b64,
                                   const std::string& sig_b64,
                                   const std::string& pub_b64,
                                   const std::string& aes_kat_hex = "");
    RpcResult get_pvac_pubkey(const std::string& addr);
    RpcResult register_public_key(const std::string& addr,
                                  const std::string& pub_b64,
                                  const std::string& sig_b64);
    RpcResult get_stealth_outputs(int from_epoch = 0);
    RpcResult staging_view();
    RpcResult compile_assembly(const std::string& source);
    RpcResult compile_aml(const std::string& source);
    RpcResult compute_contract_address(const std::string& bytecode_b64,
                                       const std::string& deployer,
                                       int nonce = 0);
    RpcResult vm_contract(const std::string& addr);
    RpcResult contract_receipt(const std::string& hash);
    RpcResult contract_call_view(const std::string& addr,
                                 const std::string& method,
                                 const nlohmann::json& params,
                                 const std::string& caller);
    RpcResult list_contracts();
    RpcResult contract_storage(const std::string& addr, const std::string& key);
    RpcResult contract_abi(const std::string& addr);
    RpcResult save_abi(const std::string& addr, const std::string& abi);
    RpcResult get_txs_by_address(const std::string& addr, int limit = 50, int offset = 0);
    RpcResult pool_view();

    std::string get_host() const { return host_; }
    int get_port() const { return port_; }
    bool is_ssl() const { return ssl_; }
    std::string get_path() const { return path_; }

private:
    RpcResult parse_response(const std::string& body);
};

}
