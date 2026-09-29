import 'package:flutter/material.dart';

/// 消息页通知铃铛样式：位置、大小和浅色/深色配色集中在此调整。
class AppMessagesTheme {
  final Color notificationBellOffColor;
  final Color notificationBellOnColor;
  final Color notificationCheckColor;

  const AppMessagesTheme({
    required this.notificationBellOffColor,
    required this.notificationBellOnColor,
    required this.notificationCheckColor,
  });

  /// 顶栏默认与消息列表使用同一背景色。所有距离单位均为逻辑像素。
  static const Color headerBackgroundLight = backgroundLight;
  static const Color headerBackgroundDark = backgroundDark;
  static const double headerHeight = 48;
  static const double headerTitleOffsetY = 0;
  static const double headerActionIconSize = 24;
  static const double clearUnreadOffsetY = 0;
  static const double moreActionsOffsetY = 0;

  /// 三个按钮区域左右两侧到屏幕边缘的距离。
  static const double shortcutHorizontalPadding = 24;

  /// 顶栏下沿到三个按钮区域上沿的距离。
  static const double shortcutTopPadding = 22;

  /// 三个按钮区域（含文字）到第一条用户会话的距离；减小可让两者更靠近。
  static const double shortcutBottomPadding = 26;

  /// 每个按钮内部的上下留白。
  static const double shortcutItemVerticalPadding = 2;

  /// 三个按钮图标底板的宽高。
  static const double shortcutSize = 56;

  /// 图标底板的圆角。
  static const double shortcutRadius = 16;

  /// 按钮图标大小。
  static const double shortcutIconSize = 29;

  /// 图标底板与“回复／公告／审核”文字的距离。
  static const double shortcutLabelGap = 9;

  /// 三个按钮下方文字的字号。
  static const double shortcutLabelFontSize = 14;
  static const double conversationMinHeight = 80;
  static const double conversationHorizontalPadding = 16;

  /// 会话行内的上下留白；首条头像和文字与三个按钮的视觉距离也会受它影响。
  static const double conversationVerticalPadding = 14;
  static const double conversationAvatarSize = 46;
  static const double conversationAvatarGap = 16;
  static const double conversationTitleFontSize = 17;
  static const double conversationPreviewFontSize = 14;

  /// 最后一条消息摘要的最大显示宽度；超出部分单行省略。
  static const double conversationPreviewMaxWidth = 220;
  static const double conversationTimeFontSize = 11;
  static const double conversationTextGap = 5;
  static const double conversationTimeMaxWidth = 80;
  static const double conversationDividerIndent =
      conversationHorizontalPadding +
      conversationAvatarSize +
      conversationAvatarGap;
  static const double unreadBadgeSize = 18;
  static const double unreadDotSize = 7;
  static const double unreadBadgeFontSize = 10;

  static const Color backgroundLight = Color(0xFFFFFFFF);
  static const Color backgroundDark = Color(0xFF191919);

  /// 三个按钮图标底板在浅色和深色模式下的颜色。
  static const Color shortcutBackgroundLight = Color(0xFFF5F6F7);
  static const Color shortcutBackgroundDark = Color(0xFF222222);
  static const Color secondaryLight = Color(0xFF747474);
  static const Color secondaryDark = Color(0xFF888888);
  static const Color dividerLight = Color(0xFFEDEDED);
  static const Color dividerDark = Color(0xFF2C2C2C);

  /// “回复”“公告”“审核”图标的颜色。
  static const Color replyIconColor = Color(0xFF43AE8A);
  static const Color announcementIconColor = Color(0xFFE5A14A);
  static const Color moderationIconColor = Color(0xFF399DCD);
  static const Color unreadColor = Color(0xFFE7444B);

  /// 相对顶栏左侧按钮默认位置的水平偏移（逻辑像素）。
  /// 正数向右，负数向左；按钮的点击区域会随图标一起移动。
  static const double notificationBellOffsetX = 10;

  /// 垂直偏移（逻辑像素）：正数向下，负数向上。
  /// 调整时请让按钮保持在顶栏内，避免点击区域超出顶栏。
  static const double notificationBellOffsetY = 0;

  /// 铃铛图标和内部对勾大小（逻辑像素）。
  static const double notificationBellSize = 24;
  static const double notificationCheckSize = 11;

  /// 浅色主题。Color 使用 0xAARRGGBB，前两位控制透明度。
  static const light = AppMessagesTheme(
    notificationBellOffColor: Color(0xCA000000),
    notificationBellOnColor: Color(0xA77BB380),
    notificationCheckColor: Color(0xFFE8F5E9), // 已开启：内部对勾
  );

  /// 深色主题。
  static const dark = AppMessagesTheme(
    notificationBellOffColor: Color(0x80FFFFFF),
    notificationBellOnColor: Color(0xA77BB380),
    notificationCheckColor: Color(0xFF1B2E1F),
  );

  static AppMessagesTheme forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
