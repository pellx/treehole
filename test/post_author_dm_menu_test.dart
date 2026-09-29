import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/models/post.dart';
import 'package:treehole/theme/app_colors.dart';
import 'package:treehole/widgets/post_card.dart';

void main() {
  testWidgets('author menu opens below the name and fits a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: ListView(
            children: const [
              PostCard(
                post: Post(id: 42, title: '标题', author: '作者'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('私信作者'));
    await tester.pumpAndSettle();
    final name = tester.getRect(find.text('作者').first);
    final menu = tester.getRect(find.text('回复').last);
    expect(menu.top, greaterThanOrEqualTo(name.bottom));
    expect(menu.left, greaterThanOrEqualTo(0));
    expect(menu.right, lessThanOrEqualTo(320));
  });
}
