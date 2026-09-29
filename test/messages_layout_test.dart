import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/pages/messages/messages_page.dart';
import 'package:treehole/services/dm_api.dart';
import 'package:treehole/services/dm_notifications.dart';
import 'package:treehole/theme/app_colors.dart';
import 'package:treehole/theme/app_messages_theme.dart';
import 'package:treehole/widgets/app_app_bar.dart';
import 'package:treehole/widgets/dm_conversation_tile.dart';
import 'package:treehole/widgets/message_inbox_shortcuts.dart';
import 'package:treehole/widgets/user_avatar.dart';

class _LayoutApi implements DmApi {
  @override
  int get sessionId => 12;
  @override
  String get accountToken => 'layout-test';

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async => {
    'user_id': 1,
    'items': [
      for (var i = 0; i < 3; i++)
        {
          'id': i + 1,
          'peer_user_id': i + 2,
          'last_seq': 5,
          'updated_at': DateTime.now()
              .toUtc()
              .subtract(Duration(minutes: 12 + i))
              .toIso8601String(),
          'peer': {
            'user_display_id': i == 0
                ? '林同学'
                : i == 1
                ? '一个很长很长的用户昵称用于验证单行截断'
                : '同桌',
            'avatar_url': null,
          },
          'last_message': {
            'content': i == 0
                ? '可以的，我们明天再聊。'
                : i == 1
                ? '这是一条很长的消息，用来确认小屏幕上摘要不会挤占时间和未读标记。'
                : '好的，已经收到。',
            'created_at': DateTime.now()
                .toUtc()
                .subtract(Duration(minutes: 12 + i))
                .toIso8601String(),
          },
          'unread_count': i == 1
              ? 37
              : i == 0
              ? 5
              : 0,
          'muted': i == 1,
          'pinned': i == 0,
        },
    ],
    'next_before_id': null,
  };

  @override
  Future<Map<String, dynamic>> systemRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async => {
    'counts': {'reply': 2, 'announcement': 0, 'moderation': 1},
  };

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() {
    DmNotifications.debugPermissionStatus = null;
  });

  for (final dark in [false, true]) {
    testWidgets(
      'message layout fits a narrow screen with large text (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        DmNotifications.debugPermissionStatus = () async => false;

        await tester.pumpWidget(
          MaterialApp(
            theme: (dark ? ThemeData.dark() : ThemeData.light()).copyWith(
              extensions: [dark ? AppColors.dark : AppColors.light],
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: MessagesPage(api: _LayoutApi()),
          ),
        );
        expect(find.text('还没有私信会话'), findsNothing);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final header = tester.widget<AppAppBar>(find.byType(AppAppBar));
        expect(
          header.backgroundColor,
          dark
              ? AppMessagesTheme.headerBackgroundDark
              : AppMessagesTheme.headerBackgroundLight,
        );
        expect(find.byType(MessageInboxShortcuts), findsOneWidget);
        expect(find.byType(DmConversationTile), findsNWidgets(3));
        final shortcutBottom = tester
            .getRect(find.byType(MessageInboxShortcuts))
            .bottom;
        final avatarTop = tester.getRect(find.byType(UserAvatar).first).top;
        expect(avatarTop - shortcutBottom, lessThanOrEqualTo(4));
        final reply = tester.getCenter(find.text('回复'));
        final announcement = tester.getCenter(find.text('公告'));
        final moderation = tester.getCenter(find.text('审核'));
        expect(reply.dx, lessThan(announcement.dx));
        expect(announcement.dx, lessThan(moderation.dx));
        expect(find.text('林同学'), findsOneWidget);
        expect(find.text('可以的，我们明天再聊。'), findsOneWidget);
        const longPreview = '这是一条很长的消息，用来确认小屏幕上摘要不会挤占时间和未读标记。';
        final preview = tester.widget<Text>(find.text(longPreview));
        expect(preview.maxLines, 1);
        expect(preview.softWrap, false);
        expect(preview.overflow, TextOverflow.ellipsis);
        expect(
          tester.getSize(find.text(longPreview)).width,
          lessThanOrEqualTo(AppMessagesTheme.conversationPreviewMaxWidth),
        );
        expect(find.text('37'), findsNothing);
        expect(
          tester.getRect(find.text('5')).right,
          greaterThan(
            tester.getRect(find.byType(DmConversationTile).first).right - 36,
          ),
        );
        expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
        expect(find.byIcon(Icons.push_pin), findsOneWidget);
        expect(find.text('消息加载中'), findsNothing);
        expect(find.text('正在获取私信'), findsNothing);
      },
    );
  }

  testWidgets('short labels open the existing full inbox titles', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: MessageInboxShortcuts(
            counts: const {},
            showUnread: false,
            onOpen: (category, title) => opened.add('$category:$title'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('回复'));
    await tester.tap(find.text('审核'));
    expect(opened, ['reply:帖子回复', 'moderation:审核与举报']);
  });

  testWidgets('a conversation never falls back to a message count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const Scaffold(
          body: DmConversationTile(
            conversation: {
              'peer_user_id': 2,
              'peer': {'user_display_id': '对方'},
              'last_seq': 5,
              'unread_count': 0,
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('共 5 条消息'), findsNothing);
  });

  testWidgets('render message page at a normal phone size', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DmNotifications.debugPermissionStatus = () async => true;
    const fontPath = String.fromEnvironment('MESSAGE_LAYOUT_FONT');
    if (fontPath.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('LayoutPreview')
          ..addFont(
            Future.value(
              ByteData.sublistView(await File(fontPath).readAsBytes()),
            ),
          );
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: fontPath.isEmpty ? null : 'LayoutPreview',
          extensions: const [AppColors.dark],
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: MessagesPage(api: _LayoutApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_MESSAGE_LAYOUT')) {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        await Directory('build/message-layout').create(recursive: true);
        await File(
          'build/message-layout/messages-dark.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
