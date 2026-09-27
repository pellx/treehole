import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/pages/messages/dm_chat_page.dart';
import 'package:treehole/services/dm_api.dart';
import 'package:treehole/services/realtime_service.dart';
import 'package:treehole/theme/app_colors.dart';
import 'package:treehole/widgets/user_avatar.dart';

class FakeDmApi implements DmApi {
  final sends = <Map<String, dynamic>>[];
  bool failFirst = true;
  Completer<void>? sendGate;
  DmException? sendError;
  int lastRead = 0;
  bool muted = false;
  bool pinned = false;
  bool blocked = false;
  final history = <Map<String, dynamic>>[];
  @override
  int get sessionId => 100;
  @override
  Future<void> reconnectRealtime() async {}
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (path.endsWith('/read')) {
      lastRead = body!['last_read_seq'] as int;
      return {'success': true};
    }
    if (path.endsWith('/preferences')) {
      if (body!.containsKey('pinned')) pinned = body['pinned'] == true;
      if (body.containsKey('muted')) muted = body['muted'] == true;
      if (body.containsKey('blocked')) blocked = body['blocked'] == true;
      return {
        'pinned': pinned,
        'muted': muted,
        'blocked': blocked,
        'can_send': !blocked,
      };
    }
    if (body == null) {
      return {
        'user_id': 1,
        'last_read_seq': lastRead,
        'pinned': pinned,
        'muted': muted,
        'blocked': blocked,
        'can_send': !blocked,
        'items': List<Map<String, dynamic>>.from(history),
        'next_before_seq': null,
      };
    }
    sends.add(Map.of(body));
    if (sendGate != null) await sendGate!.future;
    if (sendError != null) throw sendError!;
    if (failFirst) {
      failFirst = false;
      throw const DmException('网络连接失败');
    }
    final result = <String, dynamic>{
      'client_message_id': body['client_message_id'],
      'id': 1,
      'seq': 1,
      'sender_id': 1,
      'content': body['content'],
      'created_at': '2026-09-28T00:00:00Z',
    };
    history.add(result);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'renders pending immediately, keeps it out of read cursors, then reconciles one approved bubble',
    (tester) async {
      final api = FakeDmApi()
        ..failFirst = false
        ..sendGate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: DmChatPage(api: api, conversationId: 8, peerId: 2, userId: 1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '即时显示');
      await tester.tap(find.text('发送'));
      await tester.pump();
      expect(find.text('即时显示'), findsOneWidget);
      expect(find.byTooltip('审核中，仅自己可见'), findsNothing);
      expect(find.byIcon(Icons.schedule), findsNothing);
      expect(api.history, isEmpty);
      expect(api.lastRead, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      RealtimeService.instance.debugDmEvent(sessionId: 100, conversationId: 8);
      api.sendGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('即时显示'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    },
  );
  testWidgets(
    'rejection stays local, failed bubble survives refresh without entering server history',
    (tester) async {
      final api = FakeDmApi()
        ..failFirst = false
        ..sendError = const DmException('审核未通过', code: 'CONTENT_REJECTED');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: DmChatPage(api: api, conversationId: 8, peerId: 2, userId: 1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '本地失败');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(api.history, isEmpty);
      expect(api.lastRead, 0);
      await tester.tap(find.byTooltip('刷新私信'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'chat settings persist mute and block and render message avatars',
    (tester) async {
      final api = FakeDmApi();
      api.history.add({
        'id': 1,
        'seq': 1,
        'sender_id': 2,
        'content': '你好',
        'created_at': '2026-09-28T00:00:00Z',
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: DmChatPage(api: api, conversationId: 8, peerId: 2, userId: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UserAvatar), findsOneWidget);
      await tester.tap(find.byTooltip('聊天设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开启消息免打扰'));
      await tester.pumpAndSettle();
      expect(api.muted, isTrue);
      await tester.tap(find.byTooltip('聊天设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('置顶聊天'));
      await tester.pumpAndSettle();
      expect(api.pinned, isTrue);
      expect(api.muted, isTrue);
      await tester.tap(find.byTooltip('聊天设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消置顶聊天'));
      await tester.pumpAndSettle();
      expect(api.pinned, isFalse);
      await tester.tap(find.byTooltip('聊天设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入黑名单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入黑名单').last);
      await tester.pumpAndSettle();
      expect(api.blocked, isTrue);
      expect(api.muted, isTrue);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '发送'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('聊天设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出黑名单'));
      await tester.pumpAndSettle();
      expect(api.blocked, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '发送'))
            .onPressed,
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );
  testWidgets(
    'push and reconnect fetch messages without a refresh tap; other sessions ignored',
    (tester) async {
      final api = FakeDmApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: DmChatPage(api: api, conversationId: 8, peerId: 2, userId: 1),
        ),
      );
      await tester.pumpAndSettle();
      api.history.add({
        'id': 2,
        'seq': 2,
        'sender_id': 2,
        'content': '实时回复',
        'created_at': '2026-09-28T00:00:00Z',
      });
      RealtimeService.instance.debugDmEvent(sessionId: 999, conversationId: 8);
      await tester.pumpAndSettle();
      expect(find.text('实时回复'), findsNothing);
      RealtimeService.instance.debugDmEvent(sessionId: 100, conversationId: 8);
      await tester.pumpAndSettle();
      expect(find.text('实时回复'), findsOneWidget);
      expect(api.lastRead, greaterThanOrEqualTo(2));
      expect(find.text('正在获取私信'), findsNothing);
      api.history.insert(0, {
        'id': 3,
        'seq': 3,
        'sender_id': 2,
        'content': '断线期间的回复',
        'created_at': '2026-09-28T00:00:00Z',
      });
      RealtimeService.instance.debugDmEvent(sessionId: 100);
      await tester.pumpAndSettle();
      expect(find.text('断线期间的回复'), findsOneWidget);
      expect(find.text('实时回复'), findsOneWidget);
      expect(api.lastRead, greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox.shrink());
      RealtimeService.instance.debugDmEvent(sessionId: 100, conversationId: 8);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed send preserves draft and UUID; retry renders one bubble',
    (tester) async {
      final api = FakeDmApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: DmChatPage(api: api, conversationId: 8, peerId: 2, userId: 1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '你好');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '你好'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(api.sends.length, 2);
      expect(
        api.sends[0]['client_message_id'],
        api.sends[1]['client_message_id'],
      );
      expect(find.text('你好'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
