import '../dapp_bridge_protocol.dart';
import 'wallet_adapter.dart';

/// Dispatches canonical methods to the registered [WalletAdapter].
///
/// Unknown methods fall through to an explicit unsupported error —
/// never silent, never mocked.
class AdapterRegistry {
  final List<WalletAdapter> adapters;

  const AdapterRegistry(this.adapters);

  WalletAdapter? adapterFor(String canonicalMethod) {
    for (final a in adapters) {
      if (a.supports(canonicalMethod)) return a;
    }
    return null;
  }

  bool isSupported(String? method) {
    final m = DappBridgeProtocol.canonicalize(method);
    return adapterFor(m) != null;
  }

  bool isKnownUnsupported(String? method) =>
      DappBridgeProtocol.isKnownUnsupported(method);

  Future<AdapterResult> dispatch(
      DappRequest request, AdapterContext ctx) {
    final adapter = adapterFor(request.method);
    if (adapter == null) {
      if (isKnownUnsupported(request.method)) {
        throw DappError(
            '${request.method} is not supported by this wallet',
            DappBridgeProtocol.unsupportedMethod);
      }
      throw DappError('Unsupported method: ${request.method}',
          DappBridgeProtocol.unsupportedMethod);
    }
    return adapter.handle(request, ctx);
  }
}
