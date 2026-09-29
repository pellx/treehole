import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:treehole/services/api.dart';
import 'package:treehole/services/startup_posts.dart';
import 'package:treehole/services/storage.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('treehole_startup_posts');
    Hive.init(directory.path);
    await PostStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'the first list and its posts are fetched before Square consumes them',
    () async {
      var listCalls = 0;
      var postCalls = 0;
      ApiService.debugHttpClient = MockClient((request) async {
        if (request.url.path.endsWith('/idListv2')) {
          listCalls++;
          return http.Response(
            '{"total":1,"items":[{"id":321,"update_at":"2026-09-30T00:00:00Z"}]}',
            200,
          );
        }
        if (request.url.path.endsWith('/v2/321')) {
          postCalls++;
          return http.Response('{"id":321,"title":"prefetched post"}', 200);
        }
        throw StateError('Unexpected request: ${request.url}');
      });

      StartupPosts.start();
      final list = await StartupPosts.takeList();
      final post = await StartupPosts.takePost(321);

      expect(list!.items.single.id, 321);
      expect(post!.title, 'prefetched post');
      expect(listCalls, 1);
      expect(postCalls, 1);
      expect(StartupPosts.takeList(), isNull);
      expect(StartupPosts.takePost(321), isNull);
    },
  );

  test('a ready first batch is used on the first frame', () async {
    var listCalls = 0;
    var postCalls = 0;
    ApiService.debugHttpClient = MockClient((request) async {
      if (request.url.path.endsWith('/visibility')) {
        return http.Response('{"hidden_posts":[],"hidden_comments":[]}', 200);
      }
      if (request.url.path.endsWith('/idListv2')) {
        listCalls++;
        return http.Response(
          '{"total":1,"items":[{"id":322,"update_at":"2026-09-30T00:00:00Z"}]}',
          200,
        );
      }
      if (request.url.path.endsWith('/v2/322')) {
        postCalls++;
        return http.Response('{"id":322,"title":"ready"}', 200);
      }
      throw StateError('Unexpected request: ${request.url}');
    });

    StartupPosts.start();
    StartupPostSnapshot? snapshot;
    for (var i = 0; i < 100 && snapshot == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      snapshot = StartupPosts.takeReadySnapshot();
    }
    expect(snapshot?.posts.single.title, 'ready');
    expect(snapshot?.list.items.single.id, 322);
    expect(StartupPosts.takeList(), isNull);
    expect(listCalls, 1);
    expect(postCalls, 1);
  });
}
