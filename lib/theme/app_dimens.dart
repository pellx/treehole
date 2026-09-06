class AppDimens {
  const AppDimens._();

  // ---- 间距 ----
  static const double spacingXs = 2;
  static const double paddingXs = 2;
  static const double paddingSm = 4;
  static const double paddingMd = 8;
  static const double paddingLg = 4;
  static const double paddingXl = 24;

  // ---- 主页发布入口（右下角）----
  static const double postCreateButtonSize = 52; // 按钮宽高
  static const double postCreateButtonRight = 20; // 距右边距
  static const double postCreateButtonBottom = 20; // 距底边距
  static const double postCreateButtonRadius = 26; // 按钮圆角
  static const double postCreateButtonIconSize = 28; // 图标大小

  // ---- 发布页整页 ----
  static const double postCreatePagePadding = 12; // 整页左右边距（控制输入区和按钮行距屏幕距离）
  static const double postCreateSectionGap = 12; // 各部分间距
  static const double postCreateSubmitMarginRight = 20; // 发布按钮距右边距
  static const int postCreateErrorDismissMs = 3000; // 错误提示自动消失时长（毫秒）
  static const int postCreateToastDismissMs = 500; // 署名切换提示消失时长（毫秒）

  // ---- 第一部分：椭圆输入区 ----
  static const double postCreateInputRadius = 8;
  static const double postCreateInputBorderWidth = 0;
  static const double postCreateInputPaddingH = 10;
  static const double postCreateInputPaddingV = 6;
  static const double postCreateDividerThickness = 1;
  static const double postCreateDividerIndent = 2;
  static const double postCreateTitleMinHeight = 48;
  static const double postCreateContentMinHeight = 160;
  static const double postCreateContentMaxHeight = 280;

  // ---- Floating label（标题）----
  static const double postCreateLabelFontSizeLarge = 16;
  static const double postCreateLabelFontSizeSmall = 12;
  static const double postCreateLabelRestDx = 0;
  static const double postCreateLabelRestDy = 15;
  static const double postCreateLabelFloatDx = 0;
  static const double postCreateLabelFloatDy = -8;
  static const int postCreateLabelAnimMs = 170;

  // ---- Floating label（内容）----
  static const double postCreateContentLabelFontSizeLarge = 16;
  static const double postCreateContentLabelFontSizeSmall = 12;
  static const double postCreateContentLabelRestDx = 0;
  static const double postCreateContentLabelRestDy = -32;
  static const double postCreateContentLabelFloatDx = 0;
  static const double postCreateContentLabelFloatDy = -8;
  static const int postCreateContentLabelAnimMs = 170;

  // ---- 第二部分：按钮行 ----
  static const double postCreateButtonRowPaddingH = 16; // 按钮行距屏幕左右距离（可单独控制）
  static const double postCreateActionRowGap = 4; // 按钮之间水平间距
  static const double postCreatePreviewGap = 8; // 预览区与按钮行间距
  static const double postCreatePreviewThumbSize = 77; // 预览缩略图大小
  static const double postCreatePreviewDividerHeight = 1; // 预览区下方横线高度

  // 上传 / 清除按钮（统一样式）
  static const double postCreateActionButtonSize = 35; // 上传 & 清除按钮宽高（正方形）
  static const double postCreateActionButtonRadius = 8; // 上传 & 清除按钮圆角
  static const double postCreateActionButtonIconSize = 20; // 上传 & 清除按钮图标大小
  static const double postCreateActionButtonBorderWidth = 1.8; // 上传 & 清除按钮描边粗细

  // 展开按钮（样式与上传/清除一致）
  static const double postCreateExpandButtonSize = 35; // 展开按钮宽高
  static const double postCreateExpandButtonRadius = 8; // 展开按钮圆角
  static const double postCreateExpandButtonBorderWidth = 1.8; // 展开按钮描边粗细
  static const double postCreateExpandButtonIconSize = 20; // 展开图标大小
  static const int postCreateExpandThresholdChars = 80; // 展开按钮出现阈值（字符数）

  // 署名按钮（图标样式，启用/未启用两态）

  // ---- 署名切换按钮（旧自定义开关，已弃用）----
  static const double postCreateAuthorSwitchWidth = 54;
  static const double postCreateAuthorSwitchHeight = 30;
  static const double postCreateAuthorSwitchRadius = 999;
  static const double postCreateAuthorSwitchPadding = 3;
  static const double postCreateAuthorSwitchThumbSize = 24;
  static const double postCreateAuthorSwitchIconSize = 14;

  // ---- 第三部分：发布按钮 ----
  static const double postCreateSubmitHeight = 28; // 按钮高度
  static const double postCreateSubmitRadius = 8; // 按钮圆角
  static const double postCreateSubmitHPadding = 11; // 按钮水平内边距
  static const double postCreateSubmitFontSize = 14; // 按钮文字大小

  // ---- 内容展开覆盖层 ----
  static const double postCreateContentExpandedTopGap = -40; // 完全展开后顶部保留高度
  static const double postCreateContentExpandedPadding = 12; // 展开卡片内部边距
  static const double postCreateContentExpandedRadius = 8; // 展开卡片圆角
  static const double postCreateContentExpandedTextHPadding = 4; // 展开后文本左右内边距
  static const double postCreateContentExpandedTextTopStart =
      19; // 展开/收起时文本距顶部起始/终点值
  static const double postCreateContentExpandedTextLeftStart =
      10; // 文本距左边起始值（展开起点/收起终点，匹配原位）
  static const double postCreateContentExpandedTextLeftEnd =
      12; // 文本距左边终点值（展开终点/收起起点）
  static const double postCreateContentOverlayOpacity = 0.8; // 展开时遮罩最大透明度
  static const double postCreateContentCollapseWidthSwitchT =
      0.15; // 收起到此进度后切回原文本宽度
  static const int postCreateContentExpandAnimMs = 300; // 展开/收起动画时长
  static const double postCreateContentCollapseIconSize = 28; // 收起图标大小

  // ---- 帖子卡片 ----
  static const double cardHPadding = 7;
  static const double cardContentLeft = 7;
  static const double cardImageTop = 2;
  static const double cardImageBottom = 7;
  static const double cardBodySpacing = 2;
  static const double cardMarginBottom = 28;
  static const double cardLeftMargin = 22;
  static const double cardBorderRadius = 8;
  static const double cardBorderWidth = 1.7;
  static const double cardBorderOpacity = 0.18; // 卡片边框透明度

  // ---- 标题区域 ----
  static const double titleVPadding = 3;
  static const double idTitleGap = 8;

  // ---- 装饰引号 ----
  static const double quoteTop = -20;
  static const double quoteLeft = -22;
  static const double quoteBottom = -10;
  static const double quoteRight = -21;
  static const double quoteOpacity = 0.4;

  // ---- 帖子 ID ----
  static const double idRight = -32;
  static const double idTop = -2;
  static const double idOpacity = 0.36;
  static const double idImageHeight = 32;
  static const double idImageOverlap = 15;
  static const double idDigitWidth = 23;
  static const bool idVertical = true;
  static const double idGradientStopTop = 0.0;
  static const double idGradientStopMid = 0.5;
  static const double idGradientStopBottom = 1.0;

  // ---- 文字 ----
  static const double fontSizeQuote = 57;
  static const double fontSizeId = 40;
  static const double fontSizeTitle = 18;
  static const double fontSizeAt = 15;
  static const double fontSizeContent = 15;
  static const double fontSizeAuthor = 18;
  static const double titleAuthorMaxWidth = 282;
  static const double authorAtGap = 3;
  static const double fontSizeSmall = 14;

  // ---- 内容 ----
  static const int contentMaxLength = 256;

  // ---- 缩略图 ----
  static const double singleImageMaxArea = 40000;
  static const double singleImageMinRatio = 0.25;
  static const double singleImageMaxRatio = 4.0;
  static const double gridImageSize = 92;
  static const double thumbnailGap = 4;

  // ---- 展开/收起按钮 ----
  static const double expandBtnDotsGap = 2;
  static const double expandRemainGap = 4; // 展开按钮与 +N 间距
  static const double expandIconSize = 27;
  static const double expandIconCornerRadius = 3;
  static const int expandIconAnimMs = 0;
  static const double expandIconTop = -4;
  static const double expandIconGrayAlpha = 0.13;

  // ---- 内容文字 ----
  static const double contentLineHeight = 1.5;

  // ---- 两个点按钮（操作菜单触发器）----
  static const double dotsBtnWidth = 26;
  static const double dotsBtnHeight = 15;
  static const double dotsBtnRadius = 4;
  static const double dotsBtnBorderWidth = 0.5;
  static const double dotsFontSize = 18;
  static const double dotsGap = -20;
  static const double dotsTopPadding = -5.2;
  static const double dotsLeftPadding = 5;
  static const double dotsRightPadding = 5;
  static const double dotsBgOpacity = 0.09;
  static const double commentBgOpacity = 0.09; // 回复区域背景透明度
  static const double dotsPositionedRight = 1;
  static const double dotsPositionedTop = 2;
  // 两点按钮放大点击区（宽度48/有展开按钮时收窄为33，避免压住展开图标）
  static const double dotsHitWidth = 48;
  static const double dotsHitWidthWithExpand = 33;
  static const double dotsHitHeight = 24; // 日期行高度需不低于此值，超出部分下方延伸
  static const double dotsHitRight = -4;  // 向右略入卡片内边距
  static const double dotsHitTop = 0;

  // ---- 评论图标按钮（在两点按钮左侧，用于唤出回复栏）----
  static const double commentIconSize = 16; // V 形图标大小
  static const double commentIconWidth = 26; // 容器宽度（与两点按钮一致）
  static const double commentIconHeight = 15; // 容器高度（与两点按钮一致）
  static const double commentIconGap = 8; // 与两点按钮间距
  static const double commentIconRight = dotsPositionedRight + dotsBtnWidth + commentIconGap;
  static const double commentIconHitWidth = 34; // 透明点击区宽度
  static const double commentIconHitHeight = dotsHitHeight;
  static const double commentIconHitRight = commentIconRight; // 右对齐，避免侵入 .. 点击区

  // ---- 操作浮层（从两点按钮上方弹出）----
  static const double actionMenuBtnWidth = 50;               // 操作图标容器宽度
  static const double actionMenuBtnHeight = 30;              // 操作图标容器高度
  static const double actionMenuBtnGap = 4;                  // 图标间距
  static const double actionMenuBtnRadius = 4;               // 图标圆角
  static const double actionMenuIconSize = 18;               // 图标大小（宽=高）
  static const double actionMenuIconSizeFavorite = 14;       // 收藏图标
  static const double actionMenuIconSizeComment = 15;        // 评论图标
  static const double actionMenuIconSizeReport = 16;         // 举报图标
  static const double actionMenuBoxHeight = 24;        // 方框高度
  static const double actionMenuBoxTopOffset = -1;     // 方框顶部相对按钮顶部偏移
  static const double actionMenuBoxRightOffset = -28;    // 方框右边缘相对按钮右边缘偏移
  static const double actionMenuShadowBlur = 6;        // 阴影模糊半径
  static const double actionMenuShadowOpacity = 1;  // 阴影透明度
  static const double actionMenuShadowOffsetY = 2;     // 阴影Y偏移

  // ---- 时间行 ----
  static const double dateRowTopSpacing = 2;
  static const double dateRowBottomSpacing = 0; // 已并入日期行高度，减少额外空隙

  // ---- 列表 ----
  static const double listPaddingLeft = 12;
  static const double listPaddingTop = 24;
  static const double listPaddingRight = 12;
  static const double listPaddingBottom = 40;

  // ---- 加载动画 ----
  static const double loadingGifSize = 40;
  static const double loadingGifThumbSize = 24;

  // ---- 下拉刷新 ----
  static const double refreshIndicatorDisplacement = 2.0; // 下拉位移（0=不推内容）
  static const double drawerEdgeDragWidth = 50.0; // 左滑唤出抽屉灵敏度
  static const int drawerAnimMs = 300; // 抽屉动画时长(ms)
  static const double drawerAvatarSize = 56; // 抽屉头像大小
  static const double drawerHeaderPaddingLeft = 16; // 头部左间距
  static const double drawerHeaderPaddingRight = 16; // 头部右间距
  static const double drawerHeaderPaddingTop = 50; // 头部上间距
  static const double drawerHeaderPaddingBottom = 20; // 头部下间距
  static const double drawerAvatarTextGap = 12; // 头像与名字间距
  static const double drawerNameFontSize = 16; // 名字字号

  static const double settingsBarHeight = 48; // 设置页顶部栏高度
  static const double settingsItemFontSize = 16; // 设置项字号
  static const double settingsItemHeight = 60; // 设置项行高
  static const double settingsArrowRightMargin = 17; // 箭头距右侧距离
  static const double settingsArrowSize = 21; // 箭头图标大小



  // ---- 图片查看器操作栏 ----

  // ---- 图片查看器动画 ----
  static const int imageExpandMs = 250; // 打开/关闭伸缩动画时长
  static const int imageFadeMs = 500; // WebP 淡出时长
  static const double pageSnapMass = 0.2; // 切页弹簧质量（越小越快）
  static const double pageSnapStiffness = 100; // 切页弹簧刚度（越大越快）
  static const double pageSnapDampingRatio =
      1.4; // 切页阻尼比（0.9=稍有回弹, 1.0=临界无回弹, 1.1=柔和减速）
  static const double bounceMass = 0.2; // 溢出回弹弹簧质量（越小越快）
  static const double bounceStiffness = 300; // 溢出回弹弹簧刚度（越大越快）
  static const double bounceDampingRatio = 1.4; // 溢出回弹阻尼比

  // ---- 长按操作栏 ----
  static const double actionBarHeight = 48; // 操作栏高度
  static const double actionBarRadius = 12; // 操作栏圆角
  static const double actionBarBottomMargin = 60; // 距底部距离
  static const double actionBarBtnSize = 28; // 按钮图标大小
  static const int actionBarAnimMs = 80; // 操作栏显示动画时长
  static const int actionBarCloseAnimMs = 80; // 操作栏隐藏动画时长
  static const double actionBarBtnGap = 40; // 两按钮间距

  // ---- 保存提示弹窗 ----
  static const double saveToastRadius = 5; // 弹窗圆角
  static const double saveToastHPadding = 24; // 弹窗水平内边距
  static const double saveToastVPadding = 10; // 弹窗垂直内边距
  static const double saveToastBottomMargin = 112; // 距底部距离
  static const double saveToastFontSize = 14; // 文字大小
  static const int saveToastDurationMs = 1500; // 显示时长
  static const int saveToastAnimMs = 80; // 动画时长

  // ---- 回复 ----
  static const double commentFontSize = 14; // 回复内容字号
  static const double commentDateFontSize = 14; // 回复日期字号
  static const double commentAuthorFontSize = 14; // 回复署名字号
  static const int commentMaxLines = 1000; // 回复内容最大行数
  static const int commentMaxShown = 3; // 折叠时最多显示条数
  static const int commentStep = 3; // 每次点击 + 增加的条数
  static const double commentLineHeight = 1.4; // 回复内容行高
  static const double commentVPadding = 0; // 回复条间距
  static const double commentDateWidth = 46; // 日期列宽
  static const double commentDateRightMargin = 0; // 日期右侧间距
  static const double commentAuthorWidth = 52; // 署名列宽
  static const double commentSectionTopPadding = 2; // 回复区域内顶部间距
  static const double commentDateLineTopOffset = 9; // 日期分隔横线竖直偏移
  static const double commentSectionMarginTop = 0; // 回复区域距上方日期行间距
  static const double commentBgRadius = 4; // 回复区域背景圆角
  static const double commentBtnSize = 18; // +/- 按钮大小
  // +/- 按钮透明点击区高度：按钮 18 + 向上延伸 4 + 向下覆盖底部内边距 2
  static const double commentBtnHitHeight = 24;
  static const double commentBtnGap = 2; // +/- 按钮间距
  static const double commentRemainFontSize = 12; // 剩余回复数字号
  static const double commentRemainTopOffset = 0; // 剩余回复数竖直偏移
  static const double commentRemainBtnGap = 6; // +N 与 [-] 间距
  static const double commentScrollBottomOffset = 63; // 有评论时，滚动定位评论区底部距视口底部偏移
  static const double dateRowScrollBottomOffset = 56;  // 无评论时，滚动定位日期行底部距视口底部偏移

  // ---- 评论输入栏 ----
  static const double commentInputHeight = 40; // 输入栏最小高度
  static const double commentInputMaxHeight = 120; // 输入栏最大高度（超出后滚动）
  static const double commentInputRadius = 8; // 输入框圆角
  static const double commentInputPaddingH = 12; // 输入框水平内边距
  static const double commentInputFontSize = 14; // 输入字号
  static const double commentInputAuthorBtnSize = 35; // 署名按钮宽高
  static const double commentInputAuthorBtnRadius = 8; // 署名按钮圆角
  static const double commentInputAuthorBtnBorderWidth = 1.8; // 署名按钮描边
  static const double commentInputAuthorBtnIconSize = 20; // 署名按钮图标大小
  static const double commentInputBtnGap = 8; // 输入框与按钮间距
  static const double commentInputSectionMarginTop = 8; // 输入栏距上方间距
  static const double commentInputSectionMarginBottom = 8; // 输入栏距下方评论区间距
  static const double commentInputAuthorHintOffset = 16; // 署名提示距输入栏高度
  static const int commentInputAuthorHintMs = 1500; // 署名提示显示时长(ms)

  static const double pageIndicatorDotSize = 6; // 圆点大小
  static const double pageIndicatorDotGap = 8; // 圆点间距
  static const double pageIndicatorActiveOpacity = 0.9; // 当前页透明度
  static const double pageIndicatorInactiveOpacity = 0.4; // 非当前页透明度
  static const double pageIndicatorBottomMargin = 40; // 距底部距离
  static const int pageIndicatorFadeMs = 80; // 页码指示器消失动画时长

  // ---- 图片查看器页码点透明度（image_overlay.dart 引用名）----
  static const double overlayPageDotActiveOpacity = 0.9;
  static const double overlayPageDotInactiveOpacity = 0.4;

  // ---- 版本更新提示箭头 ----
  static const double updateArrowSize = 14;

  // ---- 版本卡片 ----
  static const double versionCardBottomMargin = 10;
  static const double versionCardVersionFontSize = 19;
  static const double versionCardBadgeGap = 7;
  static const double versionCardBadgeHPadding = 4;
  static const double versionCardBadgeVPadding = 1;
  static const double versionCardBadgeRadius = 4;
  static const double versionCardBadgeFontSize = 12;
  static const double versionCardRowToBoxGap = 5;
  static const double versionCardVersionPaddingLeft = 7;
  static const double versionCardBoxPadding = 8;
  static const double versionCardTitleFontSize = 18;
  static const double versionCardLogFontSize = 14;
  static const double versionCardTitleLogGap = 2;
  static const double versionCardTitlePaddingLeft = 1;
  static const double versionCardLatestBorderWidth = 1.5;
  static const double versionCardMaxHeight = 131;
  static const int versionCardLogMaxLines = 4;
}
