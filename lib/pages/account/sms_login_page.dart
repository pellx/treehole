import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api.dart';
import '../../services/device_credential_store.dart';
import '../../services/device_fingerprint.dart';
import '../../services/session_service.dart';
import '../../services/storage.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens_sms.dart';

/// 手机号找回页（官方「手机号登录」样式，从右侧滑入）。
///
/// 第一步输入手机号点「发送验证码」，出现验证码输入框后点「验证并找回」。
/// POST /user/sms/send (scene: login) → POST /user/sms/login；
/// 服务端按手机号定位账户（未注册手机号走指纹找回路径），直接签发 session。
/// 成功后 pop(true)，由注册页收尾退出。
class SmsLoginPage extends StatefulWidget {
  const SmsLoginPage({super.key});

  @override
  State<SmsLoginPage> createState() => _SmsLoginPageState();
}

class _SmsLoginPageState extends State<SmsLoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();

  bool _sending = false;
  bool _submitting = false;
  bool _codeSent = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  String? _error;

  bool _isValidPhone(String phone) => RegExp(r'^\d{11}$').hasMatch(phone);

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(() {
      if (mounted) setState(() {});
    });
    _codeController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _codeFocusNode.dispose();
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

  /// 主按钮：未发送时发送验证码，已发送后验证并找回
  Future<void> _onPrimary() async {
    if (!_codeSent) {
      await _sendCode();
      if (_codeSent && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _codeFocusNode.requestFocus();
        });
      }
      return;
    }
    await _confirm();
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
      setState(() {
        _error = null;
        _codeSent = true;
      });
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
      // 后端随响应带出 user_token，完成账户令牌登记（切号/failover 依赖）
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
    final enabled = _codeSent
        ? _isValidPhone(phone) && code.isNotEmpty && !_submitting
        : canSend;

    return Scaffold(
      backgroundColor: colors.common.surface,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: SmsDimens.pageHPadding,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  size: SmsDimens.backIconSize,
                  color: onSurface,
                ),
              ),
            ),
            const SizedBox(height: SmsDimens.titleTopGap),
            Text(
              '找回原用户',
              style: TextStyle(
                fontSize: SmsDimens.titleFontSize,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
            const SizedBox(height: SmsDimens.subtitleTopGap),
            Text(
              '使用该账户绑定的手机号验证找回；账户未绑定过手机号时，'
              '可使用任意未被占用的手机号',
              style: TextStyle(
                fontSize: SmsDimens.subtitleFontSize,
                height: SmsDimens.subtitleLineHeight,
                color: onSurface.withValues(alpha: SmsDimens.subtitleAlpha),
              ),
            ),
            const SizedBox(height: SmsDimens.formTopGap),
            _buildPhoneBox(onSurface),
            if (_codeSent) ...[
              const SizedBox(height: SmsDimens.fieldGap),
              _buildCodeBox(colors, onSurface),
            ],
            const SizedBox(height: SmsDimens.buttonTopGap),
            _buildPrimaryButton(
              colors,
              _codeSent ? '验证并找回' : '发送验证码',
              enabled ? _onPrimary : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: SmsDimens.errorTopGap),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: SmsDimens.errorFontSize,
                  color: colors.register.errorText,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 圆角描边输入框容器
  Widget _buildBox(Color onSurface, {required Widget child}) {
    return Container(
      height: SmsDimens.boxHeight,
      padding: const EdgeInsets.symmetric(horizontal: SmsDimens.boxHPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SmsDimens.boxRadius),
        border: Border.all(
          color: onSurface.withValues(alpha: SmsDimens.boxBorderAlpha),
          width: SmsDimens.boxBorderWidth,
        ),
      ),
      child: child,
    );
  }

  Widget _buildPhoneBox(Color onSurface) {
    return _buildBox(
      onSurface,
      child: Row(
        children: [
          Text(
            '+86',
            style: TextStyle(
              fontSize: SmsDimens.prefixFontSize,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          Icon(
            Icons.expand_more,
            size: SmsDimens.prefixIconSize,
            color: onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: SmsDimens.prefixGap),
          Container(
            width: 1,
            height: 18,
            color: onSurface.withValues(alpha: SmsDimens.boxBorderAlpha),
          ),
          const SizedBox(width: SmsDimens.dividerGap),
          Expanded(
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              style: TextStyle(
                fontSize: SmsDimens.fieldFontSize,
                color: onSurface,
              ),
              cursorColor: onSurface,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '请输入手机号',
                hintStyle: TextStyle(
                  fontSize: SmsDimens.fieldFontSize,
                  color: onSurface.withValues(alpha: SmsDimens.hintAlpha),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBox(AppColors colors, Color onSurface) {
    return _buildBox(
      onSurface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeController,
              focusNode: _codeFocusNode,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: TextStyle(
                fontSize: SmsDimens.fieldFontSize,
                color: onSurface,
              ),
              cursorColor: onSurface,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '请输入验证码',
                hintStyle: TextStyle(
                  fontSize: SmsDimens.fieldFontSize,
                  color: onSurface.withValues(alpha: SmsDimens.hintAlpha),
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: (_cooldown > 0 || _sending)
                ? null
                : () {
                    _codeFocusNode.unfocus();
                    _sendCode();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              child: Text(
                _cooldown > 0 ? '重新发送 $_cooldown s' : '重新发送',
                style: TextStyle(
                  fontSize: SmsDimens.suffixFontSize,
                  color: _cooldown > 0
                      ? onSurface.withValues(alpha: 0.35)
                      : colors.postCreate.submitBg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(AppColors colors, String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: SmsDimens.buttonHeight,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.postCreate.submitBg,
          foregroundColor: colors.postCreate.submitText,
          disabledBackgroundColor:
              colors.postCreate.submitBg.withValues(alpha: 0.4),
          disabledForegroundColor: colors.postCreate.submitText,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SmsDimens.buttonRadius),
          ),
        ),
        child: (_sending || _submitting)
            ? SizedBox(
                width: SmsDimens.buttonSpinnerSize,
                height: SmsDimens.buttonSpinnerSize,
                child: CircularProgressIndicator(
                  strokeWidth: SmsDimens.buttonSpinnerStroke,
                  valueColor:
                      AlwaysStoppedAnimation(colors.postCreate.submitText),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: SmsDimens.buttonFontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}
