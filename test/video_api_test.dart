import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:treehole/services/video_api.dart';

void main() {
  test(
    'video API uses public reads and session headers only for sending',
    () async {
      final seen = <http.Request>[];
      http.Response jsonResponse(Object data, int status) =>
          http.Response.bytes(utf8.encode(jsonEncode(data)), status);

      VideoApi.debugHttpClient = MockClient((request) async {
        seen.add(request);
        if (request.url.path == '/node/videos') {
          return jsonResponse([
            {
              'id': 7,
              'title': '测试视频',
              'cover_url': 'https://example.test/cover.jpg',
              'playback_url': 'https://example.test/master.m3u8',
              'duration_ms': 120000,
              'qualities': [
                {
                  'label': '360p',
                  'url': 'https://example.test/360p/playlist.m3u8',
                },
              ],
            },
          ], 200);
        }
        if (request.url.path == '/node/videos/7/danmaku' &&
            request.method == 'GET') {
          return jsonResponse([
            {'id': 9, 'time_ms': 1500, 'text': '你好'},
          ], 200);
        }
        if (request.url.path == '/node/videos/7/danmaku' &&
            request.method == 'POST') {
          return jsonResponse({'id': 10, 'time_ms': 2000, 'text': '发送成功'}, 201);
        }
        return http.Response('Not found', 404);
      });

      final videos = await VideoApi.list();
      expect(videos.single.title, '测试视频');
      expect(videos.single.qualities.single.label, '360p');

      final comments = await VideoApi.danmaku(7, 0, 60000);
      expect(comments.single.timeMs, 1500);
      expect(seen[1].url.queryParameters, {'from_ms': '0', 'to_ms': '60000'});

      final sent = await VideoApi.sendDanmaku(
        7,
        2000,
        '发送成功',
        sessionId: 12,
        sessionSecret: 'secret',
      );
      expect(sent.id, 10);
      expect(seen[2].headers['x-session-id'], '12');
      expect(seen[2].headers['x-session-secret'], 'secret');
      expect(jsonDecode(seen[2].body)['time_ms'], 2000);
      expect(seen[0].headers.containsKey('x-session-secret'), isFalse);
    },
  );
}
