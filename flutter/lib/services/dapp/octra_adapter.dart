import '../dapp_bridge_protocol.dart';
import '../network_service.dart';
import '../wallet_service.dart';
import 'wallet_adapter.dart';

/// Octra-chain adapter: serves the legacy `octra_*` dialect, the RFC-O-1
/// aliases, the third-party (`0xio`) reads, and the `window.wallet` facade
/// reads/session calls over real wallet + RPC data.
///
/// Sensitive operations (send, contract submit, account sharing, network
/// switch claims) ALWAYS go through [AdapterContext] approval callbacks.
/// Cancel / dismiss == reject ([DappBridgeProtocol.userRejected]).
class OctraAdapter implements WalletAdapter {
  final WalletService wallets;
  final NetworkService networks;

  OctraAdapter({required this.wallets, required this.networks});

  @override
  String get id => 'octra';

  @override
  String get chainType => 'Octra';

  @override
  Set<String> get supportedMethods => const {
        // legacy
        'octra_accounts',
        'octra_chainId',
        'octra_getBalance',
        'octra_sendTransaction',
        'octra_callContract',
        'octra_callView',
        // RFC-O-1
        'octra_requestAccounts',
        'octra_getEncryptedBalance',
        // third-party reads + session
        'octra_networkInfo',
        'octra_permissions',
        'disconnect',
        'getBalance',
        'getPublicKey',
        'octra_sendContractTransaction',
        'octra_switchNetwork',
        // window.wallet facade
        'wallet_connect',
        'wallet_disconnect',
        'wallet_getAccounts',
        'wallet_getAddress',
        'wallet_getBalance',
        'wallet_getNetwork',
        'wallet_getNetworkInfo',
        'wallet_getNetworks',
        'wallet_getChainId',
        'wallet_getPermissions',
        'wallet_ping',
        // wallet_* twins of legacy submit/view (dual-stack, legacy kept)
        'wallet_sendTransaction',
        'wallet_callView',
      };

  @override
  bool supports(String canonicalMethod) =>
      supportedMethods.contains(canonicalMethod);

  String get _activeAddress => wallets.activeWallet?.address ?? '';

  Map<String, dynamic> _networkInfo() {
    final chainId = networks.activeChainId;
    final mainnet = chainId.contains('mainnet');
    return {
      'id': mainnet ? 'mainnet' : 'devnet',
      'name': mainnet ? 'Octra Mainnet' : 'Octra Devnet',
      'chainId': chainId,
      'rpcUrl': networks.activeNodeUrl,
      'explorerUrl': networks.activeExplorerUrl,
      'isTestnet': !mainnet,
    };
  }

  @override
  Future<AdapterResult> handle(DappRequest request, AdapterContext ctx) async {
    final method = request.method;
    switch (method) {
      case 'octra_accounts':
        return [_activeAddress];
      case 'octra_chainId':
      case 'wallet_getChainId':
        return networks.activeChainId;
      case 'octra_getBalance':
      case 'wallet_getBalance':
        return {
          'balance': wallets.publicBalance,
          'encryptedBalance': wallets.encryptedBalance,
          'raw': wallets.balanceRaw,
          'encryptedRaw': wallets.encryptedBalanceRaw,
        };
      case 'getBalance':
        return {
          'balance': wallets.publicBalance,
          'privateBalance': wallets.encryptedBalance,
        };
      case 'octra_networkInfo':
      case 'wallet_getNetworkInfo':
        return _networkInfo();
      case 'octra_permissions':
      case 'wallet_getPermissions':
        return DappBridgeProtocol.requestedPermissions(request.params);
      case 'wallet_getNetworks':
        return [_networkInfo()];
      case 'wallet_getNetwork':
        return DappBridgeProtocol.networkIdForChain(networks.activeChainId);
      case 'wallet_ping':
        return DappBridgeProtocol.buildPing(
          connected: _activeAddress.isNotEmpty,
          locked: _activeAddress.isEmpty,
          origin: request.origin,
          tsMs: DateTime.now().millisecondsSinceEpoch,
        );
      case 'disconnect':
      case 'wallet_disconnect':
        return {'success': true};
      case 'wallet_getAccounts':
        final addr = _activeAddress;
        return addr.isEmpty ? [] : [addr];
      case 'wallet_getAddress':
        return _activeAddress;
      case 'octra_requestAccounts':
      case 'wallet_connect':
        return _handleRequestAccounts(request, ctx);
      case 'octra_getEncryptedBalance':
        return _handleEncryptedBalance();
      case 'getPublicKey':
        throw DappError('No public key available for the active wallet',
            DappBridgeProtocol.unauthorized);
      case 'octra_switchNetwork':
        return _handleSwitchNetwork(request, ctx);
      case 'octra_callView':
      case 'wallet_callView':
        return _handleCallView(request);
      case 'octra_sendTransaction':
      case 'wallet_sendTransaction':
        return _handleSend(request, ctx);
      case 'octra_sendContractTransaction':
        return _handleContractTransaction(request, ctx);
      case 'octra_callContract':
        return _handleCallContract(request, ctx);
      default:
        if (DappBridgeProtocol.isKnownUnsupported(method)) {
          throw DappError(
              '$method is not supported by this wallet (sign-only '
              'submission split, message signing and FHE-private '
              'primitives stay in the wallet UI)',
              DappBridgeProtocol.unsupportedMethod);
        }
        throw DappError('Unsupported method: $method',
            DappBridgeProtocol.unsupportedMethod);
    }
  }

  Future<AdapterResult> _handleRequestAccounts(
      DappRequest request, AdapterContext ctx) async {
    final address = _activeAddress;
    if (address.isEmpty) {
      throw DappError('No active wallet', DappBridgeProtocol.unauthorized);
    }
    final approved = await ctx.requestApproval(
      title: 'Share Account',
      body: 'This dApp wants to see your Octra address.\n\n'
          'Origin: ${request.origin}\n'
          'Address: ${_short(address)}',
      confirmLabel: 'Share',
      origin: request.origin,
    );
    // Cancel / dismiss == reject. Never fall through to approve.
    if (!approved) {
      throw DappError(
          'User rejected connection', DappBridgeProtocol.userRejected);
    }
    return [address];
  }

  Future<AdapterResult> _handleEncryptedBalance() async {
    if (_activeAddress.isEmpty) {
      throw DappError('No active wallet', DappBridgeProtocol.unauthorized);
    }
    final cipher = wallets.encryptedBalanceCipher;
    if (cipher == null || cipher.isEmpty) {
      throw DappError(
          'Encrypted balance unavailable — refresh the wallet first');
    }
    return {'address': _activeAddress, 'cipher': cipher};
  }

  Future<AdapterResult> _handleSwitchNetwork(
      DappRequest request, AdapterContext ctx) async {
    // The wallet follows its own configured node; a page can never move it.
    // Approval is still required so the user sees the attempted switch.
    String wanted = '';
    try {
      final o = DappBridgeProtocol.txObject(request.params);
      wanted = (o['networkId'] ?? o['network'] ?? '').toString().trim();
    } catch (_) {
      wanted = '';
    }
    final current =
        networks.activeChainId.contains('mainnet') ? 'mainnet' : 'devnet';
    final same = wanted.isNotEmpty &&
        (wanted.toLowerCase() == current ||
            wanted.toLowerCase() == networks.activeChainId.toLowerCase());
    if (!same && wanted.isNotEmpty) {
      final approved = await ctx.requestApproval(
        title: 'Switch Network',
        body: 'This dApp wants to switch to "$wanted".\n'
            'Wallet stays on $current (${networks.activeChainId}).\n'
            'Origin: ${request.origin}',
        confirmLabel: 'Understood',
        origin: request.origin,
      );
      if (!approved) {
        throw DappError(
            'User rejected network switch', DappBridgeProtocol.userRejected);
      }
    }
    return {'network': current, 'switched': same};
  }

  Future<AdapterResult> _handleCallView(DappRequest request) async {
    final params = request.params;
    if (params.length < 2) {
      throw DappError(
          'octra_callView requires [contractAddr, functionName, args]');
    }
    final addr = params[0].toString();
    final fn = params[1].toString();
    if (addr.isEmpty || fn.isEmpty) {
      throw DappError('octra_callView requires non-empty address + method');
    }
    final args = params.length > 2 && params[2] is List
        ? (params[2] as List)
        : <dynamic>[];
    final caller = params.length > 3 ? params[3].toString() : _activeAddress;
    try {
      return await wallets.rpcCall(
          networks.activeNodeUrl, 'contract_call', [addr, fn, args, caller]);
    } catch (e) {
      throw DappError('Network unavailable: ${_shortErr(e)}',
          DappBridgeProtocol.networkUnavailable);
    }
  }

  Future<AdapterResult> _handleSend(
      DappRequest request, AdapterContext ctx) async {
    late final Map<String, dynamic> tx;
    try {
      tx = DappBridgeProtocol.txObject(request.params);
    } catch (e) {
      throw DappError('Invalid params: $e');
    }
    if (tx['isPrivate'] == true) {
      throw DappError(
          'Private transfers are not served over the provider — '
          'use the wallet UI',
          DappBridgeProtocol.unsupportedMethod);
    }
    final to = (tx['to'] ?? '').toString().trim();
    if (to.isEmpty) {
      throw DappError('Invalid params: missing recipient address');
    }
    late final String amount;
    try {
      amount = DappBridgeProtocol.resolveTxAmount(tx);
    } catch (e) {
      throw DappError('Invalid params: $e');
    }
    if (amount == '0') {
      throw DappError('Invalid params: amount must be greater than 0');
    }
    var memo = (tx['message'] ?? tx['memo'])?.toString().trim();
    if (memo != null) {
      if (memo.isEmpty) {
        memo = null;
      } else if (memo.length > 1000) {
        throw DappError('Invalid params: message over 1000 chars');
      }
    }
    final approved = await ctx.requestTxApproval(
      title: 'Send Transaction',
      to: to,
      amount: amount,
      extra:
          '${memo != null ? 'Message: $memo\n' : ''}Origin: ${request.origin}',
      origin: request.origin,
    );
    if (!approved) {
      throw DappError(
          'User rejected transaction', DappBridgeProtocol.userRejected);
    }
    try {
      final hash = await wallets.sendTransaction(
        nodeUrl: networks.activeNodeUrl,
        toAddress: to,
        amount: amount,
        memo: memo,
      );
      return {
        'tx_hash': hash,
        'hash': hash,
        'accepted': true,
        'success': true,
        'ok': true,
      };
    } catch (e) {
      throw DappError('Transaction failed: ${_shortErr(e)}',
          DappBridgeProtocol.networkUnavailable);
    }
  }

  Future<AdapterResult> _handleContractTransaction(
      DappRequest request, AdapterContext ctx) async {
    late final Map<String, dynamic> o;
    try {
      o = DappBridgeProtocol.txObject(request.params);
    } catch (e) {
      throw DappError('Invalid params: $e');
    }
    final contract = (o['contract'] ?? '').toString().trim();
    final fn = (o['method'] ?? '').toString().trim();
    if (contract.isEmpty || fn.isEmpty) {
      throw DappError('Invalid params: call needs contract + method');
    }
    final args = o['params'] is List ? (o['params'] as List) : [];
    late final String amount;
    try {
      amount = o.containsKey('amount') && o['amount'] != null
          ? DappBridgeProtocol.resolveTxAmount(o)
          : '0';
    } catch (e) {
      throw DappError('Invalid params: $e');
    }
    return _submitContract(request, ctx, contract, fn, args, amount);
  }

  Future<AdapterResult> _handleCallContract(
      DappRequest request, AdapterContext ctx) async {
    final params = request.params;
    if (params.isNotEmpty &&
        params[0] is Map &&
        DappBridgeProtocol.isViewCall(
            Map<String, dynamic>.from(params[0] as Map))) {
      final view = Map<String, dynamic>.from(params[0] as Map);
      final contract = (view['contract'] ?? '').toString().trim();
      final fn = (view['method'] ?? '').toString().trim();
      if (contract.isEmpty || fn.isEmpty) {
        throw DappError('Invalid params: view needs contract + method');
      }
      final args = view['params'] is List ? (view['params'] as List) : [];
      final caller = (view['caller'] ?? _activeAddress).toString();
      try {
        return await wallets.rpcCall(networks.activeNodeUrl, 'contract_call',
            [contract, fn, args, caller]);
      } catch (e) {
        throw DappError('Network unavailable: ${_shortErr(e)}',
            DappBridgeProtocol.networkUnavailable);
      }
    }
    if (params.isEmpty) {
      throw DappError('octra_callContract requires params');
    }
    final contractAddr = params[0].toString();
    final fn = params.length > 1 ? params[1].toString() : '';
    if (contractAddr.isEmpty || fn.isEmpty) {
      throw DappError('octra_callContract requires contract + method');
    }
    final callArgs =
        params.length > 2 && params[2] is List ? (params[2] as List) : [];
    final callAmount = (params.length > 3 ? params[3] : '0').toString();
    return _submitContract(
        request, ctx, contractAddr, fn, callArgs, callAmount);
  }

  Future<AdapterResult> _submitContract(
    DappRequest request,
    AdapterContext ctx,
    String contractAddr,
    String fn,
    List callArgs,
    String callAmount,
  ) async {
    final approved = await ctx.requestTxApproval(
      title: 'Contract Call',
      to: contractAddr,
      amount: callAmount,
      extra: 'Function: $fn\nOrigin: ${request.origin}',
      origin: request.origin,
    );
    if (!approved) {
      throw DappError(
          'User rejected contract call', DappBridgeProtocol.userRejected);
    }
    try {
      late final String txHash;
      if (callAmount != '0' && callAmount.isNotEmpty) {
        txHash = await wallets.sendContractCallTx(
          nodeUrl: networks.activeNodeUrl,
          tokenAddress: contractAddr,
          toAddress: contractAddr,
          amount: callAmount,
        );
      } else {
        txHash = await wallets.sendContractCall(
          nodeUrl: networks.activeNodeUrl,
          contractAddress: contractAddr,
          functionName: fn,
          args: callArgs,
        );
      }
      return {
        'tx_hash': txHash,
        'hash': txHash,
        'accepted': true,
        'success': true,
        'ok': true,
      };
    } catch (e) {
      throw DappError('Contract call failed: ${_shortErr(e)}',
          DappBridgeProtocol.networkUnavailable);
    }
  }

  static String _short(String addr) => addr.length > 16
      ? '${addr.substring(0, 8)}…${addr.substring(addr.length - 6)}'
      : addr;

  static String _shortErr(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '');
    return s.length > 220 ? '${s.substring(0, 220)}…' : s;
  }
}
