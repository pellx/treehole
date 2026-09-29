import 'package:treehole/services/dm_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/pages/messages/messages_page.dart';
import 'package:treehole/theme/app_colors.dart';
import 'package:treehole/theme/app_messages_theme.dart';
import 'package:treehole/widgets/app_app_bar.dart';

void main() {
  tearDown(() {
    DmNotifications.debugPermissionStatus = null;
    DmNotifications.debugOpenSettings = null;
  });
  testWidgets(
    'notification bell opens system settings and refreshes its checked state',
    (tester) async {
      var enabled = false;
      var opens = 0;
      DmNotifications.debugPermissionStatus = () async => enabled;
      DmNotifications.debugOpenSettings = () async {
        opens++;
        enabled = true;
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const MessagesPage(active: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      await tester.tap(find.byTooltip('开启消息通知'));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(find.byTooltip('消息通知已开启，打开系统设置'), findsOneWidget);
      expect(find.byIcon(Icons.notifications), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    },
  );
  testWidgets(
    'messages root has only title, clear unread and reply-style actions sheet',
    (tester) async {
      DmNotifications.debugPermissionStatus = () async => false;
      DmNotifications.debugOpenSettings = () async {};
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const MessagesPage(active: false),
        ),
      );
      expect(find.text('消息'), findsOneWidget);
      final header = tester.widget<AppAppBar>(find.byType(AppAppBar));
      expect(header.backgroundColor, AppMessagesTheme.headerBackgroundLight);
      expect(header.height, AppMessagesTheme.headerHeight);
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      expect(find.byIcon(Icons.cleaning_services_outlined), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byTooltip('一键清理未读'), findsOneWidget);
      expect(find.byTooltip('更多消息操作'), findsOneWidget);
      expect(find.byTooltip('开启消息通知'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
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
      expect(find.text('通知权限'), findsNothing);
    },
  );
}
