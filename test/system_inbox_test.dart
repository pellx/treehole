import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/pages/messages/system_inbox_page.dart';
import 'package:treehole/services/dm_api.dart';
import 'package:treehole/theme/app_colors.dart';

class InboxFake implements DmApi {
  final reads = <String>[];
  @override
  int get sessionId => 12;
  @override
  Future<Map<String, dynamic>> systemRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (body != null) {
      reads.add(path);
      return {'success': true};
    }
    return {
      'items': [
        {
          'id': 8,
          'title': '审核结果通知',
          'content': '提交的帖子未能发布：测试原因',
          'is_read': reads.isNotEmpty,
          'created_at': '2026-09-28T00:00:00Z',
        },
      ],
      'next_before_id': null,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('system list remains unread until a message is opened', (
    tester,
  ) async {
    final api = InboxFake();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: SystemInboxPage(api: api, category: 'moderation', title: '审核与举报'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.reads, isEmpty);
    expect(find.text('审核结果通知'), findsOneWidget);
    await tester.tap(find.text('审核结果通知'));
    await tester.pumpAndSettle();
    expect(api.reads, ['8/read']);
    expect(find.byType(SelectableText), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });
}
