import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/widgets/app_toast.dart';

void main() {
  testWidgets(
    'small feedback stays below content, replaces old toast, and closes safely',
    (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return const Center(child: Text('页面内容'));
              },
            ),
          ),
        ),
      );
      final before = tester.getRect(find.text('页面内容'));
      final dismissProgress = showAppToast(
        pageContext,
        message: '正在上传并审核…',
        duration: const Duration(seconds: 90),
      );
      await tester.pump();
      expect(tester.getRect(find.text('页面内容')), before);
      expect(
        tester.getCenter(find.text('正在上传并审核…')).dy,
        greaterThan(before.center.dy),
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      showAppToast(pageContext, message: '已刷新该帖子');
      await tester.pump();
      expect(find.text('正在上传并审核…'), findsNothing);
      expect(find.text('已刷新该帖子'), findsOneWidget);
      dismissProgress(); // An older request completing must not hide the newer toast.
      await tester.pump();
      expect(find.text('已刷新该帖子'), findsOneWidget);
      expect(tester.getRect(find.text('页面内容')), before);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('已刷新该帖子'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
