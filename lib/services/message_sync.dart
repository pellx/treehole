import 'message_cache.dart';

typedef MessageTransport =
    Future<Map<String, dynamic>> Function(
      String namespace,
      String path, {
      Map<String, dynamic>? body,
    });

class MessageSync {
  final MessageCache cache;
  final MessageTransport transport;
  MessageSync(this.cache, this.transport);

  static String? keyFor(String namespace, String path) {
    final uri = Uri.parse(path);
    if (namespace == 'dm' &&
        (uri.path == 'conversations' ||
            RegExp(r'^conversations/[0-9]+/messages$').hasMatch(uri.path))) {
      return 'dm/${uri.path}';
    }
    if (namespace == 'system' &&
        uri.path.isEmpty &&
        uri.queryParameters['category'] != null) {
      return 'system/${uri.queryParameters['category']}';
    }
    if (namespace == 'system' && path == 'summary') return 'system/summary';
    return null;
  }

  Future<void> recordSent(String path, Map<String, dynamic> message) async {
    final key = keyFor('dm', path)!;
    await cache.serial(key, () async {
      final saved = cache.read(key);
      if (saved == null) return;
      final rows =
          (saved['items'] as List)
              .cast<Map<String, dynamic>>()
              .where((row) => row['id'] != message['id'])
              .toList()
            ..add(message);
      rows.sort((a, b) => (b['seq'] as int).compareTo(a['seq'] as int));
      saved['items'] = rows;
      await cache.write(key, saved);
    });
  }

  Future<Map<String, dynamic>> load(String namespace, String path) async {
    final key = keyFor(namespace, path);
    if (key == null) return transport(namespace, path);
    return cache.serial(key, () async {
      if (path == 'summary') {
        final data = await transport(namespace, path);
        await cache.write(key, data);
        return data;
      }
      var saved = cache.read(key);
      final uri = Uri.parse(path);
      final older =
          uri.queryParameters.containsKey('before_id') ||
          uri.queryParameters.containsKey('before_seq');
      final chat = namespace == 'dm' && uri.path.endsWith('/messages');
      final conversations = namespace == 'dm' && !chat;
      final ordinal = chat ? 'seq' : 'id';
      final beforeKey = chat ? 'next_before_seq' : 'next_before_id';

      Map<String, dynamic> merge(
        Map<String, dynamic>? base,
        Map<String, dynamic> incoming, {
        bool page = false,
      }) {
        final all = <int, Map<String, dynamic>>{};
        for (final row in [
          ...?base?['items'] as List?,
          ...?incoming['items'] as List?,
        ]) {
          final item = Map<String, dynamic>.from(row as Map);
          all[item['id'] as int] = item;
        }
        for (final id in incoming['removed_ids'] as List? ?? []) {
          all.remove(id);
        }
        final rows = all.values.toList()
          ..sort((a, b) {
            if (conversations &&
                (a['pinned'] == true) != (b['pinned'] == true)) {
              return a['pinned'] == true ? -1 : 1;
            }
            return (b[ordinal] as int).compareTo(a[ordinal] as int);
          });
        return {
          ...?base,
          ...incoming,
          'items': rows,
          if (!page && base != null) beforeKey: base[beforeKey],
          if (!page && base != null && conversations)
            'next_before_pinned': base['next_before_pinned'],
        };
      }

      if (saved == null || older) {
        final data = await transport(namespace, path);
        final oldCursor = saved?['_after'];
        final oldTime = saved?['_after_time'];
        saved = merge(saved, data, page: true);
        if (oldCursor != null) {
          saved['_after'] = oldCursor;
          saved['_after_time'] = oldTime;
        } else {
          final rows = (saved['items'] as List).cast<Map<String, dynamic>>();
          final newest = rows.isEmpty
              ? null
              : rows.reduce(
                  (a, b) => (a[ordinal] as int) > (b[ordinal] as int) ? a : b,
                );
          saved['_after'] = newest?[ordinal] ?? 0;
          saved['_after_time'] = newest?['created_at'] ?? newest?['updated_at'];
        }
        await cache.write(key, saved);
        return saved;
      }

      // Cursor is advanced only after a server page is merged and saved.
      // A sent local message never advances it: intervening incoming messages must still be fetched.
      while (true) {
        final params = Map<String, String>.from(uri.queryParameters)
          ..remove('before_id')
          ..remove('before_seq')
          ..remove('before_pinned')
          ..[chat ? 'after_seq' : 'after_id'] = '${saved!['_after'] ?? 0}';
        if (saved['_after_time'] != null) {
          params['after_time'] = saved['_after_time'].toString();
        }
        final url = Uri(path: uri.path, queryParameters: params).toString();
        final data = await transport(namespace, url);
        final cursor = saved['_after'];
        final time = saved['_after_time'];
        saved = merge(saved, data);
        final pageRows = (data['items'] as List).cast<Map<String, dynamic>>();
        saved['_after'] = pageRows.isEmpty ? cursor : pageRows.last[ordinal];
        saved['_after_time'] = pageRows.isEmpty
            ? time
            : (pageRows.last['created_at'] ?? pageRows.last['updated_at']);
        await cache.write(key, saved);
        if (data['has_more'] != true) break;
        if (saved['_after'] == cursor) throw StateError('消息同步游标未前进');
      }

      if (!chat) {
        final known = (saved['items'] as List)
            .cast<Map<String, dynamic>>()
            .toList();
        if (conversations) {
          final pinned = await transport(namespace, 'pinned');
          final ids = known.map((row) => row['id']).toSet();
          for (final id in pinned['ids'] as List) {
            if (ids.add(id)) known.add({'id': id});
          }
        }
        for (var offset = 0; offset < known.length; offset += 200) {
          final batch = known.skip(offset).take(200);
          final data = await transport(
            namespace,
            conversations ? 'conversations/state' : 'state',
            body: {
              if (!conversations) 'category': uri.queryParameters['category'],
              'known': [
                for (final row in batch)
                  {
                    'id': row['id'],
                    'hash': row['sync_hash'] ?? List.filled(64, '0').join(),
                  },
              ],
            },
          );
          final cursor = saved!['_after'], time = saved['_after_time'];
          saved = merge(saved, data);
          saved['_after'] = cursor;
          saved['_after_time'] = time;
          await cache.write(key, saved);
        }
      }
      return saved!;
    });
  }
}
