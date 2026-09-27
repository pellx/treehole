import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/pages/messages/messages_page.dart';
import 'package:treehole/theme/app_colors.dart';

void main() {
  testWidgets(
    'messages root has only title, clear unread and reply-style actions sheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const MessagesPage(active: false),
        ),
      );
      expect(find.text('消息'), findsOneWidget);
      expect(find.byTooltip('一键清理未读'), findsOneWidget);
      expect(find.byTooltip('更多消息操作'), findsOneWidget);
      // Disabled IconButtons use a dim color; both must stay enabled even before session hydration.
      for (final tooltip in ['一键清理未读', '更多消息操作']) {
        final button = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.onPressed, isNotNull);
      }

      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.byIcon(Icons.arrow_back_ios), findsNothing);
      await tester.tap(find.byTooltip('更多消息操作'));
      await tester.pumpAndSettle();
      expect(find.text('发起私信'), findsOneWidget);
      expect(find.text('刷新消息'), findsOneWidget);
      expect(find.text('通知权限'), findsOneWidget);
    },
  );
}
