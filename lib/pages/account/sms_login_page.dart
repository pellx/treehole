import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api.dart';
import '../../services/device_credential_store.dart';
import '../../services/device_fingerprint.dart';
import '../../services/session_service.dart';
import '../../services/storage.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens_register.dart';

/// 手机号找回页：短信验证码登录已存在账户。
///
/// POST /user/sms/send (scene: login) → POST /user/sms/login；
/// 服务端按手机号定位账户并在其绑定范围内匹配本机指纹，直接签发 session。
/// 成功后 pop(true)，由引导页（DeviceRegisteredPage）收尾退出。
class SmsLoginPage extends StatefulWidget {
  const SmsLoginPage({super.key});

  @override
  State<SmsLoginPage> createState() => _SmsLoginPageState();
}

class _SmsLoginPageState extends State<SmsLoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  bool _sending = false;
  bool _submitting = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  String? _error;

  bool _isValidPhone(String phone) => RegExp(r'^\d{11}$').hasMatch(phone);

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown -= 1);
      }
    });
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!_isValidPhone(phone) || _sending || _cooldown > 0) return;

    setState(() => _sending = true);
    try {
      final result = await ApiService.smsSend(phone: phone, scene: 'login');
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

  Future<void> _confirm() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (!_isValidPhone(phone) || code.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // 与登录/建绑同一套硬件指纹 hash（仅稳定硬件字段）
      final fingerprint = await DeviceFingerprintService.collect();
      final hash = SessionService.computeFingerprintHash(fingerprint);

      final result = await ApiService.smsLogin(
        phone: phone,
        code: code,
        fingerprintHash: hash,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() => _error = _mapLoginError(ApiService.lastError));
        return;
      }

      // 服务端已直接签发 session：写入顶层 session 并视为已注册
      SessionService.instance.invalidate();
      await DeviceCredentialStore.clearSession();
      await DeviceCredentialStore.saveSessionId(result.sessionId);
      await DeviceCredentialStore.saveSessionSecret(result.sessionSecret);
      // 后端若随响应带出 user_token，则一并完成账户令牌登记
      final userToken = result.userToken?.trim() ?? '';
      if (userToken.isNotEmpty) {
        await DeviceCredentialStore.saveUserExternalToken(userToken);
        await DeviceCredentialStore.mergeKnownUserTokens([userToken]);
        await DeviceCredentialStore.saveAccountSession(
          userToken,
          result.sessionId,
          result.sessionSecret,
        );
        await DeviceCredentialStore.touchLastSessionAt(userToken);
      }
      await PostStorage.setRegistered(true);

      final profile = await ApiService.getUserProfile(
        sessionId: result.sessionId,
        sessionSecret: result.sessionSecret,
      );
      if (profile != null && profile.userDisplayId.isNotEmpty) {
        await PostStorage.saveDisplayName(profile.userDisplayId);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '网络异常：$e');
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

  String _mapLoginError(String? raw) {
    return switch (raw) {
      'SMS_CODE_INVALID' => '验证码错误',
      'SMS_CODE_EXPIRED' => '验证码已过期，请重新获取',
      'SMS_CODE_ATTEMPTS_EXCEEDED' => '验证码错误次数过多，请重新获取',
      'USER_NOT_FOUND' => '该手机号未注册，且本机没有可找回的账户',
      'FINGERPRINT_MISMATCH' => '本机设备不在该账户的绑定范围内',
      'DEVICE_SESSION_LOCKED' => '本机切号锁定中（约 2 天），暂不可切换',
      'REBIND_COOLDOWN' => '解绑冷却中，请 2 天后再登录此账户',
      'TRANSFER_REQUIRED' => '需先在原设备发起转移申请（15 分钟内有效）',
      'TRANSFER_INVALID' => '转移申请无效或已过期，请在原设备重新申请',
      null || '' => '找回失败',
      final code => '找回失败：$code',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final canSend = _isValidPhone(phone) && !_sending && _cooldown == 0;
    final canConfirm = _isValidPhone(phone) && code.isNotEmpty && !_submitting;

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
                  // 插图（与令牌登录阶段一致）
                  Positioned(
                    left: centerLeft(
                      RegisterDimens.loginImageWidth,
                      RegisterDimens.loginImageHOffset,
                    ),
                    top: centerTop(
                      RegisterDimens.loginImageHeight,
                      RegisterDimens.loginImageVOffset,
                    ),
                    width: RegisterDimens.loginImageWidth,
                    height: RegisterDimens.loginImageHeight,
                    child: IgnorePointer(
                      child: Image.asset(
                        'assets/mu/mu-login.png',
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
                          '手机号找回',
                          style: TextStyle(
                            fontSize: RegisterDimens.phaseTitleFontSize,
                            fontWeight: FontWeight.bold,
                            color: onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 交互内容
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.center,
                      child: Transform.translate(
                        offset: const Offset(0, RegisterDimens.smsContentVOffset),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: RegisterDimens.contentHPadding,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildPhoneInput(onSurface),
                              const SizedBox(height: RegisterDimens.smsRowGap),
                              _buildCodeRow(colors, onSurface, canSend),
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
                          ),
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

  Widget _buildPhoneInput(Color onSurface) {
    return SizedBox(
      width: RegisterDimens.smsInputWidth,
      height: RegisterDimens.smsInputHeight,
      child: TextField(
        controller: _phoneController,
        autofocus: true,
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
        onChanged: (_) => setState(() {}),
        decoration: _underlineDecoration(onSurface, hint: '请输入手机号'),
      ),
    );
  }

  Widget _buildCodeRow(AppColors colors, Color onSurface, bool canSend) {
    return Row(
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
            onChanged: (_) => setState(() {}),
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
                      valueColor:
                          AlwaysStoppedAnimation(colors.register.buttonText),
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
        child: _submitting
            ? SizedBox(
                width: RegisterDimens.loginButtonConfirmSize,
                height: RegisterDimens.loginButtonConfirmSize,
                child: CircularProgressIndicator(
                  strokeWidth: RegisterDimens.loginButtonStrokeWidth,
                  valueColor:
                      AlwaysStoppedAnimation(colors.register.buttonText),
                ),
              )
            : Text(
                '找回',
                style: TextStyle(
                  fontSize: RegisterDimens.smsConfirmButtonFontSize,
                  fontWeight: FontWeight.w500,
                  letterSpacing:
                      RegisterDimens.loginConfirmButtonLetterSpacing,
                ),
              ),
      ),
    );
  }
}
