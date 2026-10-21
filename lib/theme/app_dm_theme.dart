import 'package:flutter/material.dart';

/// 私信模块的视觉参数集中在此：会话列表行、聊天页气泡、请求提示条、输入栏。
///
/// 写法与 [AppMessagesTheme] 一致：全部是 `static const`，单位均为逻辑像素
/// （Flutter 的 dp，会按屏幕像素密度自动换算）。只改这里的数值即可调整外观，
/// 不需要动布局代码；深浅色差异用 `xxxAlpha` 控制透明度，颜色本身跟随主题。
class AppDmTheme {
  const AppDmTheme._();

  // ===== 会话行：整体尺寸 =====

  /// 会话行左右到屏幕边缘的距离。
  static const double conversationHorizontalPadding = 16;

  /// 会话行内部的上下留白。
  static const double conversationVerticalPadding = 14;

  /// 会话行的最小高度；首行不参与最小高度，避免和上方按钮区重叠。
  static const double conversationMinHeight = 80;

  /// 会话行底部细分隔线的高度与粗细。
  static const double dividerHeight = 1;
  static const double dividerThickness = 0.5;

  /// 置顶会话的背景色透明度（0~1，越大越明显）。
  static const double pinnedBackgroundAlpha = 0.06;

  // ===== 会话行：头像与文字 =====

  /// 头像直径；实际传给 UserAvatar 的 radius 是它的一半。
  static const double avatarSize = 46;

  /// 头像与右侧文字区的水平间距。
  static const double avatarGap = 16;

  /// 昵称字号。
  static const double titleFontSize = 17;

  /// 最近一条消息摘要的字号。
  static const double previewFontSize = 14;

  /// 摘要单行显示的最大宽度，超出显示省略号。
  static const double previewMaxWidth = 220;

  /// 右侧相对时间的字号。
  static const double timeFontSize = 11;

  /// 相对时间的最大宽度，超出显示省略号。
  static const double timeMaxWidth = 80;

  /// 昵称行与摘要行的垂直间距。
  static const double textGap = 5;

  // ===== 会话行：功能标记 =====

  /// 置顶小图标的尺寸与它到昵称的间距。
  static const double pinIconSize = 13;
  static const double pinIconGap = 5;

  /// 免打扰小图标的尺寸与它前面的间距。
  static const double muteIconSize = 13;
  static const double muteIconGap = 8;

  /// 昵称与右侧时间之间的最小间距。
  static const double timeGap = 12;

  /// 未读角标前的间距。
  static const double unreadGap = 10;

  /// 未读数字角标的边长；单红点模式用 unreadDotSize。
  static const double unreadBadgeSize = 18;
  static const double unreadDotSize = 7;

  /// 未读数字的字号。
  static const double unreadBadgeFontSize = 10;

  // ===== 会话行：「请求」标签 =====

  /// 「请求」二字的字号。
  static const double requestTagFontSize = 10;

  /// 标签内部的左右/上下留白。
  static const double requestTagHorizontalPadding = 5;
  static const double requestTagVerticalPadding = 1;

  /// 标签圆角半径。
  static const double requestTagRadius = 4;

  /// 标签与昵称之间的间距。
  static const double requestTagGap = 6;

  /// 标签底色的透明度（主色叠加，深浅色都适用）。
  static const double requestTagBackgroundAlpha = 0.12;

  // ===== 会话行：同意 / 拒绝按钮 =====

  /// 按钮最小高度（会压缩点击热区，保持在一行内）。
  static const double requestButtonMinHeight = 28;

  /// 按钮内部左右留白。
  static const double requestButtonHorizontalPadding = 8;

  /// 按钮文字字号。
  static const double requestButtonFontSize = 12;

  /// 「拒绝」与「同意」之间的间距。
  static const double requestButtonGap = 6;

  // ===== 聊天页：消息列表 =====

  /// 消息列表整体内边距。
  static const double messageListPadding = 16;

  /// 气泡最大宽度占屏幕宽度的比例（0~1）。
  static const double bubbleMaxWidthRatio = 0.78;

  /// 相邻气泡之间的垂直间距。
  static const double bubbleBottomGap = 12;

  /// 气泡内部四周留白。
  static const double bubblePadding = 12;

  /// 气泡圆角半径。
  static const double bubbleRadius = 12;

  /// 自己发送的气泡底色透明度（主色叠加）。
  static const double bubbleMineAlpha = 0.16;

  /// 气泡内头像半径。
  static const double bubbleAvatarRadius = 16;

  /// 气泡内头像与正文的间距。
  static const double bubbleAvatarGap = 6;

  /// 私信正文字号。
  static const double messageTextFontSize = 15;

  /// 气泡底部时间的字号与它上方的间距。
  static const double bubbleTimeFontSize = 11;
  static const double bubbleTimeGap = 4;

  /// 发送失败感叹号图标的尺寸。
  static const double failedIconSize = 20;

  /// 气泡内头像与失败图标共用的圆角/间距留白。
  static const double bubbleInnerGap = 6;

  /// 空会话（还没消息）时的占位文字字号。
  static const double emptyChatFontSize = 14;

  /// 「加载更早消息」按钮的文字字号。
  static const double loadOlderFontSize = 14;

  // ===== 聊天页：请求提示条 =====

  /// 提示条外层外边距：左、右。
  static const double bannerHorizontalMargin = 12;

  /// 提示条到输入区/页面底部的距离。
  static const double bannerBottomMargin = 8;

  /// 提示条内部四周留白。
  static const double bannerPadding = 12;

  /// 提示条圆角半径。
  static const double bannerRadius = 12;

  /// 提示条底色的透明度（主色叠加）。
  static const double bannerBackgroundAlpha = 0.08;

  /// 提示文字字号。
  static const double bannerTextFontSize = 14;

  /// 提示条内按钮文字字号。
  static const double bannerButtonFontSize = 14;

  /// 提示文字与下方按钮行的间距。
  static const double bannerActionTopGap = 8;

  /// 「拒绝」「同意」两个按钮之间的间距。
  static const double bannerButtonGap = 8;

  /// 提示条内按钮的最小高度。
  static const double bannerButtonMinHeight = 36;

  // ===== 聊天页：输入栏 =====

  /// 输入栏外层内边距：左、上、右、下。
  static const double composerHorizontalPadding = 12;
  static const double composerTopPadding = 8;
  static const double composerBottomPadding = 12;

  /// 输入框与「发送」按钮之间的间距。
  static const double composerSendGap = 8;

  /// 输入框最少/最多显示行数。
  static const int composerMinLines = 1;
  static const int composerMaxLines = 4;

  /// 单条消息最大字数（与后端校验一致，改这里会误导用户，一般不要动）。
  static const int composerMaxLength = 2000;

  /// 输入框与「发送」按钮的文字字号。
  static const double composerFontSize = 15;
  static const double composerSendFontSize = 14;

  // ===== 列表页：空状态与加载 =====

  /// 空状态内容距列表顶部的距离。
  static const double emptyTopPadding = 48;

  /// 空状态文字与下方按钮的间距。
  static const double emptyTextGap = 12;

  /// 「加载更多会话」按钮文字字号。
  static const double loadMoreFontSize = 14;

  /// 列表页叠加的加载遮罩透明度（0~1）。
  static const double loadingOverlayAlpha = 0.2;

  /// 半透明加载遮罩的颜色（黑底 + loadingOverlayAlpha）。
  static const Color loadingOverlayColor = Color(0x33000000);
}
