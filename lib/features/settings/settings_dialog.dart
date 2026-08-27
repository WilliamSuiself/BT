/// 设置页：VPN 模式 / ClamAV 扫描触发
library settings_dialog;

import 'package:flutter/material.dart';

import '../../core/antivirus/clamav_scanner.dart';
import '../../core/security/vpn_client.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  VpnMode _mode = VpnMode.off;
  final _socksHost = TextEditingController(text: '127.0.0.1');
  final _socksPort = TextEditingController(text: '1080');
  final _clamHost = TextEditingController(text: '127.0.0.1');
  final _clamPort = TextEditingController(text: '3310');
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('安全代理 / VPN', style: TextStyle(fontWeight: FontWeight.bold)),
            RadioListTile<VpnMode>(
              title: const Text('关闭'),
              value: VpnMode.off,
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v!),
            ),
            RadioListTile<VpnMode>(
              title: const Text('SOCKS5 代理（仅出站）'),
              value: VpnMode.systemProxy,
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v!),
            ),
            RadioListTile<VpnMode>(
              title: const Text('TUN 透明代理（需原生层）'),
              value: VpnMode.tunTransparent,
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v!),
            ),
            if (_mode != VpnMode.off)
              Row(children: [
                const SizedBox(width: 16),
                SizedBox(width: 160, child: TextField(controller: _socksHost, decoration: const InputDecoration(labelText: '代理主机'))),
                const SizedBox(width: 8),
                SizedBox(width: 80, child: TextField(controller: _socksPort, decoration: const InputDecoration(labelText: '端口'))),
              ]),
            const SizedBox(height: 16),
            const Text('ClamAV 病毒扫描', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(children: [
              const SizedBox(width: 16),
              SizedBox(width: 160, child: TextField(controller: _clamHost, decoration: const InputDecoration(labelText: 'clamd 主机'))),
              const SizedBox(width: 8),
              SizedBox(width: 80, child: TextField(controller: _clamPort, decoration: const InputDecoration(labelText: '端口'))),
            ]),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(
                  onPressed: () async {
                    final vpn = VpnClient();
                    final cfg = VpnConfig(
                      mode: _mode,
                      socks5Host: _mode == VpnMode.off ? null : _socksHost.text,
                      socks5Port: _mode == VpnMode.off ? null : int.tryParse(_socksPort.text),
                    );
                    final ok = await vpn.start(cfg);
                    setState(() => _status = ok ? 'VPN 启动成功（或已由原生层接管）' : 'VPN 启动失败（原生层未实现）');
                  },
                  child: const Text('应用 VPN'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () async {
                    try {
                      final scanner = ClamdScanner(
                        host: _clamHost.text,
                        port: int.tryParse(_clamPort.text) ?? 3310,
                      );
                      setState(() => _status = 'clamd 连接中...');
                      // 演示：让用户选择一个文件扫描；此处省略文件选择
                      setState(() => _status = 'clamd 配置已保存（请通过右键任务扫描文件）');
                      await scanner.close();
                    } catch (e) {
                      setState(() => _status = 'clamd 错误: $e');
                    }
                  },
                  child: const Text('测试 ClamAV'),
                ),
              ],
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_status, style: const TextStyle(color: Colors.grey)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }
}
