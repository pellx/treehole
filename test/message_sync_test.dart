import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:treehole/services/message_cache.dart';
import 'package:treehole/services/message_sync.dart';

void main() {
  late Directory dir;
  late Box<String> box;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('message_sync_test');
    Hive.init(dir.path);
    box = await Hive.openBox<String>('messages');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  setUp(() async {
    await box.clear();
  });
  Map<String, dynamic> row(int seq) => {
    'id': seq,
    'seq': seq,
    'created_at': '2026-09-28T00:00:00.000Z',
    'content': 'message $seq',
  };

  test(
    'same-time incremental pages merge without repeats, keep older cursor, and survive reopening',
    () async {
      final cache = MessageCache(box, 'account-a');
      var calls = 0;
      final sync = MessageSync(cache, (namespace, path, {body}) async {
        calls++;
        final query = Uri.parse(path).queryParameters;
        if (calls == 1) {
          return {
            'user_id': 1,
            'items': [row(2)],
            'next_before_seq': 2,
          };
        }
        expect(query['after_time'], '2026-09-28T00:00:00.000Z');
        if (calls == 2) {
          expect(query['after_seq'], '2');
          return {
            'user_id': 1,
            'items': [row(3), row(4)],
            'has_more': true,
          };
        }
        expect(query['after_seq'], '4');
        return {
          'user_id': 1,
          'items': [row(5)],
          'has_more': false,
        };
      });
      await sync.load('dm', 'conversations/8/messages');
      final result = await sync.load('dm', 'conversations/8/messages');
      expect((result['items'] as List).map((r) => r['seq']), [5, 4, 3, 2]);
      expect(result['next_before_seq'], 2);
      await box.close();
      box = await Hive.openBox<String>('messages');
      expect(
        MessageCache(
          box,
          'account-a',
        ).read('dm/conversations/8/messages')!['_after'],
        5,
      );
      expect(
        MessageCache(box, 'account-b').read('dm/conversations/8/messages'),
        isNull,
      );
    },
  );
  test(
    'a local send does not skip unseen incoming messages or advance the sync cursor',
    () async {
      final cache = MessageCache(box, 'a');
      final sync = MessageSync(cache, (_, path, {body}) async {
        final after = Uri.parse(path).queryParameters['after_seq'];
        if (after == null) {
          return {
            'items': [row(2)],
            'next_before_seq': null,
          };
        }
        expect(after, '2');
        return {
          'items': [row(3), row(4)],
          'has_more': false,
        };
      });
      await sync.load('dm', 'conversations/8/messages');
      await sync.recordSent('conversations/8/messages', row(4));
      final result = await sync.load('dm', 'conversations/8/messages');
      expect((result['items'] as List).map((r) => r['seq']), [4, 3, 2]);
    },
  );
  test('network failure retains cached body and confirmed cursor', () async {
    final cache = MessageCache(box, 'a');
    await cache.write('dm/conversations/8/messages', {
      'items': [row(2)],
      '_after': 2,
      '_after_time': row(2)['created_at'],
    });
    final sync = MessageSync(
      cache,
      (_, __, {body}) async => throw Exception('offline'),
    );
    await expectLater(
      sync.load('dm', 'conversations/8/messages'),
      throwsException,
    );
    expect(cache.read('dm/conversations/8/messages')!['_after'], 2);
    expect(
      (cache.read('dm/conversations/8/messages')!['items'] as List).length,
      1,
    );
  });
  test(
    'system metadata checks replace redacted/read old messages without refetching unchanged content',
    () async {
      final cache = MessageCache(box, 'a');
      var initial = true;
      var stateCalls = 0;
      final sync = MessageSync(cache, (_, path, {body}) async {
        if (path == 'state') {
          stateCalls++;
          expect(body!['known'], [
            {'id': 1, 'hash': List.filled(64, 'a').join()},
          ]);
          return {
            'items': [
              {
                'id': 1,
                'created_at': row(1)['created_at'],
                'content': '关联内容已隐藏',
                'is_read': true,
                'sync_hash': List.filled(64, 'b').join(),
              },
            ],
            'removed_ids': [],
          };
        }
        if (initial) {
          initial = false;
          return {
            'items': [
              {
                'id': 1,
                'created_at': row(1)['created_at'],
                'content': 'original',
                'is_read': false,
                'sync_hash': List.filled(64, 'a').join(),
              },
            ],
            'next_before_id': null,
          };
        }
        expect(Uri.parse(path).queryParameters['after_id'], '1');
        return {'items': [], 'has_more': false};
      });
      await sync.load('system', '?category=reply');
      final result = await sync.load('system', '?category=reply');
      expect(stateCalls, 1);
      expect((result['items'] as List).single['content'], '关联内容已隐藏');
      expect((result['items'] as List).single['is_read'], true);
    },
  );
  test(
    'paging older content does not move the latest incremental cursor backwards',
    () async {
      final cache = MessageCache(box, 'a');
      final sync = MessageSync(cache, (_, path, {body}) async {
        if (Uri.parse(path).queryParameters['before_seq'] != null) {
          return {
            'items': [row(1)],
            'next_before_seq': null,
          };
        }
        return {
          'items': [row(3), row(2)],
          'next_before_seq': 2,
        };
      });
      await sync.load('dm', 'conversations/8/messages');
      final result = await sync.load(
        'dm',
        'conversations/8/messages?before_seq=2',
      );
      expect(result['_after'], 3);
      expect((result['items'] as List).map((r) => r['seq']), [3, 2, 1]);
      expect(result['next_before_seq'], isNull);
    },
  );
}
