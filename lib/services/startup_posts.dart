import 'dart:async';

import '../models/post.dart';
import '../models/post_meta.dart';
import 'api.dart';
import 'storage.dart';

class StartupPostSnapshot {
  final IdListV2Result list;
  final List<Post> posts;
  const StartupPostSnapshot(this.list, this.posts);
}

/// Starts the first Square request while the platform launch screen is visible.
/// Square consumes these futures, so startup and page creation share one request.
class StartupPosts {
  static Future<IdListV2Result?>? _list;
  static IdListV2Result? _listResult;
  static bool _claimed = false;
  static final Map<int, Future<Post?>> _posts = {};
  static final Map<int, Post?> _resolved = {};

  static void start() {
    _listResult = null;
    _claimed = false;
    _posts.clear();
    _resolved.clear();
    _list = _fetchList();
  }

  /// Synchronous first frame when the complete first batch arrived during launch.
  static StartupPostSnapshot? takeReadySnapshot() {
    final list = _listResult;
    if (list == null) return null;
    final firstIds = list.items.take(7).map((item) => item.id).toList();
    if (firstIds.any((id) => !_resolved.containsKey(id))) return null;
    final posts = [
      for (final id in firstIds)
        if (_resolved[id] case final Post post)
          if (!PostStorage.isPostHidden(post.id)) post,
    ];
    if (posts.isEmpty) return null;
    _list = null;
    _claimed = true;
    _posts.clear();
    _resolved.clear();
    _listResult = null;
    return StartupPostSnapshot(list, posts);
  }

  static Future<IdListV2Result?>? takeList() {
    final request = _list;
    _list = null;
    _claimed = true;
    _listResult = null;
    _resolved.clear();
    return request;
  }

  static Future<Post?>? takePost(int id) => _posts.remove(id);

  static Future<IdListV2Result?> _fetchList() async {
    try {
      final result = await ApiService.getIdListV2();
      if (!_claimed) _listResult = result;
      for (final meta in result.items.take(7)) {
        _posts[meta.id] = _fetchPost(meta);
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<Post?> _fetchPost(PostMeta meta) async {
    Post? post;
    try {
      final cached = PostStorage.getPost(meta.id);
      if (cached != null &&
          cached.updateAt.isNotEmpty &&
          meta.updateAt.isNotEmpty &&
          cached.updateAt.compareTo(meta.updateAt) >= 0) {
        post = cached;
      } else {
        post = await ApiService.getPostV2(meta.id) ?? cached;
        if (post != null && post != cached) {
          await PostStorage.savePost(post);
        }
      }
    } catch (_) {}
    if (!_claimed) _resolved[meta.id] = post;
    return post;
  }
}
