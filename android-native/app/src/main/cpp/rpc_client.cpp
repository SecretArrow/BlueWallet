#include "rpc_client.hpp"

namespace octra {

void RpcClient::parse_url(const std::string& url) {
    std::string u = url;
    ssl_ = false;
    port_ = 80;
    if (u.rfind("https://", 0) == 0) {
        ssl_ = true;
        port_ = 443;
        u = u.substr(8);
    } else if (u.rfind("http://", 0) == 0) {
        u = u.substr(7);
    }
    auto slash = u.find('/');
    if (slash != std::string::npos) {
        path_ = u.substr(slash);
        host_ = u.substr(0, slash);
    } else {
        path_ = "/rpc";
        host_ = u;
    }
    auto colon = host_.find(':');
    if (colon != std::string::npos) {
        port_ = std::stoi(host_.substr(colon + 1));
        host_ = host_.substr(0, colon);
    }
}

RpcClient::RpcClient() : path_("/rpc"), ssl_(true), port_(443) {}

RpcClient::RpcClient(const std::string& url) { parse_url(url); }

void RpcClient::set_url(const std::string& url) { parse_url(url); }

RpcResult RpcClient::call(const std::string& method,
                          const nlohmann::json& params,
                          int timeout_sec) {
    nlohmann::json req;
    req["jsonrpc"] = "2.0";
    req["method"] = method;
    req["params"] = params;
    req["id"] = ++id_;
    
    return {false, {}, "HTTP client not implemented in native layer - use Java"};
}

RpcResult RpcClient::get_balance(const std::string& addr) {
    return call("octra_balance", {addr});
}

RpcResult RpcClient::get_account(const std::string& addr, int limit) {
    return call("octra_account", {addr, limit});
}

RpcResult RpcClient::get_transaction(const std::string& hash) {
    return call("octra_transaction", {hash});
}

RpcResult RpcClient::submit_tx(const nlohmann::json& tx) {
    return call("octra_submit", nlohmann::json::array({tx}));
}

RpcResult RpcClient::get_view_pubkey(const std::string& addr) {
    return call("octra_viewPubkey", {addr});
}

RpcResult RpcClient::get_encrypted_balance(const std::string& addr,
                                           const std::string& sig_b64,
                                           const std::string& pub_b64) {
    return call("octra_encryptedBalance", {addr, sig_b64, pub_b64});
}

RpcResult RpcClient::get_encrypted_cipher(const std::string& addr) {
    return call("octra_encryptedCipher", {addr});
}

RpcResult RpcClient::register_pvac_pubkey(const std::string& addr,
                                          const std::string& pk_b64,
                                          const std::string& sig_b64,
                                          const std::string& pub_b64,
                                          const std::string& aes_kat_hex) {
    return call("octra_registerPvacPubkey", {addr, pk_b64, sig_b64, pub_b64, aes_kat_hex});
}

RpcResult RpcClient::get_pvac_pubkey(const std::string& addr) {
    return call("octra_pvacPubkey", {addr});
}

RpcResult RpcClient::register_public_key(const std::string& addr,
                                         const std::string& pub_b64,
                                         const std::string& sig_b64) {
    return call("octra_registerPublicKey", {addr, pub_b64, sig_b64});
}

RpcResult RpcClient::get_stealth_outputs(int from_epoch) {
    return call("octra_stealthOutputs", {from_epoch});
}

RpcResult RpcClient::staging_view() {
    return call("staging_view", nlohmann::json::array(), 5);
}

RpcResult RpcClient::compile_assembly(const std::string& source) {
    return call("octra_compileAssembly", {source}, 10);
}

RpcResult RpcClient::compile_aml(const std::string& source) {
    return call("octra_compileAml", {source}, 10);
}

RpcResult RpcClient::compute_contract_address(const std::string& bytecode_b64,
                                              const std::string& deployer,
                                              int nonce) {
    return call("octra_computeContractAddress", {bytecode_b64, deployer, nonce});
}

RpcResult RpcClient::vm_contract(const std::string& addr) {
    return call("vm_contract", {addr});
}

RpcResult RpcClient::contract_receipt(const std::string& hash) {
    return call("contract_receipt", {hash});
}

RpcResult RpcClient::contract_call_view(const std::string& addr,
                                        const std::string& method,
                                        const nlohmann::json& params,
                                        const std::string& caller) {
    return call("contract_call", {addr, method, params, caller}, 15);
}

RpcResult RpcClient::list_contracts() {
    return call("octra_listContracts", nlohmann::json::array(), 10);
}

RpcResult RpcClient::contract_storage(const std::string& addr, const std::string& key) {
    return call("octra_contractStorage", {addr, key});
}

RpcResult RpcClient::contract_abi(const std::string& addr) {
    return call("octra_contractAbi", {addr});
}

RpcResult RpcClient::save_abi(const std::string& addr, const std::string& abi) {
    return call("contract_saveAbi", {addr, abi});
}

RpcResult RpcClient::get_txs_by_address(const std::string& addr, int limit, int offset) {
    return call("octra_transactionsByAddress", {addr, limit, offset}, 15);
}

RpcResult RpcClient::pool_view() {
    return call("pool_view", nlohmann::json::array(), 5);
}

RpcResult RpcClient::parse_response(const std::string& body) {
    try {
        auto j = nlohmann::json::parse(body);
        if (j.contains("result"))
            return {true, j["result"], ""};
        if (j.contains("error")) {
            auto& e = j["error"];
            std::string msg = e.is_object() ? e.value("message", "rpc error") : e.dump();
            return {false, {}, msg};
        }
        return {false, {}, "unknown rpc response"};
    } catch (const std::exception& ex) {
        return {false, {}, std::string("parse error: ") + ex.what()};
    }
}

}
