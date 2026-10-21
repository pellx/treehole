import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/pages/messages/dm_mock_chat_page.dart';
import 'package:treehole/services/dm_mock_data.dart';
import 'package:treehole/theme/app_colors.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: child,
);

void main() {
  setUp(() {
    DmMockData.instance.enable();
    DmMockData.instance.reset();
  });

  testWidgets('已接受的会话显示历史消息与输入框，发送后消息出现', (tester) async {
    await tester.pumpWidget(_wrap(const DmMockChatPage(conversationId: 104)));
    await tester.pumpAndSettle();

    expect(find.text('阿哲'), findsOneWidget);
    expect(find.text('比如消息模块的边界情况，最近在补'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '自动化测试消息');
    await tester.tap(find.text('发送'));
    await tester.pump();
    expect(find.text('自动化测试消息'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('待接受的请求显示提示条与同意/拒绝，且没有输入框', (tester) async {
    await tester.pumpWidget(_wrap(const DmMockChatPage(conversationId: 101)));
    await tester.pumpAndSettle();

    expect(find.text('对方请求与你私信，接受后才能互发消息'), findsOneWidget);
    expect(find.text('同意'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('空会话显示打招呼文案', (tester) async {
    await tester.pumpWidget(_wrap(const DmMockChatPage(conversationId: 103)));
    await tester.pumpAndSettle();

    expect(find.text('还没有消息，打个招呼吧'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
