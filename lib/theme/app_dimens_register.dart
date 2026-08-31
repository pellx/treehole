/// 注册页尺寸、间距、字号、弧度、动画参数
///
/// 竖直定位一律为相对 Stack 垂直中心的 `*VOffset`（负值向上），
/// 水平为 `*HOffset`（负值向左）。Stack `clipBehavior: Clip.none`。
/// 修改后需检查亮色/暗色模式下各阶段显示效果。
class RegisterDimens {
  const RegisterDimens._();

  // ── 页面内容 ──
  static const double contentHPadding = 40;
  /// 阶段标题相对垂直中心
  static const double phaseTitleVOffset = -22;
  static const double phaseTitleHOffset = 0;
  static const double phaseTitleFontSize = 22;

  // ── 白色椭圆背景 ──
  static const double ellipseWidth = 1100;
  static const double ellipseHeight = 1000;
  static const double ellipseVOffset = -580;
  static const double ellipseHOffset = 0;

  // ── 注册页图片 — think（加载中/验证中；宽高为 max，框内等比缩放）──
  static const double thinkWidth = 270;
  static const double thinkHeight = 1000;
  static const double thinkVOffset = -137;
  static const double thinkHOffset = 10;

  // ── 注册页图片 — true（可以注册）──
  static const double trueWidth = 270;
  static const double trueHeight = 1000;
  static const double trueVOffset = -137;
  static const double trueHOffset = 6;

  // ── 注册页图片 — flase（已注册）──
  static const double flaseWidth = 270;
  static const double flaseHeight = 1000;
  static const double flaseVOffset = -137;
  static const double flaseHOffset = 15;

  // ── 错误提示 ──
  static const double errorFontSize = 15;
  static const double errorAlpha = 0.7;
  static const double errorRetryGap = 24;

  // ── 已注册提示 ──
  static const double registeredVOffset = 21;
  static const double registeredHOffset = 0;
  static const double registeredFontSize = 16;
  static const double registeredAlpha = 0.8;
  static const double registeredLineHeight = 1.6;

  // ── 已注册 — 登录按钮 ──
  static const double registeredLoginButtonWidth = 88;
  static const double registeredLoginButtonHeight = 37;
  static const double registeredLoginButtonPaddingH = 0;
  static const double registeredLoginButtonPaddingV = 0;
  static const double registeredLoginButtonVOffset = 72.5;
  static const double registeredLoginButtonHOffset = -60;
  static const double registeredLoginButtonRadius = 15;
  static const double registeredLoginButtonBorderWidth = 3;
  static const double registeredLoginButtonFontSize = 19;
  static const double registeredLoginButtonLetterSpacing = 0;

  // ── 已注册 — 联系我们按钮 ──
  static const double registeredContactButtonWidth = 110;
  static const double registeredContactButtonHeight = 37.8;
  static const double registeredContactButtonPaddingH = 0;
  static const double registeredContactButtonPaddingV = 0;
  static const double registeredContactButtonVOffset = 72.8;
  static const double registeredContactButtonHOffset = 50;
  static const double registeredContactButtonRadius = 16;
  static const double registeredContactButtonBorderWidth = 3;
  static const double registeredContactButtonFontSize = 19;
  static const double registeredContactButtonLetterSpacing = 0;

  // ── 注册按钮（相对垂直中心；0 约等于原距顶 380）──
  static const double buttonHeight = 40;
  static const double buttonWidth = 100;
  static const double buttonVOffset = 30;
  static const double buttonHOffset = 0;
  static const double buttonRadius = 13;
  static const double buttonBorderWidth = 3;
  static const double buttonFontSize = 19;
  static const double buttonLetterSpacing = 6;

  // ── 验证步骤行（registering 阶段）──
  static const double stepVOffset = 30;
  static const double stepHOffset = 0;
  static const double stepGap = 12; // 两行步骤间距
  static const double stepIconSize = 16;
  static const double stepIconGap = 10; // 图标和文字间距
  static const double stepFontSize = 13;
  static const double stepLoadingStrokeWidth = 2;
  static const double stepPendingAlpha = .4;
  static const double stepDefaultAlpha = 0.6;
  static const double stepErrorGap = 16; // 步骤区和错误信息间距

  // ── 验证码嵌入视图（registering 阶段显示；此前隐藏预渲染）──
  // 高度 320：拼图/滑块二次挑战面板会在验证条下方展开，需预留空间；
  // 一点即过形态仅条高约 40，多余部分透明不可见。
  // VOffset 154 使 320 高视图的顶部与原 72 高视图一致（中心-6），
  // 验证条视觉位置不变
  static const double captchaVOffset = 154;
  static const double captchaHOffset = 0;
  static const double captchaHeight = 320;
  /// 验证条 SDK 固定 320 宽，内边距须保证容器 ≥ 320（屏宽 - 2×20）
  static const double captchaHPadding = 20;

  // ── 注册页图片 — flower（输入用户名）──
  static const double flowerWidth = 270;
  static const double flowerHeight = 1000;
  static const double flowerVOffset = -140;
  static const double flowerHOffset = 6;

  // ── 注册页图片 — login（登录令牌输入）──
  static const double loginImageWidth = 270;
  static const double loginImageHeight = 1000;
  static const double loginImageVOffset = -137;
  static const double loginImageHOffset = 6;

  // ── 取名阶段（naming）──
  static const double namingInputVOffset = 25;
  static const double namingInputHOffset = 0;
  static const double namingInputHeight = 20;
  static const double namingInputWidth = 200;
  static const double namingInputFontSize = 14;
  static const double namingHintFontSize = 14;
  static const double namingHintAlpha = 0.3;
  static const double namingInputPaddingH = 0;
  static const double namingInputPaddingV = 10;

  static const double namingButtonGap = 6;
  static const double namingConfirmButtonWidth = 50;
  static const double namingConfirmButtonHeight = 27;
  static const double namingConfirmButtonPaddingH = 0;
  static const double namingConfirmButtonPaddingV = 0;
  static const double namingConfirmButtonRadius = 11;
  static const double namingConfirmButtonBorderWidth = 2;
  static const double namingConfirmButtonFontSize = 16;
  static const double namingConfirmButtonLetterSpacing = 0;

  static const double namingButtonConfirmSize = 20;
  static const double namingButtonStrokeWidth = 2;
  static const double namingErrorGap = 12;

  // ── 登录阶段（login）──
  static const double loginInputVOffset = 17;
  static const double loginInputHOffset = 0;
  /// 注册流程进入 login 时的令牌输入栏高度
  static const double loginInputHeight = 20;
  /// 用户侧（切换账户「登录用户」）唤出的令牌输入栏高度
  static const double loginFromUserInputHeight = 20;
  static const double loginInputWidth = 200;
  static const double loginInputFontSize = 17;
  static const double loginHintFontSize = 17;
  static const double loginHintAlpha = 0.3;
  static const double loginInputPaddingH = 0;
  static const double loginInputPaddingV = 10;

  /// 粘贴后掩码令牌（首末四位）字号
  static const double loginMaskedFontSize = 17;
  /// 掩码令牌透明度
  static const double loginMaskedAlpha = 0.6;
  /// 掩码令牌相对输入框水平偏移（负值向左）
  static const double loginMaskedHOffset = 0;
  /// 掩码令牌相对输入框竖直偏移（负值向上）
  static const double loginMaskedVOffset = -4;

  static const double loginButtonGap = 10;
  static const double loginConfirmButtonWidth = 50;
  static const double loginConfirmButtonHeight = 27;
  static const double loginConfirmButtonPaddingH = 0;
  static const double loginConfirmButtonPaddingV = 0;
  static const double loginConfirmButtonRadius = 11;
  static const double loginConfirmButtonBorderWidth = 2;
  static const double loginConfirmButtonFontSize = 16;
  static const double loginConfirmButtonLetterSpacing = 0;

  static const double loginButtonConfirmSize = 20;
  static const double loginButtonStrokeWidth = 2;
  static const double loginErrorGap = 12;

  static const double loginRecoverGap = 2; // 输入框和"找回用户"间距（保留）
  static const double loginRecoverFontSize = 12;
  /// 「找回用户」相对垂直中心
  static const double loginRecoverVOffset = 44;
  static const double loginRecoverHOffset = 0;
  static const double loginRecoverHitPaddingH = 12;
  static const double loginRecoverHitPaddingV = 8;

  // ── 右上角重新加载（相对右上角）──
  static const double refreshHOffset = -8;
  static const double refreshVOffset = 4;
  static const double refreshIconSize = 22;

  // ── 账户切换「登录用户」输入栏下方提示 ──
  static const double loginTransferTipGap = 0;
  static const double loginTransferTipHPadding = 12;
  static const double loginTransferTipFontSize = 12;
  static const double loginTransferTipAlpha = 0.45;
  static const double loginTransferTipLineHeight = 1.5;

  // ── 已注册阶段（register_page registered：两个继续路径按钮同一行 + 下一行小字）──
  static const double deviceRegisteredButtonWidth = 100;
  static const double deviceRegisteredButtonHeight = 40;
  static const double deviceRegisteredButtonVOffset = 22;
  static const double deviceRegisteredButtonHOffset = 0;
  static const double deviceRegisteredButtonGap = 24;
  static const double deviceRegisteredButtonRadius = 13;
  static const double deviceRegisteredButtonBorderWidth = 3;
  static const double deviceRegisteredButtonFontSize = 16;
  static const double deviceRegisteredButtonLetterSpacing = 1;
  static const double deviceRegisteredHintVOffset = 78;
  static const double deviceRegisteredHintHOffset = 0;
  static const double deviceRegisteredHintFontSize = 12;
  static const double deviceRegisteredHintAlpha = 0.45;

  // ── 手机号验证码页（sms_login / sms_register）──
  /// 交互内容区相对垂直中心的起点
  static const double smsContentVOffset = 25;
  static const double smsInputWidth = 200;
  static const double smsInputHeight = 20;
  static const double smsInputFontSize = 15;
  static const double smsRowGap = 14;
  static const double smsCodeInputWidth = 110;
  static const double smsSendGap = 10;
  static const double smsSendButtonWidth = 86;
  static const double smsSendButtonHeight = 27;
  static const double smsSendButtonRadius = 11;
  static const double smsSendButtonBorderWidth = 2;
  static const double smsSendButtonFontSize = 13;
  static const double smsConfirmButtonWidth = 60;
  static const double smsConfirmButtonHeight = 27;
  static const double smsConfirmButtonRadius = 11;
  static const double smsConfirmButtonBorderWidth = 2;
  static const double smsConfirmButtonFontSize = 16;
  static const double smsErrorGap = 12;
  static const double smsErrorFontSize = 13;
  static const double smsCaptchaTipGap = 8;
  static const double smsCaptchaTipFontSize = 12;
  static const double smsCaptchaTipAlpha = 0.45;
}
