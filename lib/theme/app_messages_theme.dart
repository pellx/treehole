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

  /// 相对顶栏左侧按钮默认位置的水平偏移（逻辑像素）。
  /// 正数向右，负数向左；按钮的点击区域会随图标一起移动。
  static const double notificationBellOffsetX = 0;

  /// 垂直偏移（逻辑像素）：正数向下，负数向上。
  /// 调整时请让按钮保持在顶栏内，避免点击区域超出顶栏。
  static const double notificationBellOffsetY = 0;

  /// 铃铛图标和内部对勾大小（逻辑像素）。
  static const double notificationBellSize = 24;
  static const double notificationCheckSize = 11;

  /// 浅色主题。Color 使用 0xAARRGGBB，前两位控制透明度。
  static const light = AppMessagesTheme(
    notificationBellOffColor: Color(0xFF7BB380), // 未开启：较明亮的绿色
    notificationBellOnColor: Color(0x80000000), // 已开启：较暗的实心铃铛
    notificationCheckColor: Color(0xFFE8F5E9), // 已开启：内部对勾
  );

  /// 深色主题。
  static const dark = AppMessagesTheme(
    notificationBellOffColor: Color(0xFF7BB380),
    notificationBellOnColor: Color(0x80FFFFFF),
    notificationCheckColor: Color(0xFF1B2E1F),
  );

  static AppMessagesTheme forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
