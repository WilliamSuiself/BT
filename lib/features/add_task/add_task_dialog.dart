/// 添加任务对话框：接受磁力链 / .torrent 文件路径
library add_task_dialog;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/bittorrent/magnet.dart';
import '../../core/bittorrent/torrent_parser.dart';
import '../../models/torrent_info.dart';

class AddTaskResult {
  final TorrentInfo? torrent;
  final String? magnetName;
  final Uint8List? magnetInfoHash;
  final String? inputRaw;
  AddTaskResult.torrent(this.torrent, {this.inputRaw})
      : magnetName = null,
        magnetInfoHash = null;
  AddTaskResult.magnet(this.magnetInfoHash, this.magnetName, {this.inputRaw})
      : torrent = null;
}

Future<AddTaskResult?> showAddTaskDialog(BuildContext context) async {
  final controller = TextEditingController();
  String? hint;
  return showDialog<AddTaskResult>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: const Text('添加 BT 任务'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: '磁力链 / .torrent 路径',
                    hintText: 'magnet:?xt=urn:btih:... 或 /path/to/file.torrent',
                    errorText: hint,
                  ),
                  minLines: 1,
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  setSt(() => hint = '内容不能为空');
                  return;
                }
                final r = _parseInput(raw);
                if (r == null) {
                  setSt(() => hint = '无法解析输入');
                  return;
                }
                Navigator.pop(ctx, r);
              },
              child: const Text('添加'),
            ),
          ],
        );
      });
    },
  );
}

AddTaskResult? _parseInput(String raw) {
  if (raw.startsWith('magnet:')) {
    final m = MagnetParser.tryParse(raw);
    if (m == null) return null;
    return AddTaskResult.magnet(m.infoHash, m.displayName, inputRaw: raw);
  }
  if (raw.startsWith('urn:btih:')) {
    final m = MagnetParser.tryParse('magnet:?xt=$raw');
    if (m != null) return AddTaskResult.magnet(m.infoHash, m.displayName, inputRaw: raw);
  }
  final f = File(raw);
  if (f.existsSync()) {
    final bytes = f.readAsBytesSync();
    final t = TorrentParser.parse(Uint8List.fromList(bytes));
    return AddTaskResult.torrent(t, inputRaw: raw);
  }
  return null;
}
