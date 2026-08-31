import 'package:flutter/material.dart';

/// 手机号验证码页（sms_login / sms_register）全部样式参数。
///
/// 这两页是系统默认路由推入的正式子页（官方「手机号登录」样式）：
/// 白底、左对齐大标题 + 灰色副标题、圆角描边输入框、大号圆角主按钮。
/// 颜色在 app_colors.dart 的 SmsPageColors（亮/暗色成对），这里只管形状。
class SmsDimens {
  const SmsDimens._();

  // ── 页面框架 ──
  static const double pageHPadding = 24;
  static const double backIconSize = 22;
  /// 返回按钮图标左缘距屏幕左缘的绝对距离（不受点击区宽度和页面边距影响）
  static const double backIconLeftInset = 24;
  static const double backTapHeight = 36;
  static const double titleTopGap = 20;
  static const double titleFontSize = 30;
  static const FontWeight titleFontWeight = FontWeight.bold;
  static const double subtitleTopGap = 10;
  static const double subtitleFontSize = 15;
  static const double subtitleLineHeight = 1.5;
  static const double formTopGap = 16;
  static const double fieldGap = 16;
  static const double buttonTopGap = 20;
  static const double errorTopGap = 16;
  static const double errorFontSize = 13;

  // ── 圆角描边输入框 ──
  static const double boxHeight = 56;
  static const double boxRadius = 14;
  static const double boxBorderWidth = 1;
  static const double boxHPadding = 16;

  // ── +86 前缀 ──
  static const double prefixFontSize = 18;
  static const FontWeight prefixFontWeight = FontWeight.w600;
  static const double prefixIconSize = 20;
  static const double prefixGap = 10;
  static const double dividerWidth = 1;
  static const double dividerHeight = 18;
  static const double dividerGap = 12;

  // ── 输入框内文字 ──
  static const double fieldFontSize = 17;
  /// 名字输入框提示语略小一号
  static const double nameHintFontSize = 15;
  static const double suffixFontSize = 13;
  /// 「重新发送」链接的水平/垂直点击内边距
  static const double suffixHPadding = 8;
  static const double suffixVPadding = 8;

  // ── 主按钮 ──
  static const double buttonHeight = 52;
  static const double buttonRadius = 26;
  static const double buttonFontSize = 18;
  static const double buttonSpinnerSize = 20;
  static const double buttonSpinnerStroke = 2;
}
