import 'dart:io';
import 'dart:typed_data';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../models/version_info.dart';
import '../services/api.dart';

class PostStorage {
  static const _idListKey = 'id_list';
  static late Box _idBox;
  static late Box _postBox;
  static late Box _thumbBox;
  static late Box _commentBox;
  static late Box _customColorsBox;
  static late Box _versionBox;
  static late Box _accountBox;
  static late Box _searchHistoryBox;
  static late Box _draftBox;

  static Future<void> init() async {
    // 并行打开各 box，缩短首帧前阻塞
    await Future.wait([
      Hive.openBox('id_list').then((b) => _idBox = b),
      Hive.openBox('posts').then((b) => _postBox = b),
      Hive.openBox('thumbnails').then((b) => _thumbBox = b),
      Hive.openBox('comments').then((b) => _commentBox = b),
      Hive.openBox('custom_colors').then((b) => _customColorsBox = b),
      Hive.openBox('versions').then((b) => _versionBox = b),
      Hive.openBox('account').then((b) => _accountBox = b),
      Hive.openBox('search_history').then((b) => _searchHistoryBox = b),
      Hive.openBox('post_draft').then((b) => _draftBox = b),
    ]);
  }

  // ---- 发帖页本地暂存草稿 ----

  static Map? getPostDraft() {
    final raw = _draftBox.get('draft');
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  static Future<void> savePostDraft(Map<String, dynamic> draft) {
    return _draftBox.put('draft', draft);
  }

  static Future<void> clearPostDraft() {
    return _draftBox.delete('draft');
  }

  // ---- 账号 ----
  // 设备凭证、用户凭证、会话凭证已迁移到 DeviceCredentialStore (安全存储)
  // 此处仅保留非敏感的 UI 状态

  static String? getDisplayName() {
    return _accountBox.get('display_name') as String?;
  }

  static Future<void> saveDisplayName(String name) async {
    await _accountBox.put('display_name', name);
  }

  static bool isRegistered() {
    return _accountBox.get('registered', defaultValue: false) as bool;
  }

  static Future<void> setRegistered(bool value) async {
    await _accountBox.put('registered', value);
  }

  static Future<void> clearAccount() async {
    await _accountBox.clear();
  }

  // ---- ID 列表 ----

  static List<int> getIdList() {
    final raw = _idBox.get(_idListKey);
    if (raw == null) return [];
    return List<int>.from(raw as List);
  }

  static Future<void> saveIdList(List<int> ids) async {
    await _idBox.put(_idListKey, ids);
  }

  static List<int> mergeAndSaveIdList(List<int> newIds) {
    final old = getIdList();
    final merged = <int>[...newIds];
    for (final id in old) {
      if (!merged.contains(id)) merged.add(id);
    }
    _idBox.put(_idListKey, merged);
    return merged;
  }

  // ---- 帖子内容 ----

  static Post? getPost(int id) {
    final raw = _postBox.get(id);
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(raw as Map);
    map.remove('fetched');
    map.remove('comments_checked_at');
    return Post.fromJson(map);
  }

  /// 评论列表本地刷新 TTL：期间内不再重复 getPost 拉全帖
  static const Duration commentRefreshTtl = Duration(minutes: 5);

  /// 记录最近一次评论列表从服务端刷新的时间
  static Future<void> setCommentsCheckedAt(int postId) async {
    final raw = _postBox.get(postId);
    if (raw == null) return;
    final map = Map<String, dynamic>.from(raw as Map);
    map['comments_checked_at'] = DateTime.now().millisecondsSinceEpoch;
    await _postBox.put(postId, map);
  }

  /// 最近一次评论刷新是否仍在 TTL 内（在则跳过重新 getPost）
  static bool commentsFresh(int postId) {
    final raw = _postBox.get(postId);
    if (raw == null) return false;
    final map = raw as Map;
    final at = map['comments_checked_at'];
    if (at is! num) return false;
    final checked = DateTime.fromMillisecondsSinceEpoch(at.toInt());
    return DateTime.now().difference(checked) < commentRefreshTtl;
  }

  static Future<void> savePost(Post post) async {
    final map = <String, dynamic>{
      'id': post.id,
      'title': post.title,
      'content': post.content,
      'author': post.author,
      'is_anonymous': post.isAnonymous,
      'created_at': post.createdAt,
      'update_at': post.updateAt,
      'images': post.images.map((e) => {'file_name': e.fileName}).toList(),
      'attachments': post.attachments
          .map((e) => {'file_name': e.fileName, 'source_name': e.sourceName})
          .toList(),
      'comments': post.comments,
      'fetched': true,
    };
    await _postBox.put(post.id, map);
  }

  static Future<void> updatePostCommentIds(int postId, List<int> newIds) async {
    final raw = _postBox.get(postId);
    if (raw == null) return;
    final map = Map<String, dynamic>.from(raw as Map);
    map['comments'] = newIds;
    await _postBox.put(postId, map);
  }

  static Future<void> markFetched(int id) async {
    final raw = _postBox.get(id);
    if (raw != null) {
      final map = Map<String, dynamic>.from(raw as Map);
      map['fetched'] = true;
      await _postBox.put(id, map);
    }
  }

  static bool isFetched(int id) {
    final raw = _postBox.get(id);
    if (raw == null) return false;
    final map = raw as Map;
    return map['fetched'] == true;
  }

  static List<int> getCachedIds() {
    return _postBox.keys.cast<int>().toList();
  }

  static List<int> getFetchedIds() {
    return _postBox.keys.cast<int>().where((id) => isFetched(id)).toList();
  }

  static List<Post> getAllCachedPosts() {
    return _postBox.keys
        .cast<int>()
        .map((id) => getPost(id)!)
        .where((p) => true)
        .toList();
  }

  static Future<void> deletePost(int id) async {
    await _postBox.delete(id);
  }

  // ---- 缩略图 ----

  static ThumbnailData? getThumbnail(String fileName) {
    final raw = _thumbBox.get('thumb_$fileName');
    if (raw == null) return null;
    if (raw is Uint8List) {
      return ThumbnailData(bytes: raw, width: 0, height: 0);
    }
    final map = raw as Map;
    return ThumbnailData(
      bytes: map['bytes'] as Uint8List,
      width: map['w'] as int,
      height: map['h'] as int,
    );
  }

  static Future<void> saveThumbnail(String fileName, ThumbnailData data) async {
    await _thumbBox.put('thumb_$fileName', {
      'bytes': data.bytes,
      'w': data.width,
      'h': data.height,
    });
  }

  // ---- PNG 原图文件缓存 ----

  static Future<Directory> _pngCacheDir() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/png_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Uint8List?> getPng(String fileName) async {
    final file = File('${(await _pngCacheDir()).path}/$fileName');
    if (await file.exists()) return await file.readAsBytes();
    return null;
  }

  static Future<void> savePng(String fileName, Uint8List bytes) async {
    final file = File('${(await _pngCacheDir()).path}/$fileName');
    await file.writeAsBytes(bytes);
  }

  // ---- 回复缓存 ----

  static Comment? getComment(int id) {
    final raw = _commentBox.get(id);
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(raw as Map);
    return Comment.fromJson(map);
  }

  static Future<void> saveComment(Comment comment) async {
    await _commentBox.put(comment.id, <String, dynamic>{
      'id': comment.id,
      'post_id': comment.postId,
      'to_id': comment.toId,
      'author': comment.author,
      'is_anonymous': comment.isAnonymous,
      'content': comment.content,
      'created_at': comment.createdAt,
    });
  }

  static List<Comment> getComments(List<int> ids) {
    return ids.map((id) => getComment(id)).whereType<Comment>().toList();
  }

  // ---- 评论草稿 ----

  static String? getCommentDraft(int postId) {
    return _commentBox.get('draft_$postId') as String?;
  }

  static Future<void> saveCommentDraft(int postId, String text) async {
    if (text.isEmpty) {
      await _commentBox.delete('draft_$postId');
    } else {
      await _commentBox.put('draft_$postId', text);
    }
  }

  static Future<void> clearCommentDraft(int postId) async {
    await _commentBox.delete('draft_$postId');
  }

  // ---- 搜索历史 ----

  static List<String> getSearchHistory() {
    final raw = _searchHistoryBox.get('queries');
    if (raw == null) return [];
    return (raw as List).cast<String>();
  }

  static Future<void> saveSearchHistory(List<String> queries) async {
    await _searchHistoryBox.put('queries', queries);
  }

  static Future<void> addSearchHistory(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final history = getSearchHistory();
    history.remove(q);
    history.insert(0, q);
    if (history.length > 20) history.removeLast();
    await saveSearchHistory(history);
  }

  static Future<void> clearSearchHistory() async {
    await _searchHistoryBox.delete('queries');
  }

  static Future<void> removeSearchHistory(String query) async {
    final history = getSearchHistory();
    history.remove(query);
    await saveSearchHistory(history);
  }

  // ---- 自定义颜色 ----

  static Map<String, int> getCustomColors() {
    final raw = _customColorsBox.get('colors');
    if (raw == null) return {};
    return Map<String, int>.from(raw as Map);
  }

  static Future<void> saveCustomColors(Map<String, int> colors) async {
    await _customColorsBox.put('colors', colors);
  }

  static Future<void> clearCustomColors() async {
    await _customColorsBox.delete('colors');
  }

  // ---- 用户名 ----

  static String getUserName() {
    final raw = _customColorsBox.get('user_name');
    if (raw == null) return '匿名用户';
    return raw as String;
  }

  static Future<void> saveUserName(String name) async {
    await _customColorsBox.put('user_name', name);
  }

  // ---- 版本历史 ----

  static List<VersionInfo> getCachedVersions() {
    final raw = _versionBox.get('list');
    if (raw == null) return [];
    final list = raw as List;
    return list
        .map((j) => VersionInfo.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  static Future<void> saveVersions(List<VersionInfo> versions) async {
    await _versionBox.put('list', versions.map((v) => v.toJson()).toList());
  }

  static VersionInfo? getLatestCachedVersion() {
    final versions = getCachedVersions();
    return versions.isNotEmpty ? versions.first : null;
  }

  static Future<void> saveLatestVersion(VersionInfo version) async {
    final existing = getCachedVersions();
    final ids = existing.map((v) => v.id).toSet();
    if (!ids.contains(version.id)) {
      existing.insert(0, version);
      await saveVersions(existing);
    }
  }
}
