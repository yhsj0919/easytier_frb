import 'package:toml/toml.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 网络配置（TOML 为权威数据源）。
class NetworkConfig {
  NetworkConfig({
    required this.id,
    Map<String, dynamic>? tomlData,
    this.configName = '',
  }) : _tomlData = _deepCopyMap(tomlData ?? <String, dynamic>{});

  factory NetworkConfig.fromToml(String toml, {String? id}) {
    final parsed = TomlDocument.parse(toml).toMap();
    final rawId = _asString(parsed['instance_id']);
    return NetworkConfig(
      id: id ?? (rawId.isEmpty ? _uuid.v4() : rawId),
      tomlData: parsed,
    );
  }

  final String id;
  final String configName;
  final Map<String, dynamic> _tomlData;

  String get displayName {
    if (configName.trim().isNotEmpty) return configName.trim();
    if (networkName.isNotEmpty) return networkName;
    if (instanceName.isNotEmpty) return instanceName;
    return id;
  }

  String get instanceName => _asString(_tomlData['instance_name']);
  set instanceName(String value) => _setTop('instance_name', value.trim());

  String get hostname => _asString(_tomlData['hostname']);
  set hostname(String value) => _setTop('hostname', value.trim());

  Map<String, dynamic> get tomlMap => _deepCopyMap(_tomlData);

  String get networkName =>
      _getPath(const ['network_identity', 'network_name']);

  set networkName(String value) {
    final t = value.trim();
    if (t.isEmpty) {
      _removePath(const ['network_identity', 'network_name']);
      return;
    }
    _setPath(const ['network_identity', 'network_name'], t);
  }

  String get networkSecret =>
      _getPath(const ['network_identity', 'network_secret']);

  set networkSecret(String value) {
    final identity = _ensureMap(const ['network_identity']);
    identity['network_secret'] = value;
  }

  String get virtualIpv4 => _asString(_tomlData['ipv4']);
  set virtualIpv4(String value) => _setTop('ipv4', value.trim());

  bool get dhcp => _tomlData['dhcp'] == true;
  set dhcp(bool value) => _setTop('dhcp', value, removeIfFalse: true);

  List<String> get listeners => _stringList(_tomlData['listeners']);
  set listeners(List<String> value) => _setTop('listeners', _cleanList(value));

  List<String> get peerUrls {
    final peers = _tomlData['peer'];
    if (peers is! List) return const [];
    return peers
        .whereType<Map>()
        .map((e) => _asString(e['uri']))
        .where((u) => u.isNotEmpty)
        .toList();
  }

  set peerUrls(List<String> value) {
    _tomlData['peer'] = value
        .map((uri) => uri.trim())
        .where((uri) => uri.isNotEmpty)
        .map((uri) => <String, dynamic>{'uri': uri})
        .toList();
  }

  bool get latencyFirst => _flagBool('latency_first');
  int get mtu => _flagInt('mtu', fallback: 1380);
  set mtu(int value) => _setFlag('mtu', value);

  List<String> get manualRoutes => _stringList(_tomlData['routes']);
  List<String> get proxyCidrs {
    final proxies = _tomlData['proxy_networks'];
    if (proxies is! List) return const [];
    return proxies
        .whereType<Map>()
        .map((e) => _asString(e['cidr']))
        .where((c) => c.isNotEmpty)
        .toList();
  }

  String toToml({bool forAndroidVpn = false}) {
    final data = _deepCopyMap(_tomlData);
    data['instance_id'] = id;
    if (forAndroidVpn) {
      final flags = _ensureMap(const ['flags']);
      flags['no_tun'] = true;
    }
    if (listeners.isEmpty && !forAndroidVpn) {
      data['listeners'] = ['tcp://0.0.0.0:11010'];
    }
    return TomlDocument.fromMap(data).toString();
  }

  NetworkConfig copyWith({
    String? configName,
    Map<String, dynamic>? tomlData,
  }) {
    return NetworkConfig(
      id: id,
      configName: configName ?? this.configName,
      tomlData: tomlData ?? _tomlData,
    );
  }

  void _setTop(String key, dynamic value, {bool removeIfFalse = false}) {
    if (removeIfFalse && value == false) {
      _tomlData.remove(key);
      return;
    }
    if (value is String && value.isEmpty) {
      _tomlData.remove(key);
      return;
    }
    _tomlData[key] = value;
  }

  String _getPath(List<String> path) {
    dynamic cur = _tomlData;
    for (final key in path) {
      if (cur is! Map) return '';
      cur = cur[key];
    }
    return _asString(cur);
  }

  void _setPath(List<String> path, String value) {
    final parent = _ensureMap(path.sublist(0, path.length - 1));
    parent[path.last] = value;
  }

  void _removePath(List<String> path) {
    if (path.length == 1) {
      _tomlData.remove(path.first);
      return;
    }
    dynamic cur = _tomlData;
    for (var i = 0; i < path.length - 1; i++) {
      if (cur is! Map) return;
      cur = cur[path[i]];
    }
    if (cur is Map) {
      cur.remove(path.last);
    }
  }

  Map<String, dynamic> _ensureMap(List<String> path) {
    if (path.isEmpty) return _tomlData;
    dynamic cur = _tomlData;
    for (final key in path) {
      if (cur is! Map<String, dynamic>) {
        throw StateError('invalid path');
      }
      final next = cur[key];
      if (next is! Map<String, dynamic>) {
        final created = <String, dynamic>{};
        cur[key] = created;
        cur = created;
      } else {
        cur = next;
      }
    }
    return cur as Map<String, dynamic>;
  }

  bool _flagBool(String key) {
    final flags = _tomlData['flags'];
    if (flags is! Map) return false;
    return flags[key] == true;
  }

  int _flagInt(String key, {required int fallback}) {
    final flags = _tomlData['flags'];
    if (flags is! Map) return fallback;
    final v = flags[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  void _setFlag(String key, dynamic value) {
    final flags = _ensureMap(const ['flags']);
    flags[key] = value;
  }

  static List<String> _cleanList(List<String> value) {
    return value.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) {
    return Map<String, dynamic>.from(
      source.map(
        (key, value) => MapEntry(
          key,
          value is Map
              ? _deepCopyMap(Map<String, dynamic>.from(value))
              : value is List
              ? List<dynamic>.from(value)
              : value,
        ),
      ),
    );
  }

  static String _asString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
}
