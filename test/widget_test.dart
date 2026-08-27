// 简单的 smoke test：应用能跑起来不崩
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bt_safe/main.dart';

void main() {
  testWidgets('App boots', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BtSafeApp()));
    await tester.pump();
    expect(find.text('BT Safe 下载'), findsOneWidget);
  });
}
