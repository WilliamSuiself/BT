/// 下载任务列表项
library download_list_item;

import 'package:flutter/material.dart';

import '../core/bittorrent/download_session.dart';

class DownloadListItem extends StatelessWidget {
  final DownloadSession session;
  final DownloadStats stats;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onRemove;

  const DownloadListItem({
    super.key,
    required this.session,
    required this.stats,
    this.onPause,
    this.onResume,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconForStatus(session.status)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusChip(status: session.status),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: stats.progress),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(_formatBytes(stats.downloaded) + ' / ' + _formatBytes(stats.totalLength)),
                const SizedBox(width: 16),
                Text('Peers: ${stats.peers}'),
                const Spacer(),
                if (session.status == SessionStatus.running)
                  IconButton(icon: const Icon(Icons.pause), onPressed: onPause)
                else if (session.status == SessionStatus.paused)
                  IconButton(icon: const Icon(Icons.play_arrow), onPressed: onResume),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: onRemove),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForStatus(SessionStatus s) {
    switch (s) {
      case SessionStatus.added:
        return Icons.add_circle_outline;
      case SessionStatus.running:
        return Icons.downloading;
      case SessionStatus.paused:
        return Icons.pause_circle_outline;
      case SessionStatus.completed:
        return Icons.check_circle;
      case SessionStatus.error:
        return Icons.error_outline;
    }
  }

  String _formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _StatusChip extends StatelessWidget {
  final SessionStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SessionStatus.added => ('已添加', Colors.grey),
      SessionStatus.running => ('下载中', Colors.blue),
      SessionStatus.paused => ('已暂停', Colors.orange),
      SessionStatus.completed => ('完成', Colors.green),
      SessionStatus.error => ('错误', Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
