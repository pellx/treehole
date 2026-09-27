import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/video_item.dart';

class VideoApi {
  static final Uri _base = Uri.parse('https://tree.leisure.xin/node/videos');
  static const _timeout = Duration(seconds: 20);
  static http.Client _client = http.Client();

  @visibleForTesting
  static set debugHttpClient(http.Client client) => _client = client;

  static Future<dynamic> _read(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('服务器返回 ${response.statusCode}');
    }
    return Future.value(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  static Future<List<VideoItem>> list() async {
    final data = await _read(await _client.get(_base).timeout(_timeout));
    return (data as List<dynamic>)
        .map((item) => VideoItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<VideoItem> detail(int id) async {
    final data = await _read(
      await _client.get(_base.resolve('videos/$id')).timeout(_timeout),
    );
    return VideoItem.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<VideoDanmaku>> danmaku(
    int id,
    int fromMs,
    int toMs,
  ) async {
    final uri = Uri.parse(
      '$_base/$id/danmaku',
    ).replace(queryParameters: {'from_ms': '$fromMs', 'to_ms': '$toMs'});
    final data = await _read(await _client.get(uri).timeout(_timeout));
    return (data as List<dynamic>)
        .map((item) => VideoDanmaku.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<VideoDanmaku> sendDanmaku(
    int id,
    int timeMs,
    String text, {
    required int sessionId,
    required String sessionSecret,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_base/$id/danmaku'),
          headers: {
            'Content-Type': 'application/json',
            'x-session-id': '$sessionId',
            'x-session-secret': sessionSecret,
          },
          body: jsonEncode({'time_ms': timeMs, 'text': text}),
        )
        .timeout(_timeout);
    return VideoDanmaku.fromJson(await _read(response) as Map<String, dynamic>);
  }
}
