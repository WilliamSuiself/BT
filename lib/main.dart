import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/add_task/add_task_dialog.dart';
import 'features/downloads/download_state.dart';
import 'features/settings/settings_dialog.dart';
import 'widgets/download_list_item.dart';

void main() {
  runApp(const ProviderScope(child: BtSafeApp()));
}

class BtSafeApp extends StatelessWidget {
  const BtSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BT Safe',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final list = ref.read(downloadsProvider);
      for (var i = 0; i < list.length; i++) {
        ref.read(downloadsProvider.notifier).refresh(i);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BT Safe 下载'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const SettingsDialog(),
            ),
          ),
        ],
      ),
      body: downloads.isEmpty
          ? const Center(
              child: Text('还没有任务。点击右下角"+"添加。'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: downloads.length,
              itemBuilder: (_, i) {
                final item = downloads[i];
                return DownloadListItem(
                  session: item.session,
                  stats: item.stats,
                  onPause: () => ref.read(downloadsProvider.notifier).pause(i),
                  onResume: () => ref.read(downloadsProvider.notifier).resume(i),
                  onRemove: () => ref.read(downloadsProvider.notifier).remove(i),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('添加任务'),
        onPressed: () async {
          final r = await showAddTaskDialog(context);
          if (r == null) return;
          try {
            await ref.read(downloadsProvider.notifier).addFromResult(r);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败: $e')));
            }
          }
        },
      ),
    );
  }
}
