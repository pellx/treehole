import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/comment.dart';
import '../../models/post.dart';
import '../../models/post_meta.dart';
import '../../services/api.dart';
import '../../services/storage.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_search_theme.dart';
import '../../theme/app_square_top_bar_theme.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading_indicator.dart';
import '../../widgets/image_overlay.dart';
import '../../widgets/live_pop_scope.dart';
import '../../widgets/post_card.dart';

/// 搜索页：顶部输入栏 + 搜索历史
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  List<Post> _posts = [];
  bool _loading = false;
  String? _error;
  String _query = '';
  List<String> _history = [];
  int _deletingIndex = -1;
  final Map<int, List<Comment>> _comments = {};
  final Set<int> _postsNeedCommentRefresh = {};
  final _categories = ['默认', '问答', '资料', '兴趣', '梗图'];
  int _selectedCategoryIndex = 0;

  final _sortOptions = ['默认排序', '最新发布', '最新回复', '回复最多'];
  final _timeOptions = ['不限时间', '最近一天', '最近一月', '最近半年'];
  int _selectedSortIndex = 0;
  int _selectedTimeIndex = 0;
  bool _filterPanelExpanded = false;
  bool _searchCommitted = false;
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _loadHistory();
    // 进入页面后自动聚焦，唤出键盘
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(() => setState(() {}));
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onNeedCommentRefresh(int postId) {
    if (!_postsNeedCommentRefresh.contains(postId)) return;
    final post = _posts.firstWhere((p) => p.id == postId);
    _refreshPostComments(post);
    _postsNeedCommentRefresh.remove(postId);
  }

  Future<void> _refreshPostComments(Post post) async {
    List<int> newIds;
    try {
      final fresh = await ApiService.getPostV2(post.id);
      if (fresh != null) {
        await PostStorage.savePost(fresh);
        final idx = _posts.indexWhere((p) => p.id == post.id);
        if (idx >= 0) {
          _posts[idx] = fresh;
        }
        newIds = fresh.comments;
      } else {
        newIds = post.comments;
      }
    } catch (_) {
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
    for (final cmt in newCmts) {
      if (!merged.any((e) => e.id == cmt.id)) merged.add(cmt);
    }
    merged.sort((a, b) => newIds.indexOf(a.id).compareTo(newIds.indexOf(b.id)));

    await PostStorage.updatePostCommentIds(post.id, newIds);
    if (mounted) setState(() => _comments[post.id] = merged);
  }

  String _formatDateIso(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static int _compareDateTimeDesc(DateTime? a, DateTime? b) {
    if (a == null || b == null) return 0;
    return b.compareTo(a);
  }

  List<PostMeta> _sortMeta(List<PostMeta> items) {
    final copy = List<PostMeta>.from(items);
    switch (_selectedSortIndex) {
      case 2: // 最新回复：按 update_at 倒序
        copy.sort((a, b) {
          final cmp = _compareDateTimeDesc(
            DateTime.tryParse(a.updateAt),
            DateTime.tryParse(b.updateAt),
          );
          if (cmp != 0) return cmp;
          return _compareDateTimeDesc(
            DateTime.tryParse(a.createdAt),
            DateTime.tryParse(b.createdAt),
          );
        });
      case 3: // 回复最多：按 reply_times 倒序
        copy.sort((a, b) {
          final cmp = b.replyTimes.compareTo(a.replyTimes);
          if (cmp != 0) return cmp;
          return _compareDateTimeDesc(
            DateTime.tryParse(a.createdAt),
            DateTime.tryParse(b.createdAt),
          );
        });
      case 0: // 默认排序
      case 1: // 最新发布
      default:
        copy.sort(
          (a, b) => _compareDateTimeDesc(
            DateTime.tryParse(a.createdAt),
            DateTime.tryParse(b.createdAt),
          ),
        );
    }
    return copy;
  }

  Future<void> _loadHistory() async {
    final history = PostStorage.getSearchHistory();
    setState(() {
      _history = history;
      _deletingIndex = -1;
    });
  }

  Future<void> _deleteSingleHistory(String query) async {
    await PostStorage.removeSearchHistory(query);
    _loadHistory();
  }

  Future<void> _showClearHistoryConfirm() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清空搜索历史',
      message: '确定要清空所有搜索历史吗？此操作无法恢复。',
      cancelText: '取消',
      confirmText: '清空',
    );
    if (confirmed == true) {
      _clearHistory();
    }
  }

  Future<void> _addHistory(String query) async {
    await PostStorage.addSearchHistory(query);
    _loadHistory();
  }

  Future<void> _clearHistory() async {
    await PostStorage.clearSearchHistory();
    _loadHistory();
  }

  String _formatDate(DateTime d) {
    return '${d.year}年${d.month}月${d.day}日';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_customStart ?? now.subtract(const Duration(days: 7)))
        : (_customEnd ?? now);
    final firstDate = isStart
        ? DateTime(2000)
        : (_customStart ?? DateTime(2000));
    final lastDate = isStart ? (_customEnd ?? now) : now;
    final safeInitial = initial.isBefore(firstDate)
        ? firstDate
        : (initial.isAfter(lastDate) ? lastDate : initial);

    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isStart) {
        _customStart = DateTime(picked.year, picked.month, picked.day);
      } else {
        _customEnd = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
      }
      _selectedTimeIndex = -1;
    });
    if (_query.isNotEmpty || _searchCommitted) _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final category = _selectedCategoryIndex == 0
          ? null
          : _categories[_selectedCategoryIndex];
      final result = await ApiService.getIdListV2(
        search: _query.isEmpty ? null : _query,
        category: category,
        dateStart: _customStart != null ? _formatDateIso(_customStart!) : null,
        dateEnd: _customEnd != null ? _formatDateIso(_customEnd!) : null,
      );
      var items = result.items;

      // 发布时间筛选（基于元数据，客户端）
      final now = DateTime.now();
      if (_selectedTimeIndex > 0) {
        final days = _selectedTimeIndex == 1
            ? 1
            : _selectedTimeIndex == 2
            ? 30
            : 180;
        items = items.where((m) {
          final created = DateTime.tryParse(m.createdAt);
          if (created == null) return true;
          return now.difference(created).inDays <= days;
        }).toList();
      }

      // 排序方式（基于元数据）
      items = _sortMeta(items);

      final ids = items.take(30).map((m) => m.id).toList();
      final posts = <Post>[];
      await Future.wait(
        ids.map((id) async {
          final post = await ApiService.getPostV2(id);
          if (post != null) posts.add(post);
        }),
      );
      // 保持排序后的顺序
      posts.sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));

      for (final post in posts) {
        _comments[post.id] ??= PostStorage.getComments(post.comments);
        _postsNeedCommentRefresh.add(post.id);
      }
      if (mounted) {
        setState(() {
          _posts = posts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败：$e';
        });
      }
    }
  }

  void _onSearch() {
    final query = _controller.text.trim();
    _query = query;
    _searchCommitted = true;
    _focusNode.unfocus();
    if (query.isNotEmpty) {
      HapticFeedback.lightImpact();
      _addHistory(query);
    }
    _loadPosts();
  }

  void _onHistoryTap(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _onSearch();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return LivePopScope(
      recomputeTrigger: ImageOverlay.isOpen,
      canPop: () => ImageOverlay.currentEntry == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ImageOverlay.closeCurrent();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: colors.common.surface,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: colors.common.background,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildSearchBar(colors, onSurface),
                if (_query.isNotEmpty || _searchCommitted)
                  _buildCategoryBar(colors, onSurface),
                _buildSearchHistory(colors, onSurface),
                Expanded(
                  child: Stack(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          if (_filterPanelExpanded) {
                            setState(() => _filterPanelExpanded = false);
                          }
                        },
                        child: _buildBody(colors),
                      ),
                      if ((_query.isNotEmpty || _searchCommitted) &&
                          _filterPanelExpanded)
                        Positioned(
                          top: AppSearchTheme.filterPanelOverlayTop,
                          left: AppSearchTheme.filterPanelOverlayLeft,
                          right: AppSearchTheme.filterPanelOverlayRight,
                          child: _buildFilterPanel(colors, onSurface),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(AppColors colors, Color onSurface) {
    return Container(
      color: colors.common.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSearchTheme.barHorizontalPadding,
        AppSearchTheme.barVerticalPadding,
        AppSearchTheme.barTrailingPadding,
        AppSearchTheme.barVerticalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              Icons.chevron_left,
              color: onSurface,
              size: AppSearchTheme.backIconSize,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _focusNode.requestFocus(),
              child: Container(
                height: AppSearchTheme.searchBarHeight,
                decoration: BoxDecoration(
                  color: colors.common.surface,
                  borderRadius: BorderRadius.circular(
                    AppSearchTheme.inputBorderRadius,
                  ),
                  border: Border.all(
                    color: colors.common.divider,
                    width: AppSearchTheme.inputBorderWidth,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: AppSearchTheme.searchIconLeftPadding),
                    Icon(
                      Icons.search,
                      color: colors.common.trailingIcon,
                      size: AppSearchTheme.prefixIconSize,
                    ),
                    SizedBox(width: AppSearchTheme.searchIconToTextGap),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _onSearch(),
                        cursorColor: AppSearchTheme.searchAccent,
                        textAlignVertical: TextAlignVertical.center,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: AppSearchTheme.inputTextFontSize,
                        ),
                        decoration: InputDecoration.collapsed(
                          hintText: _searchCommitted
                              ? null
                              : AppSearchTheme.inputHint,
                          hintStyle: TextStyle(
                            color: colors.common.trailingIcon,
                            fontSize: AppSearchTheme.inputHintFontSize,
                          ),
                        ),
                      ),
                    ),
                    if (_controller.text.isNotEmpty || _searchCommitted)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _query = '';
                            _searchCommitted = false;
                          });
                          _controller.clear();
                          _focusNode.unfocus();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 8,
                            right: AppSearchTheme.clearIconRightPadding,
                          ),
                          child: Icon(
                            Icons.clear,
                            color: colors.common.trailingIcon,
                            size: AppSearchTheme.clearIconSize,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSearchTheme.searchButtonLeftGap),
          TextButton(
            onPressed: _onSearch,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: AppSearchTheme.searchButtonColor,
              minimumSize: const Size(
                AppSearchTheme.searchButtonMinWidth,
                AppSearchTheme.searchButtonMinHeight,
              ),
            ),
            child: Text(
              AppSearchTheme.searchButtonText,
              style: TextStyle(
                fontSize: AppSearchTheme.searchButtonFontSize,
                fontWeight: AppSearchTheme.searchButtonFontWeight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar(AppColors colors, Color onSurface) {
    final bg = Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : colors.common.surface;

    return Container(
      color: bg,
      height: AppSquareTopBarTheme.height,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.asMap().entries.map((entry) {
                  final index = entry.key;
                  final label = entry.value;
                  final selected = index == _selectedCategoryIndex;
                  return GestureDetector(
                    onTap: () {
                      if (_selectedCategoryIndex == index) return;
                      setState(() => _selectedCategoryIndex = index);
                      if (_query.isNotEmpty) _loadPosts();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSquareTopBarTheme.itemHorizontalPadding,
                      ),
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: AppSquareTopBarTheme.fontSize,
                              fontWeight: selected
                                  ? AppSquareTopBarTheme.selectedFontWeight
                                  : AppSquareTopBarTheme.unselectedFontWeight,
                              color: selected
                                  ? colors.common.green
                                  : onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          SizedBox(
                            height: AppSquareTopBarTheme.indicatorTopSpacing,
                          ),
                          Container(
                            width: AppSquareTopBarTheme.indicatorWidth,
                            height: AppSquareTopBarTheme.indicatorHeight,
                            decoration: BoxDecoration(
                              color: selected
                                  ? colors.common.green
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                AppSquareTopBarTheme.indicatorBorderRadius,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: AppSquareTopBarTheme.indicatorBottomSpacing,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          GestureDetector(
            onTap: () =>
                setState(() => _filterPanelExpanded = !_filterPanelExpanded),
            child: Container(
              color: bg,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSearchTheme.filterButtonHorizontalPadding,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.filter_alt_outlined,
                size: AppSearchTheme.filterButtonIconSize,
                color: onSurface.withValues(
                  alpha: AppSearchTheme.filterButtonIconAlpha,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(AppColors colors, Color onSurface) {
    final bg = Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : colors.common.surface;

    Widget sectionTitle(String title) {
      return Padding(
        padding: const EdgeInsets.only(
          bottom: AppSearchTheme.filterPanelTitleBottomGap,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: AppSearchTheme.filterPanelTitleFontSize,
            fontWeight: AppSearchTheme.filterPanelTitleFontWeight,
            color: onSurface.withValues(alpha: 0.9),
          ),
        ),
      );
    }

    Widget chipGrid({
      required List<String> options,
      required int selectedIndex,
      required ValueChanged<int> onSelected,
      required double chipHeight,
    }) {
      final children = <Widget>[];
      for (var i = 0; i < options.length; i++) {
        final label = options[i];
        final selected = i == selectedIndex;
        if (i > 0) {
          children.add(SizedBox(width: AppSearchTheme.filterPanelChipSpacing));
        }
        children.add(
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (selected) return;
                onSelected(i);
                setState(() {});
                if (_query.isNotEmpty || _searchCommitted) _loadPosts();
              },
              child: Container(
                height: chipHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSearchTheme.filterPanelChipHorizontalPadding,
                  vertical: AppSearchTheme.filterPanelChipVerticalPadding,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppSearchTheme.searchAccent.withValues(alpha: 0.1)
                      : bg,
                  borderRadius: BorderRadius.circular(
                    AppSearchTheme.filterPanelChipBorderRadius,
                  ),
                  border: Border.all(
                    color: selected
                        ? AppSearchTheme.searchAccent
                        : colors.common.divider,
                    width: selected
                        ? AppSearchTheme.filterPanelSelectedBorderWidth
                        : AppSearchTheme.filterPanelUnselectedBorderWidth,
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppSearchTheme.filterPanelChipFontSize,
                    color: selected
                        ? AppSearchTheme.searchAccent
                        : onSurface.withValues(alpha: 0.75),
                    fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return Row(children: children);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelInnerWidth =
            constraints.maxWidth -
            AppSearchTheme.filterPanelPadding.left -
            AppSearchTheme.filterPanelPadding.right;
        final chipWidth =
            (panelInnerWidth -
                (AppSearchTheme.filterPanelChipCrossAxisCount - 1) *
                    AppSearchTheme.filterPanelChipSpacing) /
            AppSearchTheme.filterPanelChipCrossAxisCount;
        final chipHeight =
            chipWidth / AppSearchTheme.filterPanelChipChildAspectRatio;

        return Container(
          width: double.infinity,
          padding: AppSearchTheme.filterPanelPadding,
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: BorderSide(
                color: colors.common.divider,
                width: AppSearchTheme.filterPanelBottomBorderWidth,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              sectionTitle('排序方式'),
              chipGrid(
                options: _sortOptions,
                selectedIndex: _selectedSortIndex,
                onSelected: (i) => _selectedSortIndex = i,
                chipHeight: chipHeight,
              ),
              SizedBox(height: AppSearchTheme.filterPanelSectionSpacing),
              sectionTitle('发布时间'),
              chipGrid(
                options: _timeOptions,
                selectedIndex: _selectedTimeIndex,
                onSelected: (i) {
                  _selectedTimeIndex = i;
                  _customStart = null;
                  _customEnd = null;
                },
                chipHeight: chipHeight,
              ),
              SizedBox(height: AppSearchTheme.filterPanelDateRangeTopGap),
              _buildDateRangeRow(
                colors: colors,
                onSurface: onSurface,
                bg: bg,
                chipHeight: chipHeight,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateRangeRow({
    required AppColors colors,
    required Color onSurface,
    required Color bg,
    required double chipHeight,
  }) {
    Widget chip({
      required String label,
      required DateTime? date,
      required VoidCallback onTap,
    }) {
      final selected = date != null;
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: chipHeight,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              vertical: AppSearchTheme.filterPanelChipVerticalPadding,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppSearchTheme.searchAccent.withValues(alpha: 0.1)
                  : bg,
              borderRadius: BorderRadius.circular(
                AppSearchTheme.filterPanelChipBorderRadius,
              ),
              border: Border.all(
                color: selected
                    ? AppSearchTheme.searchAccent
                    : colors.common.divider,
                width: selected
                    ? AppSearchTheme.filterPanelSelectedBorderWidth
                    : AppSearchTheme.filterPanelUnselectedBorderWidth,
              ),
            ),
            child: Text(
              date != null ? _formatDate(date) : label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppSearchTheme.filterPanelChipFontSize,
                color: selected
                    ? AppSearchTheme.searchAccent
                    : onSurface.withValues(alpha: 0.75),
                fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(
          label: '开始日期',
          date: _customStart,
          onTap: () => _pickDate(isStart: true),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSearchTheme.filterPanelDateRangeChipSpacing,
          ),
          child: Text(
            AppSearchTheme.filterPanelDateRangeMiddleText,
            style: TextStyle(
              fontSize: AppSearchTheme.filterPanelChipFontSize,
              color: onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        chip(
          label: '结束日期',
          date: _customEnd,
          onTap: () => _pickDate(isStart: false),
        ),
      ],
    );
  }

  Widget _buildSearchHistory(AppColors colors, Color onSurface) {
    if (_query.isNotEmpty || _searchCommitted || _history.isEmpty) {
      return const SizedBox.shrink();
    }
    final chipBg = AppSearchTheme.chipBg(context);

    return Container(
      color: colors.common.surface,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSearchTheme.historySectionHorizontalPadding,
        AppSearchTheme.historySectionTopPadding,
        AppSearchTheme.historySectionHorizontalPadding,
        AppSearchTheme.historySectionBottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                AppSearchTheme.historyTitle,
                style: TextStyle(
                  fontSize: AppSearchTheme.historyTitleFontSize,
                  fontWeight: AppSearchTheme.historyTitleFontWeight,
                  color: onSurface,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: AppSearchTheme.historyClearIconSize,
                  color: onSurface.withValues(
                    alpha: AppSearchTheme.historyClearIconAlpha,
                  ),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: AppSearchTheme.historyIconButtonSize,
                  minHeight: AppSearchTheme.historyIconButtonSize,
                ),
                onPressed: _showClearHistoryConfirm,
              ),
            ],
          ),
          SizedBox(height: AppSearchTheme.historyTitleChipGap),
          Wrap(
            spacing: AppSearchTheme.historyWrapSpacing,
            runSpacing: AppSearchTheme.historyWrapRunSpacing,
            children: _history.asMap().entries.map((entry) {
              final index = entry.key;
              final q = entry.value;
              final showDelete = _deletingIndex == index;
              return GestureDetector(
                onTap: () => _onHistoryTap(q),
                onLongPress: () => setState(() => _deletingIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSearchTheme.historyChipHorizontalPadding,
                    vertical: AppSearchTheme.historyChipVerticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(
                      AppSearchTheme.historyChipBorderRadius,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        q,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppSearchTheme.historyChipFontSize,
                          color: onSurface.withValues(
                            alpha: AppSearchTheme.historyChipTextAlpha,
                          ),
                        ),
                      ),
                      if (showDelete)
                        GestureDetector(
                          onTap: () => _deleteSingleHistory(q),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppColors colors) {
    if (_query.isEmpty && !_searchCommitted) {
      return const SizedBox.shrink();
    }
    if (_loading) {
      return const AppLoadingCenter(message: '加载中...');
    }
    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _loadPosts);
    }
    final posts = _posts;
    if (posts.isEmpty) {
      return const AppEmptyState(
        message: '没有找到相关帖子',
        icon: Icons.search_off_outlined,
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        AppDimens.listPaddingLeft,
        AppDimens.listPaddingTop,
        AppDimens.listPaddingRight,
        AppDimens.listPaddingBottom,
      ),
      itemCount: posts.length,
      itemBuilder: (_, index) {
        final post = posts[index];
        return PostCard(
          key: ValueKey(post.id),
          post: post,
          comments: _comments[post.id] ?? [],
          onNeedCommentRefresh: () => _onNeedCommentRefresh(post.id),
          onCommentCreated: (cmt) {
            setState(() {
              _comments[post.id] ??= [];
              _comments[post.id] = [..._comments[post.id]!, cmt];
            });
          },
        );
      },
    );
  }
}
