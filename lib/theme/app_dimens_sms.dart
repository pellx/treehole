/// 手机号验证码页（sms_login / sms_register）尺寸参数。
///
/// 这两页是右侧滑入的正式子页（官方「手机号登录」样式）：
/// 白底、左对齐大标题 + 灰色副标题、圆角描边输入框、大号圆角主按钮。
class SmsDimens {
  const SmsDimens._();

  // ── 页面框架 ──
  static const double pageHPadding = 24;
  static const double backIconSize = 22;
  static const double titleTopGap = 20;
  static const double titleFontSize = 30;
  static const double subtitleTopGap = 10;
  static const double subtitleFontSize = 15;
  static const double subtitleAlpha = 0.45;
  static const double subtitleLineHeight = 1.5;
  static const double formTopGap = 36;
  static const double fieldGap = 16;
  static const double buttonTopGap = 40;
  static const double errorTopGap = 16;
  static const double errorFontSize = 13;

  // ── 圆角描边输入框 ──
  static const double boxHeight = 56;
  static const double boxRadius = 14;
  static const double boxBorderWidth = 1;
  static const double boxBorderAlpha = 0.25;
  static const double boxHPadding = 16;

  // ── +86 前缀 ──
  static const double prefixFontSize = 18;
  static const double prefixIconSize = 20;
  static const double prefixGap = 10;
  static const double dividerGap = 12;

  // ── 输入框内文字 ──
  static const double fieldFontSize = 17;
  static const double hintAlpha = 0.35;
  static const double suffixFontSize = 13;

  // ── 主按钮 ──
  static const double buttonHeight = 52;
  static const double buttonRadius = 26;
  static const double buttonFontSize = 18;
  static const double buttonSpinnerSize = 20;
  static const double buttonSpinnerStroke = 2;
}
