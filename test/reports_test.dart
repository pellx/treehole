import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:treehole/models/post.dart';
import 'package:treehole/models/comment.dart';
import 'package:treehole/services/api.dart';
import 'package:treehole/services/storage.dart';
import 'package:treehole/theme/app_colors.dart';
import 'package:treehole/widgets/post_card.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('treehole_reports_test');
    Hive.init(directory.path);
    await PostStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test(
    'post tombstone deletes content, child replies and saved IDs, and survives reopen',
    () async {
      const post = Post(
        id: 100,
        title: 'hidden',
        content: 'private text',
        comments: [200],
      );
      const comment = Comment(id: 200, postId: 100, content: 'private reply');
      await PostStorage.savePost(post);
      await PostStorage.saveComment(comment);
      await PostStorage.saveIdList([100]);
      ApiService.debugHttpClient = MockClient(
        (_) async => http.Response('{"id":100,"hidden":true}', 200),
      );
      expect(await ApiService.getPostV2(100), isNull);
      expect(PostStorage.getPost(100), isNull);
      expect(PostStorage.getComment(200), isNull);
      expect(PostStorage.getIdList(), isEmpty);
      await PostStorage.savePost(post);
      await PostStorage.saveComment(comment);
      expect(PostStorage.getCachedIds(), isNot(contains(100)));
      expect(PostStorage.getCachedCommentIds(), isNot(contains(200)));
      await Hive.close();
      await PostStorage.init();
      expect(PostStorage.isPostHidden(100), isTrue);
      expect(PostStorage.getPost(100), isNull);
    },
  );
  test(
    'a visible GET that arrives after a tombstone cannot restore the post',
    () async {
      final pending = Completer<http.Response>();
      ApiService.debugHttpClient = MockClient((_) => pending.future);
      final request = ApiService.getPostV2(101);
      await Future<void>.delayed(Duration.zero);
      await PostStorage.applyHidden(posts: [101]);
      pending.complete(http.Response('{"id":101,"title":"stale secret"}', 200));
      expect(await request, isNull);
    },
  );
  test(
    'comment tombstone removes only that reply and prunes its cached parent references',
    () async {
      await PostStorage.savePost(
        const Post(id: 102, title: 'keep', comments: [202, 203]),
      );
      await PostStorage.saveComment(
        const Comment(id: 202, postId: 102, content: 'remove'),
      );
      await PostStorage.saveComment(
        const Comment(id: 203, postId: 102, content: 'keep'),
      );
      ApiService.debugHttpClient = MockClient(
        (_) async =>
            http.Response('{"id":202,"post_id":102,"hidden":true}', 200),
      );
      expect(await ApiService.getComment(202), isNull);
      expect(PostStorage.getComment(202), isNull);
      expect(PostStorage.getComment(203), isNotNull);
      expect(PostStorage.getPost(102)!.comments, [203]);
    },
  );
  test('network errors do not delete cached content', () async {
    await PostStorage.savePost(const Post(id: 104, title: 'offline cache'));
    ApiService.debugHttpClient = MockClient(
      (_) async => http.Response('unavailable', 503),
    );
    expect(await ApiService.getPostV2(104), isNull);
    expect(PostStorage.getPost(104), isNotNull);
    expect(PostStorage.isPostHidden(104), isFalse);
  });
  test(
    'metadata refresh also checks cached visibility even when hidden items are absent from lists',
    () async {
      await PostStorage.savePost(const Post(id: 105, title: 'old cache'));
      final paths = <String>[];
      ApiService.debugHttpClient = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/visibility')) {
          final body = jsonDecode(request.body);
          expect(body['post_ids'], contains(105));
          return http.Response(
            '{"hidden_posts":[105],"hidden_comments":[]}',
            200,
          );
        }
        return http.Response('{"total":0,"items":[]}', 200);
      });
      await ApiService.getIdListV2();
      expect(paths.any((p) => p.endsWith('/visibility')), isTrue);
      expect(PostStorage.getPost(105), isNull);
    },
  );
  test(
    'single post refresh purges the hidden reply IDs included in its response',
    () async {
      await PostStorage.saveComment(
        const Comment(id: 210, postId: 110, content: 'old reply'),
      );
      ApiService.debugHttpClient = MockClient(
        (_) async => http.Response(
          '{"id":110,"title":"post","comments":[],"hidden_comment_ids":[210]}',
          200,
        ),
      );
      final post = await ApiService.getPostV2(110);
      expect(post, isNotNull);
      expect(PostStorage.getComment(210), isNull);
      expect(PostStorage.isCommentHidden(210), isTrue);
    },
  );
  test(
    'report POST carries session headers and consumes a hidden response',
    () async {
      ApiService.debugHttpClient = MockClient((request) async {
        expect(request.url.path.endsWith('/reports'), isTrue);
        expect(request.headers['x-session-id'], '12');
        expect(request.headers['x-session-secret'], 'test-secret');
        expect(jsonDecode(request.body), {
          'target_type': 'comment',
          'target_id': 220,
          'reason': 'spam',
        });
        return http.Response(
          '{"duplicate":false,"hidden":true,"post_id":120}',
          200,
        );
      });
      await ApiService.reportContent(
        type: 'comment',
        id: 220,
        reason: 'spam',
        sessionId: 12,
        sessionSecret: 'test-secret',
      );
      expect(PostStorage.isCommentHidden(220), isTrue);
    },
  );
  testWidgets('reply long press opens copy, report and favorite actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: PostCard(
              post: Post(id: 300, title: 'test post'),
              comments: [
                Comment(id: 301, postId: 300, content: 'long press this reply'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('long press this reply'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('举报'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('收藏功能即将上线'), findsOneWidget);
    await tester.runAsync(() => PostStorage.applyHidden(posts: [300]));
    await tester.pumpAndSettle();
    expect(find.text('test post'), findsNothing);
    expect(find.text('long press this reply'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
