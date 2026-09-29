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

  /// 顶栏。颜色沿用旧版浅绿/深绿；所有尺寸单位为逻辑像素。
  static const Color headerBackgroundLight = Color(0xFFE8F5E9);
  static const Color headerBackgroundDark = Color(0xFF1B2E1F);
  static const double headerHeight = 48;
  static const double headerTitleOffsetY = 0;
  static const double headerActionIconSize = 24;
  static const double clearUnreadOffsetY = 0;
  static const double moreActionsOffsetY = 0;

  /// 三个系统入口的纵向留白。
  static const double shortcutHorizontalPadding = 24;
  static const double shortcutTopPadding = 12;
  static const double shortcutBottomPadding = 12;
  static const double shortcutItemVerticalPadding = 2;
  static const double shortcutSize = 56;
  static const double shortcutRadius = 16;
  static const double shortcutIconSize = 29;
  static const double shortcutLabelGap = 6;
  static const double shortcutLabelFontSize = 14;

  /// 私信会话行的高度与内部纵向间距。
  static const double conversationMinHeight = 68;
  static const double conversationHorizontalPadding = 16;
  static const double conversationVerticalPadding = 10;
  static const double conversationAvatarSize = 46;
  static const double conversationAvatarGap = 16;
  static const double conversationTitleFontSize = 17;
  static const double conversationPreviewFontSize = 14;
  static const double conversationTimeFontSize = 11;
  static const double conversationTextGap = 3;
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
  static const Color shortcutBackgroundLight = Color(0xFFF5F6F7);
  static const Color shortcutBackgroundDark = Color(0xFF222222);
  static const Color secondaryLight = Color(0xFF747474);
  static const Color secondaryDark = Color(0xFF888888);
  static const Color dividerLight = Color(0xFFEDEDED);
  static const Color dividerDark = Color(0xFF2C2C2C);
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
