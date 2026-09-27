import 'package:flutter/material.dart';

/// 头像裁剪页配色：直接修改下方 light / dark，Android 和 iOS 共用。
/// Color 使用 0xAARRGGBB 格式；FF 表示不透明。
class AvatarCropperTheme {
  final Color background;
  final Color toolbar;
  final Color foreground;
  final Color accent;
  final Color dimmedLayer;
  final Color cropFrame;
  final Color cropGrid;

  const AvatarCropperTheme({
    required this.background,
    required this.toolbar,
    required this.foreground,
    required this.accent,
    required this.dimmedLayer,
    required this.cropFrame,
    required this.cropGrid,
  });

  static const light = AvatarCropperTheme(
    background: Color(0xFFFFFFFF), // 页面背景
    toolbar: Color(0xFFFFFFFF), // 工具栏背景
    foreground: Color(0xFF333333), // 标题、普通文字和图标
    accent: Color(0xFF0EAB00), // 主题绿：选中控件、iOS 完成按钮
    dimmedLayer: Color(0xBFFFFFFF), // 裁剪区域外的遮罩
    cropFrame: Color(0xFF0EAB00), // Android 裁剪框
    cropGrid: Color(0x80FFFFFF), // Android 辅助线
  );

  static const dark = AvatarCropperTheme(
    background: Color(0xFF191919),
    toolbar: Color(0xFF222222),
    foreground: Color(0xFFD3D3D3),
    accent: Color(0xFF5EED6F),
    dimmedLayer: Color(0xBF191919),
    cropFrame: Color(0xFF5EED6F),
    cropGrid: Color(0x80FFFFFF),
  );

  static AvatarCropperTheme forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
