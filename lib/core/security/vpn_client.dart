/// VPN/TUN 代理客户端（Dart 侧 API）
///
/// 通过 Platform Channel 调到原生层（macOS/Windows/Linux），
/// 由原生层启动 sing-box 或类似内核，加密 BT 流量。
library vpn_client;

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// VPN 代理模式
enum VpnMode { off, systemProxy, tunTransparent }

class VpnConfig {
  final VpnMode mode;
  final String? socks5Host;
  final int? socks5Port;
  final String? tunInterfaceName;

  const VpnConfig({
    this.mode = VpnMode.off,
    this.socks5Host,
    this.socks5Port,
    this.tunInterfaceName,
  });
}

class VpnClient {
  static const _channel = MethodChannel('bt_safe/vpn');

  /// 启动 VPN；返回是否启动成功
  Future<bool> start(VpnConfig config) async {
    try {
      final ok = await _channel.invokeMethod<bool>('start', {
        'mode': config.mode.name,
        if (config.socks5Host != null) 'socks5Host': config.socks5Host,
        if (config.socks5Port != null) 'socks5Port': config.socks5Port,
        if (config.tunInterfaceName != null) 'tun': config.tunInterfaceName,
      });
      return ok ?? false;
    } on MissingPluginException {
      // 原生侧未实现
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stop() async {
    try {
      final ok = await _channel.invokeMethod<bool>('stop');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<String?> status() async {
    try {
      return await _channel.invokeMethod<String>('status');
    } catch (_) {
      return null;
    }
  }
}

/// 简化代理：直接让 Flutter Dart 侧的 Socket 走系统代理
/// 用于 SOCKS5 模式（仅出站，无需原生 TUN）。
class ProxySocketFactory {
  final HttpOverrides? overrides;
  ProxySocketFactory(this.overrides);

  /// 使用 SOCKS5 代理的 Socket.connect（简化：仅 HTTP CONNECT 演示）
  /// 生产环境请用 dart_socks5 或类似包。
  static Future<Socket> connectViaSocks5(
      String targetHost, int targetPort, String proxyHost, int proxyPort) async {
    // 占位实现：实际需实现 SOCKS5 握手
    throw UnsupportedError(
        'SOCKS5 客户端需 dart_socks5 库；请参考 README 添加依赖');
  }
}
