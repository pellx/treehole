import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:treehole/models/api_results.dart';
import 'package:treehole/services/api.dart';

void main() {
  late Directory temporary;
  late File file;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('avatar-api-');
    file = await File(
      '${temporary.path}/avatar.png',
    ).writeAsBytes([137, 80, 78, 71]);
  });
  tearDown(() async {
    ApiService.debugHttpClient = http.Client();
    ApiService.lastError = null;
    await temporary.delete(recursive: true);
  });

  test(
    'sends multipart avatar with session headers and reads approved URL',
    () async {
      ApiService.debugHttpClient = MockClient((request) async {
        expect(request.url.path, '/node/user/avatar');
        expect(request.headers['x-session-id'], '7');
        expect(request.headers['x-session-secret'], 'secret');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        expect(String.fromCharCodes(request.bodyBytes), contains('name="file"'));
        return http.Response(
          '{"avatar_url":"https://example.com/user-icon/approved.webp"}',
          200,
        );
      });
      expect(
        await ApiService.uploadAvatar(
          file,
          sessionId: 7,
          sessionSecret: 'secret',
        ),
        'https://example.com/user-icon/approved.webp',
      );
    },
  );

  test('does not return an avatar URL when review rejects the image', () async {
    ApiService.debugHttpClient = MockClient(
      (_) async => http.Response('{"message":"moderation rejected"}', 400),
    );
    expect(
      await ApiService.uploadAvatar(
        file,
        sessionId: 7,
        sessionSecret: 'secret',
      ),
      isNull,
    );
    expect(ApiService.lastError, 'moderation rejected');
  });

  test(
    'profile parses the approved URL and supports accounts without avatars',
    () {
      expect(
        UserProfileResult.fromJson({'user_display_id': 'test'}).avatarUrl,
        isNull,
      );
      expect(
        UserProfileResult.fromJson({
          'user_display_id': 'test',
          'avatar_url': 'https://example.com/user-icon/a.webp',
        }).avatarUrl,
        'https://example.com/user-icon/a.webp',
      );
    },
  );
}
