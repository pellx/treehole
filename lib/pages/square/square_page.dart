import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/comment.dart';
import '../../models/post.dart';
import '../../models/post_meta.dart';
import '../../services/api.dart';
import '../../services/storage.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_square_refresh_theme.dart';
import '../../theme/app_square_top_bar_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading_indicator.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/image_overlay.dart';
import '../../widgets/live_pop_scope.dart';
import '../../widgets/post_card.dart';
import '../search/search_page.dart';

part 'square_page_state.dart';

class SquarePage extends StatefulWidget {
  const SquarePage({super.key});

  @override
  State<SquarePage> createState() => SquarePageState();
}

class SquarePageState extends State<SquarePage> with SquarePageStateMixin {
  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final topBarBg = isLight
        ? AppSquareTopBarTheme.backgroundLight
        : AppSquareTopBarTheme.backgroundDark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: topBarBg,
        statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      ),
      child: LivePopScope(
        recomputeTrigger: ImageOverlay.isOpen,
        canPop: () => ImageOverlay.currentEntry == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) ImageOverlay.closeCurrent();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Container(
            color: topBarBg,
            child: SafeArea(
              bottom: false,
              child: _buildRefreshShell(_buildBody()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final topBar = _buildTopBar(colors, onSurface);

    if (_loading && _posts.isEmpty) {
      return Container(
        color: colors.common.background,
        child: CustomScrollView(
          slivers: [
            topBar,
            const SliverFillRemaining(
              child: AppLoadingCenter(message: '加载中...'),
            ),
          ],
        ),
      );
    }
    if (_error != null && _posts.isEmpty) {
      return Container(
        color: colors.common.background,
        child: CustomScrollView(
          slivers: [
            topBar,
            SliverFillRemaining(
              child: AppErrorState(message: _error!, onRetry: _initLoad),
            ),
          ],
        ),
      );
    }
    if (_posts.isEmpty) {
      return Container(
        color: colors.common.background,
        child: CustomScrollView(
          slivers: [
            topBar,
            const SliverFillRemaining(
              child: AppEmptyState(
                message: '还没有帖子，快来发布第一条吧',
                icon: Icons.inbox_outlined,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: colors.common.background,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 1500 &&
              !_loading) {
            _loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            topBar,
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppDimens.listPaddingLeft,
                AppSquareTopBarTheme.postListTopSpacing,
                AppDimens.listPaddingRight,
                AppDimens.listPaddingBottom,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _posts
                      .map(
                        (p) => PostCard(
                          key: ValueKey(p.id),
                          post: p,
                          comments: _comments[p.id] ?? [],
                          onNeedCommentRefresh: () =>
                              _onNeedCommentRefresh(p.id),
                          onRefreshPost: () => _refreshSinglePost(p),
                          onCommentCreated: (cmt) {
                            setState(() {
                              _comments[p.id] ??= [];
                              _comments[p.id] = [..._comments[p.id]!, cmt];
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部下拉刷新球外壳：列表置顶时，任意位置向下拉都会唤出左上角刷新球
  Widget _buildRefreshShell(Widget child) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final progress = _leftPullProgress;

    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: AppSquareTopBarTheme.height,
          bottom: 0,
          child: RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: {
              _TopPullRecognizer:
                  GestureRecognizerFactoryWithHandlers<_TopPullRecognizer>(
                    _TopPullRecognizer.new,
                    (instance) {
                      instance.isAtTop = () => _isAtTop;
                      instance.onStart = () {
                        _leftPullDistance = 0;
                        _leftPullHapticTriggered = false;
                      };
                      instance.onMove = (cumulativeDy) {
                        setState(() {
                          _leftPullDistance = cumulativeDy;
                          if (_leftPullProgress >= 1.0 &&
                              !_leftPullHapticTriggered) {
                            HapticFeedback.mediumImpact();
                            _leftPullHapticTriggered = true;
                          }
                        });
                      };
                      instance.onEnd = _onLeftPullEnd;
                    },
                  ),
            },
          ),
        ),
        Positioned(
          left:
              -AppSquareRefreshTheme.ballSize +
              (AppSquareRefreshTheme.ballSize +
                      AppSquareRefreshTheme.ballLeftFinalInset) *
                  progress,
          top:
              -AppSquareRefreshTheme.ballSize +
              (AppSquareRefreshTheme.ballSize +
                      AppSquareRefreshTheme.ballTopFinalInset) *
                  progress,
          child: Opacity(
            opacity: progress,
            child: Container(
              width: AppSquareRefreshTheme.ballSize,
              height: AppSquareRefreshTheme.ballSize,
              decoration: BoxDecoration(
                color: colors.common.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors.common.onSurface.withValues(
                      alpha: AppSquareRefreshTheme.shadowOpacity,
                    ),
                    blurRadius: 8,
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
              child: Center(
                child: _leftRefreshing
                    ? SizedBox(
                        width: AppSquareRefreshTheme.indicatorSize,
                        height: AppSquareRefreshTheme.indicatorSize,
                        child: CircularProgressIndicator(
                          strokeWidth:
                              AppSquareRefreshTheme.indicatorStrokeWidth,
                          color: colors.common.green,
                        ),
                      )
                    : Icon(
                        Icons.refresh,
                        size: AppSquareRefreshTheme.iconSize,
                        color: colors.common.green,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 顶部分类栏
  Widget _buildTopBar(AppColors colors, Color onSurface) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final topBarBg = isLight
        ? AppSquareTopBarTheme.backgroundLight
        : AppSquareTopBarTheme.backgroundDark;

    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedHeaderDelegate(
        child: Container(
          color: topBarBg,
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
                        onTap: () => _onCategoryTap(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal:
                                AppSquareTopBarTheme.itemHorizontalPadding,
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
                                      : AppSquareTopBarTheme
                                            .unselectedFontWeight,
                                  color: selected
                                      ? colors.common.green
                                      : onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                              SizedBox(
                                height:
                                    AppSquareTopBarTheme.indicatorTopSpacing,
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
                                height:
                                    AppSquareTopBarTheme
                                        .indicatorBottomSpacing,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  right: AppSquareTopBarTheme.searchIconRightInset,
                ),
                child: IconButton(
                  constraints: BoxConstraints.tightFor(
                    width: AppSquareTopBarTheme.height,
                    height: AppSquareTopBarTheme.height,
                  ),
                  padding: const EdgeInsets.only(
                    top: AppSquareTopBarTheme.searchIconTopPadding,
                    bottom: AppSquareTopBarTheme.searchIconBottomPadding,
                  ),
                  icon: Icon(
                    Icons.search,
                    color: onSurface,
                    size: AppSquareTopBarTheme.searchIconSize,
                  ),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const SearchPage())),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部下拉识别器：列表在最顶部时，任意位置的「向下拉」都会触发刷新球。
///
/// 与 Scrollable 的垂直拖拽手势竞争。只有在列表已置顶且用户明显向下拖拽时
/// 才 accept，其他情况立即 reject，把手势还给列表滚动或子组件。
///
/// 注意：在正式 accept 之前不会调用 onMove，避免极小的手指抖动触发 setState
/// 导致顶部 tab 点击失效。
class _TopPullRecognizer extends OneSequenceGestureRecognizer {
  /// 回调：询问当前列表是否已经滚到最顶部。
  bool Function()? isAtTop;

  VoidCallback? onStart;

  /// 回调参数为「从手指按下开始的累计向下位移」，不是单帧 delta。
  ValueChanged<double>? onMove;
  VoidCallback? onEnd;

  double _dx = 0;
  double _dy = 0;
  bool _accepted = false;

  /// 向下拉多少像素后正式接管手势（要比 Scrollable 的拖拽阈值小一点）。
  static const double _acceptThreshold = 12;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _dx = 0;
    _dy = 0;
    _accepted = false;

    if (isAtTop == null || !isAtTop!()) {
      resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
      return;
    }
    onStart?.call();
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _dx += event.delta.dx;
      _dy += event.delta.dy;

      if (!_accepted) {
        if (_dy > _acceptThreshold && _dy > _dx.abs()) {
          _accepted = true;
          resolve(GestureDisposition.accepted);
          onMove?.call(_dy);
          return;
        }

        if (_dx.abs() > _acceptThreshold && _dx.abs() > _dy.abs()) {
          resolve(GestureDisposition.rejected);
          return;
        }

        return;
      }

      if (_dy > 0) {
        onMove?.call(_dy);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (!_accepted) {
        resolve(GestureDisposition.rejected);
      }
      _accepted = false;
      onEnd?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => 'top_pull';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _PinnedHeaderDelegate({required this.child});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  double get maxExtent => AppSquareTopBarTheme.height;

  @override
  double get minExtent => AppSquareTopBarTheme.height;

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}
