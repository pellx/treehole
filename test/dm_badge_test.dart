import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/widgets/app_bottom_nav.dart';
import 'package:treehole/theme/app_colors.dart';
import 'package:treehole/theme/app_bottom_nav_theme.dart';

void main() {
  testWidgets('message badge shows count and caps the label at 99+', (
    tester,
  ) async {
    Future<void> show(int count, {bool hasUnread = false}) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: 0,
            onTap: (_) {},
            onPublishTap: () {},
            labels: const ['广场', '收藏', '消息', '我的'],
            unreadCount: count,
            hasUnread: hasUnread,
          ),
        ),
      ),
    );
    await show(12);
    expect(find.text('12'), findsOneWidget);
    await show(105);
    expect(find.text('99+'), findsOneWidget);
    await show(0, hasUnread: true);
    final dot = tester
        .widgetList<Badge>(find.byType(Badge))
        .where((b) => b.isLabelVisible)
        .single;
    expect(dot.label, isA<SizedBox>());
    expect(dot.largeSize, AppBottomNavTheme.messageBadgeDotSize);
    await show(7, hasUnread: true);
    expect(find.text('7'), findsOneWidget);
    await show(0);
    expect(
      tester
          .widgetList<Badge>(find.byType(Badge))
          .every((b) => !b.isLabelVisible),
      isTrue,
    );
  });
}
