import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/pages/messages/dm_chat_page.dart';
import 'package:treehole/services/dm_api.dart';
import 'package:treehole/theme/app_colors.dart';
import 'package:treehole/widgets/dm_conversation_tile.dart';

/// 只覆盖私信请求状态：pending 时禁止发送，接受后恢复输入框。
class _RequestApi implements DmApi {
  String status;
  final bool requester;
  final actions = <String>[];
  _RequestApi({required this.status, this.requester = false});

  @override
  int get sessionId => 100;

  @override
  Future<void> reconnectRealtime() async {}

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (path.endsWith('/accept')) {
      actions.add('accept');
      status = 'accepted';
      return {
        'conversation': {'id': 8, 'status': 'accepted', 'can_send': true},
      };
    }
    if (path.endsWith('/reject')) {
      actions.add('reject');
      status = 'rejected';
      return {
        'conversation': {'id': 8, 'status': 'rejected', 'can_send': false},
      };
    }
    if (path.endsWith('/read')) return {'success': true};
    return {
      'user_id': 1,
      'status': status,
      'is_requester': requester,
      'can_send': status == 'accepted',
      'last_read_seq': 0,
      'items': <Map<String, dynamic>>[],
      'next_before_seq': null,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _chat(_RequestApi api) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: DmChatPage(api: api, conversationId: 8, peerId: 2, userId: 1),
);

void main() {
  testWidgets('recipient accepts a pending request and then can type', (
    tester,
  ) async {
    final api = _RequestApi(status: 'pending');
    await tester.pumpWidget(_chat(api));
    await tester.pumpAndSettle();
    expect(find.text('对方请求与你私信，接受后才能互发消息'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();
    expect(api.actions, ['accept']);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('输入私信'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('requester waits without send controls', (tester) async {
    final api = _RequestApi(status: 'pending', requester: true);
    await tester.pumpWidget(_chat(api));
    await tester.pumpAndSettle();
    expect(find.text('已发送私信请求，等待对方接受'), findsOneWidget);
    expect(find.text('同意'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('rejected requester is told to wait for the cooldown', (
    tester,
  ) async {
    final api = _RequestApi(status: 'rejected', requester: true);
    await tester.pumpWidget(_chat(api));
    await tester.pumpAndSettle();
    expect(find.text('对方已拒绝你的私信请求，24 小时后可再次申请'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('conversation row shows request tag and accept buttons', (
    tester,
  ) async {
    var accepted = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: DmConversationTile(
            conversation: {
              'id': 8,
              'peer_user_id': 2,
              'status': 'pending',
              'is_requester': false,
              'peer': {'user_display_id': '树洞用户'},
            },
            onAccept: () => accepted++,
            onReject: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('请求'), findsOneWidget);
    expect(find.text('请求与你私信'), findsOneWidget);
    await tester.tap(find.text('同意'));
    expect(accepted, 1);
  });
}
