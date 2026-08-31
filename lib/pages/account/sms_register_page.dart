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
import '../../theme/app_dimens_sms.dart';
import 'captcha_view.dart';

/// 手机号注册新账号页（官方「手机号登录」样式，从右侧滑入）。
///
/// 第一步输入手机号点「发送验证码」，出现验证码/昵称输入框后点
/// 「验证并注册」进入内嵌验证，通过即自动提交。
/// POST /user/sms/send (scene: register) → POST /user/sms/register；
/// 一步完成建号 + 建绑（返回 user_token + device_secret），保留验证码 +
/// PoW 防刷：PoW 页面加载时后台预取。成功后 pop(true)，由注册页收尾退出。
class SmsRegisterPage extends StatefulWidget {
  const SmsRegisterPage({super.key});

  @override
  State<SmsRegisterPage> createState() => _SmsRegisterPageState();
}

class _SmsRegisterPageState extends State<SmsRegisterPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _codeFocusNode = FocusNode();

  bool _sending = false;
  bool _submitting = false;
  bool _codeSent = false;
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
    _codeFocusNode.dispose();
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

  /// 主按钮：未发送时发送验证码，已发送后进入验证（captchaPhase）
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
    _confirm();
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
      setState(() {
        _error = null;
        _codeSent = true;
      });
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
    final enabled = _captchaPhase
        ? false
        : _codeSent
            ? _isValidPhone(phone) &&
                code.isNotEmpty &&
                name.isNotEmpty &&
                !_submitting
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
              '注册新账号',
              style: TextStyle(
                fontSize: SmsDimens.titleFontSize,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
            const SizedBox(height: SmsDimens.subtitleTopGap),
            Text(
              '未注册的手机号验证后将自动注册新账号',
              style: TextStyle(
                fontSize: SmsDimens.subtitleFontSize,
                height: SmsDimens.subtitleLineHeight,
                color: onSurface.withValues(alpha: SmsDimens.subtitleAlpha),
              ),
            ),
            const SizedBox(height: SmsDimens.formTopGap),
            if (_captchaPhase)
              _buildCaptchaContent(colors, onSurface)
            else ...[
              _buildPhoneBox(onSurface),
              if (_codeSent) ...[
                const SizedBox(height: SmsDimens.fieldGap),
                _buildCodeBox(colors, onSurface),
                const SizedBox(height: SmsDimens.fieldGap),
                _buildNameBox(onSurface),
              ],
              const SizedBox(height: SmsDimens.buttonTopGap),
              _buildPrimaryButton(
                colors,
                _codeSent ? '验证并注册' : '发送验证码',
                enabled ? _onPrimary : null,
              ),
            ],
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

  Widget _buildNameBox(Color onSurface) {
    return _buildBox(
      onSurface,
      child: Center(
        child: TextField(
          controller: _nameController,
          maxLength: 100,
          style: TextStyle(
            fontSize: SmsDimens.fieldFontSize,
            color: onSurface,
          ),
          cursorColor: onSurface,
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            counterText: '',
            hintText: '请输入名字（每14天可更改一次）',
            hintStyle: TextStyle(
              fontSize: SmsDimens.fieldFontSize - 2,
              color: onSurface.withValues(alpha: SmsDimens.hintAlpha),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(
    AppColors colors,
    String label,
    VoidCallback? onPressed,
  ) {
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

  /// 验证码阶段：提示 + 内嵌阿里云点击验证，通过后自动提交
  Widget _buildCaptchaContent(AppColors colors, Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '完成验证后将自动提交',
          style: TextStyle(
            fontSize: SmsDimens.subtitleFontSize,
            color: onSurface.withValues(alpha: SmsDimens.subtitleAlpha),
          ),
        ),
        const SizedBox(height: SmsDimens.fieldGap),
        CaptchaView(
          // SMS 注册服务端直接校验 captchaVerifyParam，无需 Redis 凭证，
          // 校验处理器原样回传参数
          verifyHandler: (param) async => param,
          onVerified: _onCaptchaVerified,
        ),
      ],
    );
  }
}
