import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:treehole/services/api.dart';
import 'package:treehole/models/upload_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    ApiService.debugHttpClient = http.Client();
  });
  test(
    'reply retry reuses request key and changing content allocates a new key',
    () async {
      final keys = <String?>[];
      ApiService.debugHttpClient = MockClient((request) async {
        keys.add(request.headers['x-publish-id']);
        return http.Response(
          '{"message":"blocked","code":"CONTENT_REJECTED"}',
          403,
        );
      });
      for (final text in ['first', 'first', 'edited']) {
        await ApiService.createComment(
          postId: 1,
          content: text,
          sessionId: 7,
          sessionSecret: 'secret',
        );
      }
      expect(keys[0], isNotNull);
      expect(keys[0], keys[1]);
      expect(keys[2], isNot(keys[0]));
    },
  );
  test(
    'upload authenticates with headers and surfaces the account ban message',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'session_id': '7',
        'session_secret': 'secret',
      });
      final dir = await Directory.systemTemp.createTemp('publication_safety');
      try {
        final file = await File(
          '${dir.path}/image.jpg',
        ).writeAsBytes([1, 2, 3]);
        ApiService.debugHttpClient = MockClient((request) async {
          expect(request.headers['x-session-id'], '7');
          expect(request.headers['x-session-secret'], 'secret');
          expect(request.headers['x-publish-id'], isNotEmpty);
          return http.Response(
            '{"message":"account banned","code":"ACCOUNT_BANNED"}',
            403,
          );
        });
        expect(await ApiService.uploadFile(PostUploadType.image, file), isNull);
        expect(ApiService.lastError, 'account banned');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
