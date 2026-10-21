import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/pages/messages/messages_page.dart';
import 'package:treehole/services/dm_mock_data.dart';
import 'package:treehole/theme/app_colors.dart';

void main() {
  setUp(() {
    DmMockData.instance.enable();
    DmMockData.instance.reset();
  });

  testWidgets('测试模式下消息页直接显示假会话，不发网络请求', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const MessagesPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('林夕'), findsOneWidget);
    expect(find.text('苏晚'), findsOneWidget);
    // 首页的「请求」标签（待接受会话）。
    expect(find.text('请求'), findsWidgets);
  });
}
