/// 全局应用状态
library app_state;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/bittorrent/download_session.dart';
import '../../models/torrent_info.dart';
import '../../features/add_task/add_task_dialog.dart';

class DownloadItem {
  final DownloadSession session;
  DownloadStats stats;
  DownloadItem(this.session, this.stats);
}

/// 单一 Peer ID（每次启动随机生成；生产应持久化）
String _generatePeerId() {
  final rng = Random();
  const prefix = '-BS0001-'; // BT Safe client
  final suffix = List.generate(12, (_) {
    final c = rng.nextInt(36);
    return c < 10 ? (0x30 + c) : (0x61 + c - 10);
  });
  return prefix + String.fromCharCodes(suffix);
}

class AppState {
  final List<DownloadItem> items = [];
  final String peerId = _generatePeerId();
  final int listenPort = 6881;
  late final Directory downloadRoot;

  AppState() {
    downloadRoot = Directory(p.join(
      Directory.systemTemp.path,
      'bt_safe_downloads',
    ));
    if (!downloadRoot.existsSync()) {
      downloadRoot.createSync(recursive: true);
    }
  }

  Future<void> addFromResult(AddTaskResult r) async {
    if (r.torrent != null) {
      await _addTorrent(r.torrent!);
    } else if (r.magnetInfoHash != null) {
      // 磁力链：我们这里简化提示用户需要 .torrent（DHT 拉取元数据未实现）
      throw UnsupportedError('磁力链支持需要 DHT 元数据拉取（BEP-9），当前实现暂未提供。请使用 .torrent 文件。');
    }
  }

  Future<void> _addTorrent(TorrentInfo torrent) async {
    final subDir = Directory(p.join(downloadRoot.path, torrent.name ?? 'task_${DateTime.now().millisecondsSinceEpoch}'));
    if (!subDir.existsSync()) subDir.createSync(recursive: true);
    final session = DownloadSession(
      torrent: torrent,
      displayName: torrent.name,
      saveDir: subDir,
      peerId: peerId,
      listenPort: listenPort,
    );
    final item = DownloadItem(session, DownloadStats(downloaded: 0, uploaded: 0, totalLength: torrent.totalLength, progress: 0, peers: 0));
    items.add(item);
    await session.start();
    session.startScheduler();
    session.statsStream.listen((s) {
      item.stats = s;
    });
  }

  void pause(DownloadItem item) {
    item.session.pause();
  }

  void resume(DownloadItem item) {
    item.session.start();
    item.session.startScheduler();
  }

  void remove(DownloadItem item) {
    item.session.pause();
    items.remove(item);
  }
}

final appStateProvider = Provider<AppState>((ref) => AppState());
final downloadsProvider = StateNotifierProvider<DownloadsNotifier, List<DownloadItem>>(
  (ref) => DownloadsNotifier(ref.read(appStateProvider)),
);

class DownloadsNotifier extends StateNotifier<List<DownloadItem>> {
  final AppState _app;
  DownloadsNotifier(this._app) : super(_app.items);

  Future<void> addFromResult(AddTaskResult r) async {
    await _app.addFromResult(r);
    state = List.from(_app.items);
  }

  void pause(int idx) {
    if (idx < 0 || idx >= state.length) return;
    _app.pause(state[idx]);
    state = List.from(state);
  }

  void resume(int idx) {
    if (idx < 0 || idx >= state.length) return;
    _app.resume(state[idx]);
    state = List.from(state);
  }

  void remove(int idx) {
    if (idx < 0 || idx >= state.length) return;
    _app.remove(state[idx]);
    state = List.from(state);
  }

  void refresh(int idx) {
    if (idx < 0 || idx >= state.length) return;
    final s = state[idx].session;
    state[idx].stats = DownloadStats(
      downloaded: s.downloaded,
      uploaded: s.uploaded,
      totalLength: s.totalLength,
      progress: s.progress,
      peers: state[idx].stats.peers,
    );
    state = List.from(state);
  }
}
