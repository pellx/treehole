import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../theme/app_dimens.dart';
import '../theme/app_colors.dart';
import '../services/storage.dart';
import '../services/timezone_service.dart';
import '../services/api.dart';
import '../services/session_service.dart';
import '../pages/account/register_page.dart';
import '../pages/settings/settings_navigation.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_snackbar.dart';
import 'image_overlay.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final List<Comment> comments; // 帖子回复列表
  final VoidCallback? onNeedCommentRefresh;
  final Future<void> Function()? onRefreshPost;
  final void Function(Comment comment)? onCommentCreated; // 评论成功后直接插入
  const PostCard({
    super.key,
    required this.post,
    this.comments = const [],
    this.onNeedCommentRefresh,
    this.onRefreshPost,
    this.onCommentCreated,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _expanded = false; // 正文是否展开
  bool _hasBeenExpanded = false; // 是否曾经被展开过
  int _commentsShowCount = AppDimens.commentMaxShown; // 当前展开的回复数
  int? _expandedAuthorId; // 当前展开的回复署名 ID
  OverlayEntry? _commentOverlay; // 评论输入浮层
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  bool _commentHasAuthor = false;
  bool _commentMultiLine = false; // 多行时去掉垂直 padding
  bool _commentHadText = false; // 跟踪是否有文字（发送按钮状态）
  String? _commentAuthorHint; // 署名提示文字
  Timer? _commentAuthorTimer;
  final _commentTextFieldKey = GlobalKey(); // 保持 TextField 状态跨重建
  final _cardKey = GlobalKey(); // 卡片定位
  final _dateRowKey = GlobalKey(); // 日期行定位
  final _commentSectionKey = GlobalKey(); // 回复区域底部定位
  final _commentInputBarKey = GlobalKey(); // 输入栏定位（用于滚动对齐）
  bool _commentKeyboardVisible = false; // 跟踪键盘状态
  double _commentLastBottomInset = 0; // 上次键盘高度
  Timer? _commentScrollTimer; // 滚动对齐防抖计时器
  double _commentLastAlignedBottomInset = -1; // 上次对齐时的键盘高度

  @override
  void initState() {
    super.initState();
    widget.onNeedCommentRefresh?.call();
    _commentController.addListener(_onCommentTextChanged);
    _commentFocusNode.addListener(_onCommentFocusChanged);
  }

  void _onCommentFocusChanged() {
    if (!_commentFocusNode.hasFocus) {
      _dismissCommentOverlay();
    }
  }

  void _onCommentTextChanged() {
    final text = _commentController.text.trim();
    final hasText = text.isNotEmpty;
    final needsRebuild = hasText != _commentHadText;

    // 文本空/非空状态变化 → 重建（更新发送按钮）
    if (hasText != _commentHadText) {
      _commentHadText = hasText;
    }

    // 保存草稿
    PostStorage.saveCommentDraft(widget.post.id, _commentController.text);

    if (text.isEmpty) {
      if (_commentMultiLine || needsRebuild) {
        _commentMultiLine = false;
        _commentOverlay?.markNeedsBuild();
      }
      return;
    }

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 14, height: 1.4),
      ),
      textDirection: TextDirection.ltr,
    );
    final screenW = MediaQuery.of(context).size.width;
    final availW =
        screenW -
        AppDimens.commentInputSectionMarginBottom * 2 -
        AppDimens.commentInputAuthorBtnSize * 2 -
        AppDimens.commentInputBtnGap * 2 -
        AppDimens.commentInputPaddingH * 2;
    painter.layout(maxWidth: availW);
    final isMulti = painter.height > 19.6 * 1.2;

    if (isMulti != _commentMultiLine || needsRebuild) {
      _commentMultiLine = isMulti;
      _commentOverlay?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _commentController.removeListener(_onCommentTextChanged);
    _commentFocusNode.removeListener(_onCommentFocusChanged);
    _commentOverlay?.remove();
    _commentAuthorTimer?.cancel();
    _commentScrollTimer?.cancel();
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  String _dateTransform(String dateStr) =>
      TimezoneService.format(dateStr);

  String _timeTransform(String dateStr) =>
      TimezoneService.format(dateStr, showDate: false);

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final isLong = post.content.length > AppDimens.contentMaxLength;
    final remaining = isLong
        ? post.content.length - AppDimens.contentMaxLength
        : 0;
    final displayContent = (_expanded || !isLong)
        ? post.content
        : post.content.substring(0, AppDimens.contentMaxLength);
    final hasBody =
        post.content.isNotEmpty ||
        post.images.isNotEmpty ||
        post.attachments.isNotEmpty;

    final colors = Theme.of(context).extension<AppColors>()!;
    final primary = Theme.of(context).colorScheme.onSurface;
    final pc = colors.postCard;

    return Padding(
      key: _cardKey,
      padding: EdgeInsets.only(
        bottom: AppDimens.cardMarginBottom,
        left: AppDimens.cardLeftMargin,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: pc.cardBorder,
                width: AppDimens.cardBorderWidth,
              ),
              borderRadius: BorderRadius.circular(AppDimens.cardBorderRadius),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _titleRow(post, primary, colors),
                    if (hasBody)
                      Container(
                        height: AppDimens.cardBorderWidth,
                        color: pc.cardBorder,
                      ),
                    if (hasBody)
                      Padding(
                        padding: EdgeInsets.only(
                          left: AppDimens.cardHPadding,
                          right: AppDimens.cardHPadding,
                          top: AppDimens.cardBodySpacing,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (post.content.isNotEmpty)
                              _content(displayContent, pc),
                            if (post.images.isNotEmpty) _images(post),
                            if (post.attachments.isNotEmpty)
                              _attachments(post, colors),
                          ],
                        ),
                      ),
                  ],
                ),
                _idWidget(post, pc),
              ],
            ),
          ),
          SizedBox(height: AppDimens.dateRowTopSpacing),
          Container(
            key: _dateRowKey,
            child: _dateRow(colors, isLong, remaining),
          ),
          SizedBox(height: AppDimens.dateRowBottomSpacing),
          if (widget.comments.isNotEmpty) _commentSection(colors, primary),
        ],
      ),
    );
  }

  Widget _titleRow(post, Color primary, AppColors colors) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppDimens.cardHPadding,
        right: AppDimens.cardHPadding,
        top: AppDimens.titleVPadding,
        bottom: AppDimens.titleVPadding,
      ),
      child: _TitleAuthorRow(post: post, primary: primary, colors: colors),
    );
  }

  Widget _idWidget(post, PostCardColors pc) {
    final len = post.id.toString().length;

    final child = ColorFiltered(
      colorFilter: ColorFilter.mode(pc.idTint, BlendMode.srcIn),
      child: SizedBox(
        width: AppDimens.idImageOverlap * (len - 1) + AppDimens.idDigitWidth,
        height: AppDimens.idImageHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: List.generate(len, (i) {
            final digit = post.id.toString()[i];
            return Positioned(
              left: i * AppDimens.idImageOverlap * 1.0,
              child: Image.asset(
                'assets/numbers/$digit.png',
                width: AppDimens.idDigitWidth,
                height: AppDimens.idImageHeight,
                fit: BoxFit.fill,
                errorBuilder: (context, error, stackTrace) => Text(
                  digit,
                  style: TextStyle(
                    fontSize: AppDimens.fontSizeId,
                    color: pc.idErrorFallback,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );

    Widget content = child;
    if (AppDimens.idVertical) {
      content = RotatedBox(quarterTurns: 3, child: content);
    }

    return Positioned(
      left: AppDimens.idRight,
      top: AppDimens.idTop,
      child: content,
    );
  }

  Widget _content(String displayContent, PostCardColors pc) {
    return Text(
      displayContent,
      style: TextStyle(
        fontSize: AppDimens.fontSizeContent,
        color: pc.content,
        height: AppDimens.contentLineHeight,
      ),
    );
  }

  Widget _images(post) {
    if (post.images.isEmpty) return const SizedBox.shrink();
    final count = post.images.length;

    if (count == 1) {
      return _buildSingleImage(post);
    } else {
      return _buildGrid(post);
    }
  }

  List<GlobalKey> _gridKeys = [];
  List<GlobalKey> _singleKey = [];

  void _openOverlay(List<PostImage> images, int index, List<GlobalKey> keys) {
    if (ImageOverlay.currentEntry != null) return;
    final rects = <Rect?>[];
    for (final key in keys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) {
        rects.add(null);
        continue;
      }
      final offset = box.localToGlobal(Offset.zero);
      final size = box.size;
      rects.add(Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height));
    }
    // 确保至少有 index 对应的 rect
    while (rects.length <= index) {
      rects.add(null);
    }

    final thumbs = <Uint8List?>[];
    for (final img in images) {
      thumbs.add(PostStorage.getThumbnail(img.fileName)?.bytes);
    }

    final overlay = Overlay.of(context);
    ImageOverlay.currentEntry = OverlayEntry(
      builder: (_) {
        return ImageOverlay(
          images: images,
          initialIndex: index,
          thumbRects: rects,
          thumbnails: thumbs,
        );
      },
    );
    overlay.insert(ImageOverlay.currentEntry!);
  }

  Widget _buildSingleImage(post) {
    if (_singleKey.isEmpty) _singleKey = [GlobalKey()];
    return GestureDetector(
      onTap: () => _openOverlay(post.images, 0, _singleKey),
      child: Padding(
        padding: EdgeInsets.only(
          top: AppDimens.cardImageTop,
          bottom: AppDimens.cardImageBottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                AppDimens.singleImageMaxRatio * AppDimens.titleAuthorMaxWidth,
          ),
          child: SizedBox(
            key: _singleKey[0],
            child: ThumbnailImage(
              key: ValueKey(post.images[0].fileName),
              fileName: post.images[0].fileName,
              fit: BoxFit.contain,
              constrainSingle: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(post) {
    if (_gridKeys.length != post.images.length) {
      _gridKeys = List.generate(post.images.length, (_) => GlobalKey());
    }

    return Padding(
      padding: EdgeInsets.only(
        top: AppDimens.cardImageTop,
        bottom: AppDimens.cardImageBottom,
      ),
      child: Wrap(
        spacing: AppDimens.thumbnailGap,
        runSpacing: AppDimens.thumbnailGap,
        children: post.images.asMap().entries.take(12).map<Widget>((entry) {
          final i = entry.key;
          final img = entry.value;
          return GestureDetector(
            onTap: () => _openOverlay(post.images, i, _gridKeys),
            child: SizedBox(
              key: _gridKeys[i],
              width: AppDimens.gridImageSize,
              height: AppDimens.gridImageSize,
              child: ThumbnailImage(
                key: ValueKey(img.fileName),
                fileName: img.fileName,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _attachments(post, AppColors colors) {
    final pc = colors.postCard;
    return Padding(
      padding: EdgeInsets.only(top: AppDimens.paddingSm),
      child: Column(
        children: post.attachments.map<Widget>((att) {
          return Text(
            '📎 ${att.sourceName}',
            style: TextStyle(
              fontSize: AppDimens.fontSizeSmall,
              color: pc.attachmentText,
            ),
          );
        }).toList(),
      ),
    );
  }

  // 回复区域：无边框，默认折叠显示前 commentMaxShown 条，末尾有展开/收起文字按钮
  Widget _commentSection(AppColors colors, Color primary) {
    final pc = colors.postCard;
    final all = widget.comments;
    final showMore = all.length > _commentsShowCount;
    final hasMinus = _commentsShowCount > AppDimens.commentMaxShown;
    final visible = all.take(_commentsShowCount).toList();
    final postDay = widget.post.createdAt.length >= 10
        ? widget.post.createdAt.substring(0, 10)
        : '';

    String? lastDay;
    final rows = <Widget>[];
    for (int i = 0; i < visible.length; i++) {
      final cmtDay = visible[i].createdAt.length >= 10
          ? visible[i].createdAt.substring(0, 10)
          : '';
      if (cmtDay != postDay && cmtDay != lastDay) {
        rows.add(
          Padding(
            key: ValueKey('sep_$cmtDay'),
            padding: EdgeInsets.only(bottom: AppDimens.commentVPadding),
            child: _commentDateSeparator(visible[i].createdAt, colors),
          ),
        );
      }
      rows.add(
        Padding(
          key: ValueKey('cmt_${visible[i].id}'),
          padding: EdgeInsets.only(bottom: AppDimens.commentVPadding),
          child: _commentRow(
            visible[i],
            colors,
            primary,
            _expandedAuthorId == visible[i].id,
          ),
        ),
      );
      lastDay = cmtDay;
    }
    if (showMore || hasMinus) {
      final remain = all.length - _commentsShowCount;
      rows.add(
        Align(
          key: const ValueKey('comment_btns'),
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showMore) ...[
                Padding(
                  padding: EdgeInsets.only(
                    top: AppDimens.commentRemainTopOffset,
                  ),
                  child: Text(
                    '+$remain',
                    style: TextStyle(
                      fontSize: AppDimens.commentRemainFontSize,
                      color: pc.commentRemain,
                    ),
                  ),
                ),
                SizedBox(width: AppDimens.commentRemainBtnGap),
              ],
              if (hasMinus)
                GestureDetector(
                  onTap: () => setState(
                    () => _commentsShowCount = AppDimens.commentMaxShown,
                  ),
                  child: SvgPicture.asset(
                    'assets/minus.svg',
                    width: AppDimens.commentBtnSize,
                    height: AppDimens.commentBtnSize,
                    colorFilter: ColorFilter.mode(
                      pc.commentIcon,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              if (showMore && hasMinus)
                SizedBox(width: AppDimens.commentBtnGap),
              if (showMore)
                GestureDetector(
                  onTap: () => setState(
                    () => _commentsShowCount += AppDimens.commentStep,
                  ),
                  child: SvgPicture.asset(
                    'assets/plus.svg',
                    width: AppDimens.commentBtnSize,
                    height: AppDimens.commentBtnSize,
                    colorFilter: ColorFilter.mode(
                      pc.commentIcon,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      key: _commentSectionKey,
      margin: EdgeInsets.only(top: AppDimens.commentSectionMarginTop),
      decoration: BoxDecoration(
        color: pc.commentBg,
        borderRadius: BorderRadius.circular(AppDimens.commentBgRadius),
      ),
      padding: EdgeInsets.only(
        left: AppDimens.paddingSm,
        right: AppDimens.paddingSm,
        top: AppDimens.commentSectionTopPadding,
        bottom: AppDimens.cardBodySpacing,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }

  Widget _commentDateSeparator(String dateStr, AppColors colors) {
    final pc = colors.postCard;
    return Padding(
      padding: EdgeInsets.only(bottom: AppDimens.commentVPadding),
      child: Row(
        children: [
          Text(
            _dateOnlyTransform(dateStr),
            style: TextStyle(
              fontSize: AppDimens.commentDateFontSize,
              color: pc.commentDate,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: AppDimens.commentDateLineTopOffset),
              child: Container(height: 1, color: pc.commentDateSeparatorLine),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 评论输入覆盖层（全屏宽 + 键盘同步）----

  Widget _buildCommentOverlay() {
    return Builder(
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<AppColors>()!;
        final pc = colors.postCard;
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final safeBottom = MediaQuery.of(ctx).padding.bottom;
        final keyboardUp = bottomInset > 0;

        // 键盘高度下降 → 立即关闭输入栏
        if (_commentKeyboardVisible && bottomInset < _commentLastBottomInset) {
          _commentKeyboardVisible = false;
          _commentScrollTimer?.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _dismissCommentOverlay();
          });
        } else {
          _commentKeyboardVisible = keyboardUp;
        }

        // 键盘升起或高度变化稳定时，自动平滑滚动对齐帖子底部到输入栏上方
        if (keyboardUp && (bottomInset - _commentLastAlignedBottomInset).abs() > 1) {
          _commentScrollTimer?.cancel();
          _commentScrollTimer = Timer(const Duration(milliseconds: 60), () {
            _commentLastAlignedBottomInset = bottomInset;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToAlignPostBottom();
            });
          });
        }

        _commentLastBottomInset = bottomInset;

        return Material(
          color: Colors.transparent,
          child: Stack(
          children: [
            // 署名提示（输入栏上方）
            if (_commentAuthorHint != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: (bottomInset > 0 ? bottomInset : safeBottom + AppDimens.commentInputSectionMarginBottom)
                    + AppDimens.commentInputHeight + AppDimens.commentInputAuthorHintOffset,
                child: Center(
                  child: Text(
                    _commentAuthorHint!,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.postCreate.bottomHintText,
                    ),
                  ),
                ),
              ),
            // 输入栏贴在键盘上方
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset > 0 ? bottomInset : safeBottom + AppDimens.commentInputSectionMarginBottom,
              child: Container(
                key: _commentInputBarKey,
                color: pc.commentInputBarBg,
                padding: EdgeInsets.only(
                  left: AppDimens.commentInputSectionMarginBottom,
                  right: AppDimens.commentInputSectionMarginBottom,
                  top: AppDimens.commentInputSectionMarginTop,
                  bottom: bottomInset > 0 ? AppDimens.commentInputSectionMarginBottom : 0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: AppDimens.commentInputHeight,
                          maxHeight: AppDimens.commentInputMaxHeight,
                        ),
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: pc.commentInputFieldBg,
                                borderRadius: BorderRadius.circular(AppDimens.commentInputRadius),
                              ),
                              child: TextField(
                                  key: _commentTextFieldKey,
                                  controller: _commentController,
                                focusNode: _commentFocusNode,
                                autofocus: true,
                                minLines: 1,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                textAlignVertical: _commentMultiLine
                                    ? TextAlignVertical.top
                                    : TextAlignVertical.center,
                                style: TextStyle(
                                  fontSize: AppDimens.commentInputFontSize,
                                  color: pc.commentContent,
                                  height: 1.4,
                                ),
                                decoration: InputDecoration(
                                  hintText: '输入评论...',
                                  hintStyle: TextStyle(
                                    fontSize: AppDimens.commentInputFontSize,
                                    color: pc.commentDate,
                                    height: 1.4,
                                  ),
                                  contentPadding: _commentMultiLine
                                      ? EdgeInsets.symmetric(horizontal: AppDimens.commentInputPaddingH)
                                      : EdgeInsets.fromLTRB(
                                          AppDimens.commentInputPaddingH,
                                          10,
                                          AppDimens.commentInputPaddingH,
                                          10,
                                        ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _submitComment(),
                              ),
                            ),
                            if (!PostStorage.isRegistered())
                              Positioned.fill(
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(bottomUpRoute(const RegisterPage()));
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: pc.commentInputFieldBg,
                                      borderRadius: BorderRadius.circular(AppDimens.commentInputRadius),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    padding: _commentMultiLine
                                        ? EdgeInsets.symmetric(horizontal: AppDimens.commentInputPaddingH)
                                        : EdgeInsets.fromLTRB(
                                            AppDimens.commentInputPaddingH,
                                            10,
                                            AppDimens.commentInputPaddingH,
                                            10,
                                          ),
                                    child: Text(
                                      '目前未绑定账号，请注册',
                                      style: TextStyle(
                                        fontSize: AppDimens.commentInputFontSize,
                                        color: pc.commentDate,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: AppDimens.commentInputBtnGap),
                    _commentAuthorBtn(colors),
                    SizedBox(width: AppDimens.commentInputBtnGap),
                    _commentSendBtn(colors),
                  ],
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }


  Widget _commentAuthorBtn(AppColors colors) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _commentHasAuthor = !_commentHasAuthor;
        _commentAuthorTimer?.cancel();
        _commentAuthorHint = _commentHasAuthor ? '开启署名' : '关闭署名';
        _commentOverlay?.markNeedsBuild();
        _commentAuthorTimer = Timer(
          const Duration(milliseconds: AppDimens.commentInputAuthorHintMs),
          () {
            _commentAuthorHint = null;
            _commentOverlay?.markNeedsBuild();
          },
        );
      },
      child: Container(
        width: AppDimens.commentInputAuthorBtnSize,
        height: AppDimens.commentInputAuthorBtnSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            AppDimens.commentInputAuthorBtnRadius,
          ),
          color: _commentHasAuthor
              ? colors.postCreate.authorActiveFill
              : colors.postCreate.fieldBg,
          border: Border.all(
            color: _commentHasAuthor
                ? colors.postCreate.authorActiveFill
                : colors.postCreate.authorBorder,
            width: AppDimens.commentInputAuthorBtnBorderWidth,
          ),
        ),
        child: Icon(
          _commentHasAuthor ? Icons.person : Icons.person_outline,
          size: AppDimens.commentInputAuthorBtnIconSize,
          color: _commentHasAuthor
              ? colors.postCreate.authorActiveIcon
              : colors.postCreate.authorIcon,
        ),
      ),
    );
  }

  Widget _commentSendBtn(AppColors colors) {
    final hasText = _commentController.text.trim().isNotEmpty;
    final pc = colors.postCard;
    return GestureDetector(
      onTap: hasText ? _submitComment : null,
      child: Container(
        width: AppDimens.commentInputAuthorBtnSize,
        height: AppDimens.commentInputAuthorBtnSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            AppDimens.commentInputAuthorBtnRadius,
          ),
          color: hasText ? pc.commentSendActiveBg : pc.commentSendInactiveBg,
          border: Border.all(
            color: hasText
                ? pc.commentSendActiveBg
                : pc.commentSendInactiveBorder,
            width: AppDimens.commentInputAuthorBtnBorderWidth,
          ),
        ),
        child: Icon(
          Icons.send,
          size: AppDimens.commentInputAuthorBtnIconSize,
          color: hasText
              ? pc.commentSendActiveIcon
              : pc.commentSendInactiveIcon,
        ),
      ),
    );
  }

  /// 优先用资料里的 user_display_id，没有再回退本地昵称
  String get _commentUserName {
    final display = PostStorage.getDisplayName()?.trim();
    if (display != null && display.isNotEmpty) return display;
    return PostStorage.getUserName();
  }

  Future<void> _submitComment() async {
    HapticFeedback.mediumImpact();
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    // 回复不带 session；署名才带 user_id / author
    final userId = _commentHasAuthor ? _commentUserName : null;
    final result = await ApiService.createComment(
      postId: widget.post.id,
      content: content,
      author: userId,
      isAnonymous: !_commentHasAuthor,
      userId: userId,
    );
    if (!mounted) return;
    if (result != null) {
      _commentController.clear();
      PostStorage.clearCommentDraft(widget.post.id);
      PostStorage.saveComment(result);
      widget.onCommentCreated?.call(result);
      _dismissCommentOverlay();
      widget.onNeedCommentRefresh?.call();
    } else {
      showAppSnackBar(context, message: ApiService.lastError ?? '评论发送失败');
    }
  }

  String _dateOnlyTransform(String dateStr) =>
      TimezoneService.format(dateStr, showTime: false);

  // 单条回复行：[时间] 内容(单行截断) [署名]
  Widget _commentRow(
    Comment comment,
    AppColors colors,
    Color primary,
    bool isExpanded,
  ) {
    final pc = colors.postCard;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => _copyComment(comment),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        SizedBox(
          width: AppDimens.commentDateWidth,
          child: Text(
            _timeTransform(comment.createdAt),
            style: TextStyle(
              fontSize: AppDimens.commentDateFontSize,
              color: pc.commentDate,
            ),
          ),
        ),
        SizedBox(width: AppDimens.commentDateRightMargin),
        Expanded(
          child: Text(
            comment.content,
            maxLines: AppDimens.commentMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppDimens.commentFontSize,
              color: pc.commentContent,
              height: AppDimens.commentLineHeight,
            ),
          ),
        ),
        SizedBox(width: AppDimens.commentDateRightMargin),
        if (comment.displayAuthor.isNotEmpty)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _expandedAuthorId = isExpanded ? null : comment.id;
              });
            },
            child: SizedBox(
              width: isExpanded ? null : AppDimens.commentAuthorWidth,
              child: Text(
                comment.displayAuthor,
                maxLines: isExpanded ? 1000 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: AppDimens.commentAuthorFontSize,
                  color: pc.commentAuthor,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

  void _copyComment(Comment comment) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: comment.content));
    showAppToast(context, message: '已复制该回复');
  }

  Widget _dateRow(AppColors colors, bool isLong, int remaining) {
    final pc = colors.postCard;
    return Stack(
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(left: AppDimens.paddingSm),
          child: Text(
            _dateTransform(widget.post.createdAt),
            style: TextStyle(
              fontSize: AppDimens.fontSizeSmall,
              color: pc.dateText,
            ),
          ),
        ),
        if (isLong && !_hasBeenExpanded)
          Positioned(
            top: AppDimens.expandIconTop,
            right:
                AppDimens.commentIconRight +
                AppDimens.commentIconWidth +
                AppDimens.expandBtnDotsGap +
                AppDimens.expandIconSize +
                AppDimens.expandRemainGap,
            child: Text(
              '+$remaining',
              style: TextStyle(
                fontSize: AppDimens.fontSizeSmall,
                color: pc.commentDate,
              ),
            ),
          ),
        if (isLong)
          Positioned(
            top: AppDimens.expandIconTop,
            right:
                AppDimens.commentIconRight +
                AppDimens.commentIconWidth +
                AppDimens.expandBtnDotsGap,
            child: GestureDetector(
              onTap: () => setState(() {
                _expanded = !_expanded;
                _hasBeenExpanded = true;
              }),
              child: AnimatedRotation(
                turns: _expanded ? 0.0 : 0.5,
                duration: Duration(milliseconds: AppDimens.expandIconAnimMs),
                child: SvgPicture.asset(
                  'assets/expand_icon.svg',
                  width: AppDimens.expandIconSize,
                  height: AppDimens.expandIconSize,
                  colorFilter: ColorFilter.mode(
                    _hasBeenExpanded ? pc.expandIconGray : pc.expandIconBlue,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        // 评论图标按钮（在两点按钮左侧）
        Positioned(
          right: AppDimens.commentIconRight,
          top: AppDimens.dotsPositionedTop,
          child: Container(
            width: AppDimens.commentIconWidth,
            height: AppDimens.commentIconHeight,
            decoration: BoxDecoration(
              color: pc.dotsButtonBg,
              borderRadius: BorderRadius.circular(AppDimens.dotsBtnRadius),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.expand_less,
              size: AppDimens.commentIconSize,
              color: colors.common.onSurface,
            ),
          ),
        ),
        // 评论图标按钮扩大点击区
        Positioned(
          right: AppDimens.commentIconHitRight,
          top: AppDimens.dotsHitTop,
          child: _invisibleHitBox(
            width: AppDimens.commentIconHitWidth,
            height: AppDimens.commentIconHitHeight,
            onTap: _onComment,
          ),
        ),
        // 两点按钮
        Positioned(
          right: AppDimens.dotsPositionedRight,
          top: AppDimens.dotsPositionedTop,
          child: _dotsOnly(pc, colors.common.onSurface),
        ),
        // 两点按钮扩大点击区
        Positioned(
          right: AppDimens.dotsHitRight,
          top: AppDimens.dotsHitTop,
          child: _invisibleHitBox(
            width: isLong
                ? AppDimens.dotsHitWidthWithExpand
                : AppDimens.dotsHitWidth,
            height: AppDimens.dotsHitHeight,
            onTap: () => _showPostActionsSheet(pc),
          ),
        ),
      ],
    );
  }

  // 透明命中盒：只扩大点击区域，不参与视觉布局
  Widget _invisibleHitBox({
    required double width,
    required double height,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: Container(width: width, height: height, color: Colors.transparent),
    );
  }

  // ---- 两点按钮（点击弹出底部菜单）----

  Widget _dotsOnly(PostCardColors pc, Color dotsColor) {
    return GestureDetector(
      onTap: () => _showPostActionsSheet(pc),
      child: Container(
        width: AppDimens.dotsBtnWidth,
        height: AppDimens.dotsBtnHeight,
        decoration: BoxDecoration(
          color: pc.dotsButtonBg,
          borderRadius: BorderRadius.circular(AppDimens.dotsBtnRadius),
        ),
        child: Stack(
          children: [
            Positioned(
              top: AppDimens.dotsTopPadding,
              left: AppDimens.dotsLeftPadding,
              child: Text(
                '·',
                style: TextStyle(
                  fontSize: AppDimens.dotsFontSize,
                  fontWeight: FontWeight.bold,
                  color: dotsColor,
                ),
              ),
            ),
            Positioned(
              top: AppDimens.dotsTopPadding,
              right: AppDimens.dotsRightPadding,
              child: Text(
                '·',
                style: TextStyle(
                  fontSize: AppDimens.dotsFontSize,
                  fontWeight: FontWeight.bold,
                  color: dotsColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPostActionsSheet(PostCardColors pc) {
    HapticFeedback.lightImpact();
    showAppActionsSheet(
      context: context,
      actions: [
        AppSheetAction(
          icon: Icons.refresh,
          label: '刷新帖子',
          onTap: () {
            if (widget.onRefreshPost != null) {
              unawaited(widget.onRefreshPost!());
            }
          },
        ),
        AppSheetAction(
          icon: Icons.star_border,
          label: '收藏',
          onTap: () => showAppSnackBar(context, message: '收藏功能即将上线'),
        ),
        AppSheetAction(
          icon: Icons.report_outlined,
          label: '举报',
          onTap: () => showAppSnackBar(context, message: '举报功能即将上线'),
        ),
        AppSheetAction(
          icon: Icons.content_copy,
          label: '复制内容',
          onTap: () {
            final text = '${widget.post.title}\n${widget.post.content}';
            Clipboard.setData(ClipboardData(text: text));
            showAppSnackBar(context, message: '已复制帖子内容');
          },
        ),
      ],
    );
  }

  void _onComment() {
    HapticFeedback.lightImpact();
    if (_commentOverlay != null) {
      _dismissCommentOverlay();
      return;
    }
    // 确保有有效 session
    SessionService.instance.ensureSession();
    final overlay = Overlay.of(context);
    _commentOverlay = OverlayEntry(builder: (_) => _buildCommentOverlay());
    overlay.insert(_commentOverlay!);
    // 恢复草稿
    final draft = PostStorage.getCommentDraft(widget.post.id);
    if (draft != null && draft.isNotEmpty) {
      _commentController.text = draft;
    }
    _commentKeyboardVisible = false;
    _commentLastAlignedBottomInset = -1;
    // 先聚焦唤出键盘，再滚动对齐
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _commentOverlay == null) return;
      _commentFocusNode.requestFocus();
      // 兜底：若在部分设备或无软键盘变化场景下，延时触发对齐
      _commentScrollTimer?.cancel();
      _commentScrollTimer = Timer(const Duration(milliseconds: 250), () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToAlignPostBottom();
        });
      });
    });
  }

  void _scrollToAlignPostBottom() {
    if (!mounted || _commentOverlay == null) return;

    // 目标：帖子最底下，即回复内容展示的下面（有回复展示时为评论区底部，无回复时为日期行底部）
    final targetCtx =
        (widget.comments.isNotEmpty && _commentSectionKey.currentContext != null)
            ? _commentSectionKey.currentContext
            : _dateRowKey.currentContext;

    if (targetCtx == null || !targetCtx.mounted) return;

    final targetBox = targetCtx.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize) return;

    final scrollable = Scrollable.maybeOf(targetCtx);
    if (scrollable == null) return;

    // 目标区域底部在屏幕中的全局绝对 Y 坐标
    final targetBottom =
        targetBox.localToGlobal(Offset(0, targetBox.size.height)).dy;

    // 获取输入栏顶部在屏幕中的全局绝对 Y 坐标
    final inputBarCtx = _commentInputBarKey.currentContext;
    final double inputBarTop;
    if (inputBarCtx != null && inputBarCtx.mounted) {
      final inputBarBox = inputBarCtx.findRenderObject() as RenderBox?;
      if (inputBarBox != null && inputBarBox.hasSize) {
        inputBarTop = inputBarBox.localToGlobal(Offset.zero).dy;
      } else {
        final mq = MediaQuery.of(context);
        final bottomOccupied = max(mq.viewInsets.bottom, mq.padding.bottom);
        inputBarTop = mq.size.height -
            bottomOccupied -
            AppDimens.commentInputHeight -
            AppDimens.commentInputSectionMarginTop -
            AppDimens.commentInputSectionMarginBottom;
      }
    } else {
      final mq = MediaQuery.of(context);
      final bottomOccupied = max(mq.viewInsets.bottom, mq.padding.bottom);
      inputBarTop = mq.size.height -
          bottomOccupied -
          AppDimens.commentInputHeight -
          AppDimens.commentInputSectionMarginTop -
          AppDimens.commentInputSectionMarginBottom;
    }

    final desiredGap = AppDimens.commentInputSectionMarginBottom;
    final delta = targetBottom - (inputBarTop - desiredGap);

    if (delta.abs() > 1) {
      final newOffset = (scrollable.position.pixels + delta).clamp(
        scrollable.position.minScrollExtent,
        scrollable.position.maxScrollExtent,
      );
      scrollable.position.animateTo(
        newOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _dismissCommentOverlay() {
    _commentScrollTimer?.cancel();
    _commentLastAlignedBottomInset = -1;
    _commentOverlay?.remove();
    _commentOverlay = null;
    _commentFocusNode.unfocus();
    _commentHadText = false;
  }
}

class _TitleAuthorRow extends StatelessWidget {
  final dynamic post;
  final Color primary;
  final AppColors colors;

  const _TitleAuthorRow({
    required this.post,
    required this.primary,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final pc = colors.postCard;
    final titleStyle = TextStyle(
      fontSize: AppDimens.fontSizeTitle,
      fontWeight: FontWeight.w400,
      color: pc.title,
    );
    final authorStyle = TextStyle(
      fontSize: AppDimens.fontSizeAuthor,
      color: pc.authorName,
    );
    final atStyle = TextStyle(
      fontSize: AppDimens.fontSizeAt,
      color: pc.atSymbol,
      fontStyle: FontStyle.italic,
    );

    // 测量标题和作者宽度（标题最多2行）
    final tp = TextPainter(
      text: TextSpan(text: post.title, style: titleStyle),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout();
    final ap = TextPainter(
      text: TextSpan(text: '@${post.displayAuthor}', style: authorStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    );
    if (post.displayAuthor.isNotEmpty) ap.layout();

    final titleW = tp.width;
    final authorW = post.displayAuthor.isEmpty
        ? 0
        : ap.width + AppDimens.paddingLg;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: AppDimens.titleAuthorMaxWidth),
      child: post.displayAuthor.isEmpty
          ? Text(
              post.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            )
          : titleW + authorW <= AppDimens.titleAuthorMaxWidth
          // 不超宽：都 inline，不换行
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  post.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                SizedBox(width: AppDimens.paddingLg),
                Text('@', style: atStyle),
                SizedBox(width: AppDimens.authorAtGap),
                Text(post.displayAuthor, style: authorStyle),
              ],
            )
          // 超宽
          : () {
              final halfW = AppDimens.titleAuthorMaxWidth / 2;
              final gap = AppDimens.paddingLg;
              final bothLong = titleW > halfW && authorW > halfW;

              if (bothLong) {
                // 按比例分配：titleShare = titleW / totalW * maxWidth
                final totalW = titleW + authorW;
                final avail = AppDimens.titleAuthorMaxWidth - gap;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      flex: (titleW / totalW * avail).round().clamp(1, 999),
                      child: Text(
                        post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: titleStyle,
                      ),
                    ),
                    SizedBox(width: gap),
                    Flexible(
                      flex: (authorW / totalW * avail).round().clamp(1, 999),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '@', style: atStyle),
                            TextSpan(
                              text: post.displayAuthor,
                              style: authorStyle,
                            ),
                          ],
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                );
              } else {
                // 短的 inline，长的被约束到 maxWidth - 短宽度
                final titleLong = titleW > halfW;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (titleLong)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              AppDimens.titleAuthorMaxWidth - authorW - gap,
                        ),
                        child: Text(
                          post.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      )
                    else
                      Text(
                        post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    SizedBox(width: gap),
                    if (!titleLong)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              AppDimens.titleAuthorMaxWidth - titleW - gap,
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '@', style: atStyle),
                              TextSpan(
                                text: post.displayAuthor,
                                style: authorStyle,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '@', style: atStyle),
                            TextSpan(
                              text: post.displayAuthor,
                              style: authorStyle,
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              }
            }(),
    );
  }
}

class ThumbnailImage extends StatefulWidget {
  final String fileName;
  final BoxFit fit;
  final bool constrainSingle;
  const ThumbnailImage({
    super.key,
    required this.fileName,
    this.fit = BoxFit.cover,
    this.constrainSingle = false,
  });

  @override
  State<ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<ThumbnailImage> {
  Uint8List? _bytes;
  bool _loading = true;
  double? _displayW;
  double? _displayH;

  @override
  void initState() {
    super.initState();
    _initDims();
    _load();
  }

  void _initDims() {
    if (!widget.constrainSingle) return;
    final data = PostStorage.getThumbnail(widget.fileName);
    if (data != null) _calcDisplaySize(data);
  }

  void _calcDisplaySize(ThumbnailData data) {
    if (data.width > 0 && data.height > 0) {
      final ratio = (data.width / data.height).clamp(
        AppDimens.singleImageMinRatio,
        AppDimens.singleImageMaxRatio,
      );
      final h = sqrt(AppDimens.singleImageMaxArea / ratio);
      _displayH = h;
      _displayW = ratio * h;
    }
  }

  Future<void> _load() async {
    final cached = PostStorage.getThumbnail(widget.fileName);
    if (cached != null) {
      _calcDisplaySize(cached);
      setState(() {
        _bytes = cached.bytes;
        _loading = false;
      });
      return;
    }
    final downloaded = await ApiService.downloadThumbnail(widget.fileName);
    if (downloaded != null) {
      await PostStorage.saveThumbnail(widget.fileName, downloaded);
    }
    if (!mounted) return;
    if (downloaded != null) {
      _calcDisplaySize(downloaded);
      setState(() {
        _bytes = downloaded.bytes;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultMax = sqrt(AppDimens.singleImageMaxArea);
    if (_loading) {
      final child = const Image(
        image: AssetImage('assets/loading.gif'),
        width: AppDimens.loadingGifThumbSize,
        height: AppDimens.loadingGifThumbSize,
      );
      if (widget.constrainSingle) {
        final w = _displayW ?? defaultMax;
        final h = _displayH ?? defaultMax;
        return SizedBox(
          width: w,
          height: h,
          child: Center(child: child),
        );
      }
      return Center(child: child);
    }
    if (_bytes != null) {
      Widget img = Image.memory(_bytes!, fit: widget.fit);
      if (widget.constrainSingle) {
        final w = _displayW ?? defaultMax;
        final h = _displayH ?? defaultMax;
        img = SizedBox(width: w, height: h, child: img);
      }
      return img;
    }
    if (widget.constrainSingle) {
      return SizedBox(
        width: defaultMax,
        height: defaultMax,
        child: Image.asset('assets/404.png', fit: BoxFit.cover),
      );
    }
    return Image.asset('assets/404.png', fit: BoxFit.cover);
  }
}
