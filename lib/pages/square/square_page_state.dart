part of 'square_page.dart';

mixin SquarePageStateMixin on State<SquarePage> {
  List<Post> _posts = [];
  List<int> _allIds = [];

  /// idListv2 元数据：帖子 id → 服务端 update_at，用于判断本地缓存是否过期
  Map<int, String> _updateAtById = {};

  int _loadedCount = 0;
  bool _loading = false;
  String? _error;
  final Set<int> _loadingIds = {};
  final Map<int, List<Comment>> _comments = {};
  final Set<int> _postsNeedCommentRefresh = {};

  int _selectedCategoryIndex = 0;

  double _leftPullDistance = 0;
  bool _leftPullHapticTriggered = false;
  bool _leftRefreshing = false;

  final _scrollController = ScrollController();

  bool get _isAtTop {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <=
        _scrollController.position.minScrollExtent + 0.01;
  }

  double get _leftPullProgress =>
      (_leftPullDistance / AppSquareRefreshTheme.pullThreshold).clamp(0.0, 1.0);

  final _categories = ['默认', '问答', '资料', '兴趣', '梗图'];

  String? get _currentCategory {
    final index = _selectedCategoryIndex;
    if (index == 0) return null;
    return _categories[index];
  }

  void _onCategoryTap(int index) {
    if (_selectedCategoryIndex == index) return;
    HapticFeedback.lightImpact();
    setState(() => _selectedCategoryIndex = index);
    _reloadCategory();
  }

  void resetToDefault() {
    if (_selectedCategoryIndex == 0) {
      _reloadCategory();
      return;
    }
    _selectedCategoryIndex = 0;
    _reloadCategory();
  }

  Future<void> _reloadCategory() async {
    setState(() {
      _posts = [];
      _allIds = [];
      _updateAtById = {};
      _loadedCount = 0;
      _comments.clear();
      _postsNeedCommentRefresh.clear();
      _loadingIds.clear();
      _loading = false;
      _error = null;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await _initLoad();
  }

  void _onLeftPullEnd() {
    // 刷新进行中忽略后续手势，防止并发多个 _refresh 双双 insertAll 造成重复帖
    if (_leftRefreshing) return;
    if (_leftPullProgress >= 1.0) {
      _triggerLeftRefresh();
    } else if (_leftPullDistance != 0 || _leftPullHapticTriggered) {
      setState(() {
        _leftPullDistance = 0;
        _leftPullHapticTriggered = false;
      });
    }
  }

  Future<void> _triggerLeftRefresh() async {
    setState(() {
      _leftRefreshing = true;
      _leftPullDistance = AppSquareRefreshTheme.pullThreshold;
      _leftPullHapticTriggered = false;
    });
    await _refresh();
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      setState(() {
        _leftRefreshing = false;
        _leftPullDistance = 0;
      });
    }
  }

  void _onNeedCommentRefresh(int postId) {
    if (!_postsNeedCommentRefresh.contains(postId)) return;
    final post = _posts.firstWhere((p) => p.id == postId);
    _refreshPostComments(post);
    _postsNeedCommentRefresh.remove(postId);
  }

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ---- 首次启动加载 ----
  //
  // 流程：
  //   1. 先从 API 获取最新 ID 列表（失败则用 Hive 缓存的旧列表）
  //   2. 取前 7 个 ID，逐个加载帖子
  //      - Hive 有 → 直接用
  //      - Hive 无 → API 请求 → 存入 Hive
  //   3. 帖子按 _allIds 顺序排列显示
  //
  // 第二次打开时，Hive 里的旧帖子秒出，新帖子从 API 补。
  //
  Future<void> _initLoad() async {
    final category = _currentCategory;
    try {
      final res = await ApiService.getIdListV2(category: category);
      _allIds = [for (final m in res.items) m.id];
      _updateAtById = {for (final m in res.items) m.id: m.updateAt};
      if (category == null) await PostStorage.saveIdList(_allIds);
    } catch (_) {
      _allIds = category == null ? PostStorage.getIdList() : [];
      _updateAtById = {};
    }

    if (_allIds.isEmpty) {
      setState(() {
        _loading = false;
        _error = '加载失败，请检查网络';
      });
      return;
    }

    _posts = [];
    _loadedCount = 0;
    await _loadMore();

    if (_posts.isEmpty) {
      setState(() {
        _loading = false;
        _error = '加载失败，请检查网络';
      });
    }
  }

  // ---- 加载下一批帖子（7 篇）----
  //
  // 流程：
  //   1. 从 _allIds 中取 _loadedCount 之后的 7 个 ID
  //   2. 7 个请求并行发出（不串行等待）
  //   3. 拿到一篇就立即显示一篇
  //   4. 排序保证与 _allIds 顺序一致
  //
  // 调用时机：
  //   - _initLoad 首次加载
  //   - 列表滚到距底部 300px 时触发
  //
  /// 本地缓存是否已是最新：无 idListv2 元数据（如离线回退）时视为未知，
  /// 维持原“逐帖复查”行为；有元数据时缓存 update_at 不旧于服务端才算最新
  bool _isCacheFresh(Post cached) {
    final serverUpdateAt = _updateAtById[cached.id];
    if (serverUpdateAt == null || serverUpdateAt.isEmpty) return false;
    if (cached.updateAt.isEmpty) return false;
    return cached.updateAt.compareTo(serverUpdateAt) >= 0;
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    final batch = _allIds
        .skip(_loadedCount)
        .take(7)
        .where((id) => !_loadingIds.contains(id))
        .toList();
    if (batch.isEmpty) return;

    setState(() => _loading = true);
    for (final id in batch) {
      _loadingIds.add(id);
    }

    final futures = batch.map((id) async {
      final cached = PostStorage.getPost(id);
      // 缓存未过期 → 直接使用，不再发任何复查请求
      if (cached != null && _isCacheFresh(cached)) {
        return (post: cached, fresh: false, upToDate: true);
      }
      final post = await ApiService.getPostV2(id);
      if (post != null) {
        await PostStorage.savePost(post);
        return (post: post, fresh: true, upToDate: false);
      }
      // 拉取失败回退缓存（断网时仍可显示），评论走原复查逻辑
      return (post: cached, fresh: false, upToDate: false);
    }).toList();

    final order = _buildOrderMap();
    for (int i = 0; i < futures.length; i++) {
      final result = await futures[i];
      final post = result.post;
      _loadingIds.remove(batch[i]);
      if (post != null && !_posts.any((p) => p.id == post.id)) {
        _comments[post.id] ??= PostStorage.getComments(post.comments);
        setState(() {
          _posts.add(post);
          _posts.sort((a, b) => (order[a.id] ?? 0).compareTo(order[b.id] ?? 0));
        });
        if (!result.upToDate) {
          _refreshPostComments(post, fetchLatest: !result.fresh);
        }
      }
    }

    _loadedCount += batch.length;
    setState(() => _loading = false);

    // 后台预下载缩略图，只遍历本轮新加载的帖子
    for (final post in _posts) {
      if (!batch.contains(post.id)) continue;
      for (final img in post.images) {
        if (PostStorage.getThumbnail(img.fileName) == null) {
          ApiService.downloadThumbnail(img.fileName).then((data) {
            if (data != null) PostStorage.saveThumbnail(img.fileName, data);
          });
        }
      }
    }

    if (_loadedCount < _allIds.length && _scrollController.hasClients) {
      final remaining = _scrollController.position.maxScrollExtent -
          _scrollController.position.pixels;
      if (remaining < 1500) {
        _loadMore();
      }
    }
  }

  // ---- 下拉刷新 ----
  Future<void> _refresh() async {
    _loading = true;
    final metas = await _fetchIdListMeta();

    if (metas.isEmpty) {
      _loading = false;
      return;
    }

    final newIds = [for (final m in metas) m.id];
    _updateAtById = {for (final m in metas) m.id: m.updateAt};

    await _removeDeletedPosts(newIds);
    final freshIds = await _fetchAndInsertNewPosts(newIds);
    final staleIds = await _refreshStalePosts();
    await _batchRefreshComments({...freshIds, ...staleIds});

    _loading = false;
  }

  /// 拉取 idListv2 元数据；失败时回退 Hive 缓存的 id 列表（无元数据，
  /// 后续按“未知”处理，维持原逐帖复查行为）
  Future<List<PostMeta>> _fetchIdListMeta() async {
    final category = _currentCategory;
    try {
      final res = await ApiService.getIdListV2(category: category);
      if (category == null) {
        await PostStorage.saveIdList([for (final m in res.items) m.id]);
      }
      return res.items;
    } catch (_) {
      final ids = category == null ? PostStorage.getIdList() : <int>[];
      return [for (final id in ids) PostMeta(id: id)];
    }
  }

  Future<void> _removeDeletedPosts(List<int> newIds) async {
    final newIdSet = newIds.toSet();
    final removedIds =
        _posts.map((p) => p.id).where((id) => !newIdSet.contains(id)).toList();
    if (removedIds.isEmpty) return;

    for (final id in removedIds) {
      _posts.removeWhere((p) => p.id == id);
      _comments.remove(id);
      _postsNeedCommentRefresh.remove(id);
    }
    setState(() {});
    await Future.wait(removedIds.map(PostStorage.deletePost));
  }

  /// 用 idListv2 的 update_at 比对已加载帖子，只重新拉取有变更的
  /// （回复/编辑都会刷新 update_at），替代原来的逐帖复查。
  /// 返回成功刷新的帖子 id，交由 _batchRefreshComments 同步评论。
  Future<Set<int>> _refreshStalePosts() async {
    final stale = _posts.where((p) {
      final serverUpdateAt = _updateAtById[p.id];
      if (serverUpdateAt == null || serverUpdateAt.isEmpty) return false;
      return p.updateAt.isEmpty || p.updateAt.compareTo(serverUpdateAt) < 0;
    }).toList();
    if (stale.isEmpty) return {};

    final results = await Future.wait(
      stale.map((p) async {
        try {
          return await ApiService.getPostV2(p.id);
        } catch (_) {
          return null;
        }
      }),
    );
    final refreshed = <int>{};
    var changed = false;
    for (final fresh in results.whereType<Post>()) {
      await PostStorage.savePost(fresh);
      refreshed.add(fresh.id);
      if (_applyPostReplacement(fresh)) changed = true;
    }
    if (changed && mounted) setState(() {});
    return refreshed;
  }

  Future<Set<int>> _fetchAndInsertNewPosts(List<int> newIds) async {
    final existingIds = _posts.map((p) => p.id).toSet();
    final addedIds = newIds.where((id) => !existingIds.contains(id)).toList();

    final fetched = await Future.wait(
      addedIds.map((id) async {
        final cached = PostStorage.getPost(id);
        if (cached != null) return (post: cached, fresh: false);
        final post = await ApiService.getPostV2(id);
        if (post != null) await PostStorage.savePost(post);
        return (post: post, fresh: true);
      }),
    );
    final newPosts = [for (final r in fetched) if (r.post != null) r.post!];
    final freshIds = {
      for (final r in fetched) if (r.fresh && r.post != null) r.post!.id,
    };

    // 拉取期间可能有在途的 _loadMore / 并发刷新已把同 id 帖子加入 _posts，
    // 插入前必须按当前 _posts 重新去重（同时去重 newPosts 内部重复 id）
    final currentIds = _posts.map((p) => p.id).toSet();
    final deduped = [for (final p in newPosts) if (currentIds.add(p.id)) p];

    _allIds = newIds;
    _loadedCount = _posts.length + deduped.length;
    if (deduped.isNotEmpty) {
      for (final p in deduped) {
        _comments[p.id] ??= PostStorage.getComments(p.comments);
      }
      final order = _buildOrderMap();
      _posts.insertAll(0, deduped);
      _posts.sort((a, b) => (order[a.id] ?? 0).compareTo(order[b.id] ?? 0));
      setState(() {});
    }

    return freshIds;
  }

  /// 批量刷新评论：只刷新本轮有变更的帖子（新帖 + update_at 变化的帖），
  /// 未变更的帖子评论必然没变，无需复查；
  /// 所有结果合并到一次 setState，避免多次独立重建列表。
  Future<void> _batchRefreshComments(Set<int> freshIds) async {
    for (final p in _posts) {
      if (freshIds.contains(p.id)) _postsNeedCommentRefresh.add(p.id);
    }

    final targets =
        _posts.where((p) => freshIds.contains(p.id)).take(7).toList();
    for (final p in targets) {
      _postsNeedCommentRefresh.remove(p.id);
    }
    if (targets.isEmpty) return;

    final results = await Future.wait(
      targets.map((p) => _fetchCommentRefreshResult(p)),
    );

    bool changed = false;
    for (final r in results) {
      if (r.freshPost != null && _applyPostReplacement(r.freshPost!)) {
        changed = true;
      }
      if (r.comments != null) {
        _comments[r.postId] = r.comments!;
        changed = true;
      }
    }

    if (changed && mounted) setState(() {});
  }

  /// 拉取单个帖子的评论数据并返回结果，不调用 setState。
  /// 仅用于批量刷新路径（帖子刚从 API 拉取，comment ID 列表已是最新）。
  Future<({int postId, List<Comment>? comments, Post? freshPost})>
      _fetchCommentRefreshResult(Post post) async {
    final newIds = post.comments;
    if (newIds.isEmpty) {
      return (postId: post.id, comments: null, freshPost: null);
    }

    final existingIds = _comments[post.id]?.map((c) => c.id).toSet() ?? {};
    final missingIds = newIds.where((id) => !existingIds.contains(id)).toList();

    if (missingIds.isEmpty &&
        _comments[post.id] != null &&
        _comments[post.id]!.length == newIds.length) {
      return (postId: post.id, comments: null, freshPost: null);
    }

    List<Comment> merged;
    if (missingIds.isEmpty) {
      merged = PostStorage.getComments(newIds);
    } else {
      final futures = missingIds.map((id) async {
        final cmt = await ApiService.getComment(id);
        if (cmt != null) await PostStorage.saveComment(cmt);
        return cmt;
      });
      final newCmts =
          (await Future.wait(futures)).whereType<Comment>().toList();
      final existing = _comments[post.id] ?? PostStorage.getComments(newIds);
      merged = <Comment>[...existing];
      for (final c in newCmts) {
        if (!merged.any((e) => e.id == c.id)) merged.add(c);
      }
    }

    merged.sort(
      (a, b) => newIds.indexOf(a.id).compareTo(newIds.indexOf(b.id)),
    );
    await PostStorage.updatePostCommentIds(post.id, newIds);
    return (postId: post.id, comments: merged, freshPost: null);
  }

  /// 用新帖数据替换列表中同 id 项，不调用 setState。返回是否发生了替换。
  bool _applyPostReplacement(Post fresh) {
    final idx = _posts.indexWhere((p) => p.id == fresh.id);
    if (idx < 0) return false;
    final old = _posts[idx];
    final same =
        old.author == fresh.author &&
        old.isAnonymous == fresh.isAnonymous &&
        old.updateAt == fresh.updateAt &&
        old.title == fresh.title &&
        old.content == fresh.content &&
        _sameIntList(old.comments, fresh.comments) &&
        _sameStringList(
          old.images.map((e) => e.fileName).toList(),
          fresh.images.map((e) => e.fileName).toList(),
        ) &&
        _sameStringList(
          old.attachments.map((e) => e.fileName).toList(),
          fresh.attachments.map((e) => e.fileName).toList(),
        ) &&
        _sameStringList(
          old.attachments.map((e) => e.sourceName).toList(),
          fresh.attachments.map((e) => e.sourceName).toList(),
        );
    if (same) return false;
    _posts[idx] = fresh;
    return true;
  }

  Map<int, int> _buildOrderMap() {
    return {for (var i = 0; i < _allIds.length; i++) _allIds[i]: i};
  }

  static bool _sameIntList(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // 刷新单个帖子的回复：获取最新 ID → 对比本地 → 只拉取新增
  // fetchLatest=false 时直接用 post.comments（帖子刚从 API 拉取，列表已最新，省一次 getPost）
  Future<void> _refreshPostComments(
    Post post, {
    bool fetchLatest = true,
  }) async {
    List<int> newIds;
    if (fetchLatest) {
      try {
        final fresh = await ApiService.getPostV2(post.id);
        if (fresh != null) {
          await PostStorage.savePost(fresh);
          _replaceLoadedPost(fresh);
          newIds = fresh.comments;
        } else {
          newIds = post.comments;
        }
      } catch (_) {
        newIds = post.comments;
      }
    } else {
      newIds = post.comments;
    }
    if (newIds.isEmpty) return;

    final existingIds = _comments[post.id]?.map((c) => c.id).toSet() ?? {};
    final missingIds = newIds.where((id) => !existingIds.contains(id)).toList();

    if (missingIds.isEmpty) {
      if (_comments[post.id] == null ||
          _comments[post.id]!.length != newIds.length) {
        _comments[post.id] = PostStorage.getComments(newIds);
        await PostStorage.updatePostCommentIds(post.id, newIds);
        if (mounted) setState(() {});
      }
      return;
    }

    final futures = missingIds.map((id) async {
      final cmt = await ApiService.getComment(id);
      if (cmt != null) await PostStorage.saveComment(cmt);
      return cmt;
    });
    final newCmts = (await Future.wait(futures)).whereType<Comment>().toList();

    final existing = _comments[post.id] ?? PostStorage.getComments(newIds);
    final merged = <Comment>[...existing];
    for (final c in newCmts) {
      if (!merged.any((e) => e.id == c.id)) merged.add(c);
    }
    merged.sort((a, b) => newIds.indexOf(a.id).compareTo(newIds.indexOf(b.id)));

    await PostStorage.updatePostCommentIds(post.id, newIds);
    if (mounted) setState(() => _comments[post.id] = merged);
  }

  /// 用最新帖数据替换列表中同 id 项（内容/署名/评论变化时刷新 UI）
  void _replaceLoadedPost(Post fresh) {
    final idx = _posts.indexWhere((p) => p.id == fresh.id);
    if (idx < 0) return;
    final old = _posts[idx];
    final same =
        old.author == fresh.author &&
        old.isAnonymous == fresh.isAnonymous &&
        old.updateAt == fresh.updateAt &&
        old.title == fresh.title &&
        old.content == fresh.content &&
        _sameIntList(old.comments, fresh.comments) &&
        _sameStringList(
          old.images.map((e) => e.fileName).toList(),
          fresh.images.map((e) => e.fileName).toList(),
        ) &&
        _sameStringList(
          old.attachments.map((e) => e.fileName).toList(),
          fresh.attachments.map((e) => e.fileName).toList(),
        ) &&
        _sameStringList(
          old.attachments.map((e) => e.sourceName).toList(),
          fresh.attachments.map((e) => e.sourceName).toList(),
        );
    if (same) return;
    _posts[idx] = fresh;
    if (mounted) setState(() {});
  }

  /// 刷新单个帖子：重新拉取帖数据 + 回复，并更新 UI/缓存
  Future<void> _refreshSinglePost(Post post) async {
    Post? fresh;
    try {
      fresh = await ApiService.getPostV2(post.id);
    } catch (_) {
      fresh = null;
    }
    if (fresh == null) {
      if (mounted) showAppSnackBar(context, message: '刷新失败，请检查网络');
      return;
    }
    await PostStorage.savePost(fresh);
    _replaceLoadedPost(fresh);
    await _refreshPostComments(fresh, fetchLatest: false);
    if (mounted) showAppSnackBar(context, message: '已刷新该帖子');
  }
}
