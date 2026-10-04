import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProxyConfig {
  final String name;
  final String host;
  final int port;
  final String type; // "SOCKS" or "HTTP"
  final bool isDefault;

  const ProxyConfig({
    required this.name,
    required this.host,
    required this.port,
    required this.type,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'type': type,
        'isDefault': isDefault,
      };

  factory ProxyConfig.fromJson(Map<String, dynamic> json) => ProxyConfig(
        name: json['name'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        type: json['type'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
      );
}

class TorProxyService extends ChangeNotifier {
  static const String _kPrefsName = 'tor_proxy_settings';
  static const String _kEnabled = 'enabled';
  static const String _kActiveHost = 'active_host';
  static const String _kActivePort = 'active_port';
  static const String _kActiveType = 'active_type'; // "SOCKS" or "HTTP"
  static const String _kServersList = 'servers_list';

  bool _enabled = false;
  String _activeHost = '127.0.0.1';
  int _activePort = 9050;
  String _activeType = 'SOCKS';
  List<ProxyConfig> _servers = [];

  bool get enabled => _enabled;
  String get activeHost => _activeHost;
  int get activePort => _activePort;
  String get activeType => _activeType;
  List<ProxyConfig> get servers => List.unmodifiable(_servers);

  static final TorProxyService instance = TorProxyService._();

  factory TorProxyService() => instance;

  TorProxyService._() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('${_kPrefsName}_$_kEnabled') ?? false;
    _activeHost = prefs.getString('${_kPrefsName}_$_kActiveHost') ?? '127.0.0.1';
    _activePort = prefs.getInt('${_kPrefsName}_$_kActivePort') ?? 9050;
    _activeType = prefs.getString('${_kPrefsName}_$_kActiveType') ?? 'SOCKS';

    final serversJson = prefs.getString('${_kPrefsName}_$_kServersList');
    if (serversJson == null || serversJson.isEmpty) {
      _servers = [
        const ProxyConfig(
            name: 'Orbot SOCKS (Lokal)',
            host: '127.0.0.1',
            port: 9050,
            type: 'SOCKS',
            isDefault: true),
        const ProxyConfig(
            name: 'Orbot HTTP (Lokal)',
            host: '127.0.0.1',
            port: 8118,
            type: 'HTTP',
            isDefault: true),
        const ProxyConfig(
            name: 'Public Tor Proxy (Free)',
            host: '173.249.49.52',
            port: 9050,
            type: 'SOCKS',
            isDefault: true),
        const ProxyConfig(
            name: 'SOCKS5 Proxy (Fast)',
            host: '45.140.13.125',
            port: 9050,
            type: 'SOCKS',
            isDefault: true),
      ];
      await _saveServers();
    } else {
      try {
        final List<dynamic> decoded = jsonDecode(serversJson);
        _servers = decoded
            .map((e) => ProxyConfig.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[TorProxyService] Failed to load servers JSON: $e');
      }
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kPrefsName}_$_kEnabled', enabled);
    notifyListeners();
  }

  Future<void> setActiveProxy(String host, int port, String type) async {
    _activeHost = host;
    _activePort = port;
    _activeType = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_kPrefsName}_$_kActiveHost', host);
    await prefs.setInt('${_kPrefsName}_$_kActivePort', port);
    await prefs.setString('${_kPrefsName}_$_kActiveType', type);
    notifyListeners();
  }

  Future<void> addProxyServer(ProxyConfig config) async {
    _servers.add(config);
    await _saveServers();
    notifyListeners();
  }

  Future<bool> removeProxyServer(String host, int port) async {
    int idx = -1;
    for (int i = 0; i < _servers.length; i++) {
      if (_servers[i].host == host && _servers[i].port == port) {
        if (_servers[i].isDefault) return false; // Default servers cannot be removed
        idx = i;
        break;
      }
    }
    if (idx != -1) {
      _servers.removeAt(idx);
      await _saveServers();
      // If we deleted the currently active proxy, fallback to Orbot SOCKS default
      if (_activeHost == host && _activePort == port) {
        await setActiveProxy('127.0.0.1', 9050, 'SOCKS');
      } else {
        notifyListeners();
      }
      return true;
    }
    return false;
  }

  Future<void> _saveServers() async {
    final prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(_servers.map((e) => e.toJson()).toList());
    await prefs.setString('${_kPrefsName}_$_kServersList', raw);
  }
}
