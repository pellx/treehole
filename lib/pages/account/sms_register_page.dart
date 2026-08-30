import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/device_fingerprint.dart';
import '../../services/api.dart';
import '../../services/device_credential_store.dart';
import '../../services/device_fingerprint.dart';
import '../../services/pow.dart';
import '../../services/session_service.dart';
import '../../services/storage.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens_register.dart';
import 'captcha_view.dart';

/// 手机号注册新账号页。
///
/// POST /user/sms/send (scene: register) → POST /user/sms/register；
/// 一步完成建号 + 建绑（返回 user_token + device_secret），与
/// RegisterPage 的 registerV2 一样保留验证码 + PoW 防刷：PoW 页面加载时
/// 后台预取，用户填完手机号/验证码/昵称点确认后嵌入阿里云点击验证，
/// 验证通过即自动提交。成功后 pop(true)，由引导页收尾退出。
class SmsRegisterPage extends StatefulWidget {
  const SmsRegisterPage({super.key});

  @override
  State<SmsRegisterPage> createState() => _SmsRegisterPageState();
}

class _SmsRegisterPageState extends State<SmsRegisterPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  bool _sending = false;
  bool _submitting = false;
  int _cooldown = 0;
  bool _captchaPhase = false; // 确认后进入：嵌入验证码，通过即提交
  String? _error;

  // PoW 预取（与 RegisterPage 相同策略：纯后台，提交时缺失再补取）
  int? _prePowNonce;
  PoWChallenge? _prePowChallenge;
  bool _powFetching = false;

  bool _isValidPhone(String phone) => RegExp(r'^\d{11}$').hasMatch(phone);

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(() => _onTextChanged());
    _codeController.addListener(() => _onTextChanged());
    _nameController.addListener(() => _onTextChanged());
    _preFetchPow();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  /// 后台预取 PoW，缩短提交时的等待
  void _preFetchPow() {
    if (_powFetching) return;
    _powFetching = true;
    ApiService.getPoWChallenge().then((challenge) async {
      if (challenge == null || !mounted) {
        _powFetching = false;
        return;
      }
      _prePowChallenge = challenge;
      final nonce = await PoWService.solve(challenge);
      _powFetching = false;
      if (mounted && nonce != null) _prePowNonce = nonce;
    });
  }

  Future<void> _ensurePow() async {
    if (_prePowChallenge != null && _prePowNonce != null) return;
    final challenge = await ApiService.getPoWChallenge();
    if (!mounted || challenge == null) {
      if (mounted) setState(() => _error = 'PoW 获取失败，请重试');
      return;
    }
    final nonce = await PoWService.solve(challenge);
    if (!mounted) return;
    if (nonce == null) {
      setState(() => _error = 'PoW 计算失败，请重试');
      return;
    }
    _prePowChallenge = challenge;
    _prePowNonce = nonce;
  }

  void _startCooldown(int seconds) {
    // 冷却计时的简单实现：页面生命周期短，无需复用登录页的 Timer 逻辑
    Future<void> tick(int remaining) async {
      if (!mounted) return;
      setState(() => _cooldown = remaining);
      if (remaining <= 0) return;
      await Future.delayed(const Duration(seconds: 1));
      await tick(remaining - 1);
    }

    unawaited(tick(seconds));
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!_isValidPhone(phone) || _sending || _cooldown > 0) return;

    setState(() => _sending = true);
    try {
      final result = await ApiService.smsSend(phone: phone, scene: 'register');
      if (!mounted) return;
      if (result == null) {
        setState(() => _error = _mapSendError(ApiService.lastError));
        return;
      }
      setState(() => _error = null);
      _startCooldown(result.cooldownSeconds);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 填写完整后点确认 → 进入验证码阶段
  void _confirm() {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    if (!_isValidPhone(phone) || code.isEmpty || name.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _captchaPhase = true;
      _error = null;
    });
    _preFetchPow();
  }

  /// 验证通过（用户真实点击完成）→ 提交 sms/register
  Future<void> _onCaptchaVerified(String token) async {
    if (!mounted || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final phone = _phoneController.text.trim();
      final code = _codeController.text.trim();
      final name = _nameController.text.trim();

      final fp = await DeviceFingerprintService.collect();
      if (!mounted) return;
      if (fp.platform == DevicePlatform.unknown) {
        setState(() {
          _captchaPhase = false;
          _error = '设备指纹不可用，请重试';
        });
        return;
      }

      // PoW challenge TTL 约 3 分钟，缺失或过期时重新获取
      await _ensurePow();
      if (!mounted || _prePowChallenge == null || _prePowNonce == null) return;

      final result = await ApiService.smsRegister(
        phone: phone,
        code: code,
        userDisplayId: name,
        deviceFingerPrint: fp,
        verificationCaptcha: token,
        verificationPow: PoWResult(
          challengeId: _prePowChallenge!.challengeId,
          nonce: _prePowNonce!,
        ),
      );
      if (!mounted) return;

      if (result == null) {
        // 验证码 param 一次性：任何到达服务端的尝试都会消费它
        if (ApiService.lastError == 'PoW 验证失败') {
          _prePowChallenge = null;
          _prePowNonce = null;
        }
        setState(() {
          _captchaPhase = false;
          _error = _mapRegisterError(ApiService.lastError);
        });
        return;
      }

      // 与 RegisterPage 注册成功后的落盘一致
      await DeviceCredentialStore.saveUserExternalToken(result.userToken);
      await DeviceCredentialStore.mergeKnownUserTokens([result.userToken]);
      await DeviceCredentialStore.saveDeviceSecret(result.deviceSecret);
      await PostStorage.saveDisplayName(name);
      await PostStorage.setRegistered(true);

      // sms/register 已建绑：用现有 secret 建 session
      final activated =
          await SessionService.instance.activateAfterRegister(result.userToken);
      if (!activated && mounted) {
        setState(() => _error =
            '注册成功，但建绑/会话失败：${ApiService.lastError ?? '未知错误'}');
        return;
      }
      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _captchaPhase = false;
          _error = '网络异常：$e';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _mapSendError(String? raw) {
    return switch (raw) {
      'SMS_DAILY_LIMIT_EXCEEDED' => '该手机号今日发送次数已达上限',
      'SMS_IP_RATE_LIMIT_EXCEEDED' => '发送过于频繁，请稍后再试',
      'SMS_SEND_FAILED' => '短信发送失败，请稍后再试',
      null || '' => '发送失败',
      final code => '发送失败：$code',
    };
  }

  String _mapRegisterError(String? raw) {
    return switch (raw) {
      'SMS_CODE_INVALID' => '验证码错误',
      'SMS_CODE_EXPIRED' => '验证码已过期，请重新获取',
      'SMS_CODE_ATTEMPTS_EXCEEDED' => '验证码错误次数过多，请重新获取',
      'PHONE_TAKEN' => '该手机号已绑定其他账号',
      'NAME_TAKEN' => '用户名被占用',
      null || '' => '注册失败',
      final code => '注册失败：$code',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final canSend = _isValidPhone(phone) && !_sending && _cooldown == 0;
    final canConfirm = _isValidPhone(phone) &&
        code.isNotEmpty &&
        name.isNotEmpty &&
        !_submitting;

    return Scaffold(
      backgroundColor: colors.register.pageBg,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              double centerLeft(double width, double hOffset) =>
                  constraints.maxWidth / 2 - width / 2 + hOffset;
              double centerTop(double height, double vOffset) =>
                  constraints.maxHeight / 2 - height / 2 + vOffset;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 白色椭圆背景
                  Positioned(
                    left: centerLeft(
                      RegisterDimens.ellipseWidth,
                      RegisterDimens.ellipseHOffset,
                    ),
                    top: centerTop(
                      RegisterDimens.ellipseHeight,
                      RegisterDimens.ellipseVOffset,
                    ),
                    width: RegisterDimens.ellipseWidth,
                    height: RegisterDimens.ellipseHeight,
                    child: IgnorePointer(
                      child: ClipOval(
                        child: ColoredBox(color: colors.register.ellipseBg),
                      ),
                    ),
                  ),
                  // 插图（与取名阶段一致）
                  Positioned(
                    left: centerLeft(
                      RegisterDimens.flowerWidth,
                      RegisterDimens.flowerHOffset,
                    ),
                    top: centerTop(
                      RegisterDimens.flowerHeight,
                      RegisterDimens.flowerVOffset,
                    ),
                    width: RegisterDimens.flowerWidth,
                    height: RegisterDimens.flowerHeight,
                    child: IgnorePointer(
                      child: Image.asset(
                        'assets/mu/mu-flower.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                  // 标题
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.center,
                      child: Transform.translate(
                        offset: const Offset(0, RegisterDimens.phaseTitleVOffset),
                        child: Text(
                          '注册新账号',
                          style: TextStyle(
                            fontSize: RegisterDimens.phaseTitleFontSize,
                            fontWeight: FontWeight.bold,
                            color: onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 交互内容：填写 → 验证码
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.center,
                      child: Transform.translate(
                        offset: const Offset(0, RegisterDimens.smsContentVOffset),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: RegisterDimens.contentHPadding,
                          ),
                          child: _captchaPhase
                              ? _buildCaptchaContent(colors)
                              : _buildFormContent(
                                  colors, onSurface, canSend, canConfirm),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  InputDecoration _underlineDecoration(Color onSurface, {required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: RegisterDimens.smsInputFontSize,
        color: onSurface.withValues(alpha: RegisterDimens.namingHintAlpha),
      ),
      counterText: '',
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: onSurface, width: 1),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: onSurface, width: 1),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: onSurface, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: RegisterDimens.namingInputPaddingV,
      ),
    );
  }

  Widget _buildFormContent(
    AppColors colors,
    Color onSurface,
    bool canSend,
    bool canConfirm,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 手机号
        SizedBox(
          width: RegisterDimens.smsInputWidth,
          height: RegisterDimens.smsInputHeight,
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: RegisterDimens.smsInputFontSize,
              color: onSurface,
            ),
            cursorColor: onSurface,
            decoration: _underlineDecoration(onSurface, hint: '请输入手机号'),
          ),
        ),
        const SizedBox(height: RegisterDimens.smsRowGap),
        // 验证码 + 发送
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: RegisterDimens.smsCodeInputWidth,
              height: RegisterDimens.smsInputHeight,
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: RegisterDimens.smsInputFontSize,
                  color: onSurface,
                ),
                cursorColor: onSurface,
                decoration: _underlineDecoration(onSurface, hint: '验证码'),
              ),
            ),
            const SizedBox(width: RegisterDimens.smsSendGap),
            SizedBox(
              width: RegisterDimens.smsSendButtonWidth,
              height: RegisterDimens.smsSendButtonHeight,
              child: ElevatedButton(
                onPressed: canSend ? _sendCode : null,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.disabled)
                          ? colors.register.disabledButtonBg
                          : colors.register.buttonBg),
                  foregroundColor: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.disabled)
                          ? colors.register.disabledButtonText
                          : colors.register.buttonText),
                  shape: WidgetStateProperty.all(RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                        RegisterDimens.smsSendButtonRadius),
                    side: BorderSide(
                      color: canSend
                          ? colors.register.buttonBorderColor
                          : colors.register.disabledButtonBorderColor,
                      width: RegisterDimens.smsSendButtonBorderWidth,
                    ),
                  )),
                  padding: WidgetStateProperty.all(EdgeInsets.zero),
                ),
                child: _sending
                    ? SizedBox(
                        width: RegisterDimens.loginButtonConfirmSize,
                        height: RegisterDimens.loginButtonConfirmSize,
                        child: CircularProgressIndicator(
                          strokeWidth: RegisterDimens.loginButtonStrokeWidth,
                          valueColor: AlwaysStoppedAnimation(
                              colors.register.buttonText),
                        ),
                      )
                    : Text(
                        _cooldown > 0 ? '$_cooldown s' : '发送验证码',
                        style: TextStyle(
                          fontSize: RegisterDimens.smsSendButtonFontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: RegisterDimens.smsRowGap),
        // 昵称
        SizedBox(
          width: RegisterDimens.smsInputWidth,
          height: RegisterDimens.smsInputHeight,
          child: TextField(
            controller: _nameController,
            maxLength: 100,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: RegisterDimens.smsInputFontSize,
              color: onSurface,
            ),
            cursorColor: onSurface,
            decoration: _underlineDecoration(
              onSurface,
              hint: '请输入名字（每14天可更改一次）',
            ),
          ),
        ),
        const SizedBox(height: RegisterDimens.smsRowGap),
        _buildConfirmButton(colors, canConfirm),
        if (_error != null) ...[
          const SizedBox(height: RegisterDimens.smsErrorGap),
          Text(
            _error!,
            style: TextStyle(
              fontSize: RegisterDimens.smsErrorFontSize,
              color: colors.register.errorText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildConfirmButton(AppColors colors, bool canConfirm) {
    return SizedBox(
      width: RegisterDimens.smsConfirmButtonWidth,
      height: RegisterDimens.smsConfirmButtonHeight,
      child: ElevatedButton(
        onPressed: canConfirm ? _confirm : null,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? colors.register.disabledButtonBg
                  : colors.register.buttonBg),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? colors.register.disabledButtonText
                  : colors.register.buttonText),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(RegisterDimens.smsConfirmButtonRadius),
            side: BorderSide(
              color: canConfirm
                  ? colors.register.buttonBorderColor
                  : colors.register.disabledButtonBorderColor,
              width: RegisterDimens.smsConfirmButtonBorderWidth,
            ),
          )),
          padding: WidgetStateProperty.all(EdgeInsets.zero),
        ),
        child: Text(
          '确认',
          style: TextStyle(
            fontSize: RegisterDimens.smsConfirmButtonFontSize,
            fontWeight: FontWeight.w500,
            letterSpacing: RegisterDimens.loginConfirmButtonLetterSpacing,
          ),
        ),
      ),
    );
  }

  /// 验证码阶段：提示 + 内嵌阿里云点击验证，通过后自动提交
  Widget _buildCaptchaContent(AppColors colors) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '完成验证后将自动提交',
          style: TextStyle(
            fontSize: RegisterDimens.smsCaptchaTipFontSize,
            color: onSurface.withValues(
              alpha: RegisterDimens.smsCaptchaTipAlpha,
            ),
          ),
        ),
        const SizedBox(height: RegisterDimens.smsCaptchaTipGap),
        CaptchaView(
          height: RegisterDimens.captchaHeight,
          // SMS 注册服务端直接校验 captchaVerifyParam，无需 Redis 凭证，
          // 校验处理器原样回传参数
          verifyHandler: (param) async => param,
          onVerified: _onCaptchaVerified,
        ),
        if (_error != null) ...[
          const SizedBox(height: RegisterDimens.smsErrorGap),
          Text(
            _error!,
            style: TextStyle(
              fontSize: RegisterDimens.smsErrorFontSize,
              color: colors.register.errorText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
