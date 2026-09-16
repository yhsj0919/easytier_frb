import 'dart:io';

import 'package:flutter/services.dart';

/// Android 系统 VpnService 的内部桥接层。
final class PlatformVpn {
  PlatformVpn._();

  static const _methodChannel = MethodChannel('easytier_flutter/vpn');
  static const _eventChannel = EventChannel('easytier_flutter/vpn_events');
  static Stream<Map<String, dynamic>>? _events;

  static bool get isRequired => Platform.isAndroid;

  static Stream<Map<String, dynamic>> get events {
    return _events ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map))
        .asBroadcastStream();
  }

  static Stream<Map<String, dynamic>> get started => events
      .where((event) => event['event'] == 'vpn_service_start')
      .map((event) => Map<String, dynamic>.from(event['data'] as Map));

  static Future<bool> prepare() async {
    if (!isRequired) return true;
    return await _methodChannel.invokeMethod<bool>('prepareVpn') ?? false;
  }

  static Future<void> start({
    required String instanceId,
    required String ipv4Cidr,
    List<String> routes = const [],
    int mtu = 1300,
  }) async {
    if (!isRequired) return;
    await _methodChannel.invokeMethod<void>('startVpn', {
      'configId': instanceId,
      'ipv4Addr': ipv4Cidr,
      'routes': routes,
      'mtu': mtu,
    });
  }

  static Future<void> stop() async {
    if (!isRequired) return;
    await _methodChannel.invokeMethod<void>('stopVpn');
  }
}
