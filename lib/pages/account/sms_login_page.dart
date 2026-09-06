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
import '../settings/settings_navigation.dart';
import 'register_page.dart';
import 'sms_register_page.dart';

/// 手机号找回页（官方「手机号登录」样式，系统默认路由推入）。
///
/// 第一步输入手机号点「发送验证码」，出现验证码输入框后点「验证并找回」。
/// POST /user/sms/send (scene: login) → POST /user/sms/login；
/// 服务端按手机号定位账户（未注册手机号走指纹找回路径），直接签发 session。
/// 成功后 pop(true)，由注册页收尾退出。
///
/// 样式集中在 SmsDimens（形状）与 SmsPageColors（颜色，亮/暗成对）。
class SmsLoginPage extends StatefulWidget {
  const SmsLoginPage({super.key});

  @override
  State<SmsLoginPage> createState() => _SmsLoginPageState();
}

class _SmsLoginPageState extends State<SmsLoginPage> {
  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();
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
    // 转场动画结束后再唤起键盘，避免转场与键盘动画打架
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) _phoneFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneController.dispose();
    _phoneFocusNode.dispose();
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

  Future<void> _openTokenLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      topDownRoute(const RegisterPage(startAtLogin: true)),
    );
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!_isValidPhone(phone) || _sending || _cooldown > 0) return;

    setState(() => _sending = true);
    try {
      // 发送前置校验需要指纹：服务端比对手机号与本机账户的对应关系
      final fingerprint = await DeviceFingerprintService.collect();
      final hash = SessionService.computeFingerprintHash(fingerprint);

      final result = await ApiService.smsSend(
        phone: phone,
        scene: 'login',
        fingerprintHash: hash,
      );
      if (!mounted) return;
      if (result == null) {
        final err = ApiService.lastError;
        if (err == 'PHONE_MISMATCH_FOR_DEVICE') {
          // 输入手机号与本机账户不符：提示并转注册新账号
          final registered = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const SmsRegisterPage()),
          );
          if (registered == true && mounted) {
            Navigator.of(context).pop(true);
          }
          return;
        }
        setState(() => _error = _mapSendError(err));
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
      'PHONE_MISMATCH_FOR_DEVICE' => '该手机号与设备当前账户不符，请注册新账号',
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
    final colors = Theme.of(context).extension<AppColors>()!.smsPage;

    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final canSend =
        _isValidPhone(phone) && !_sending && _cooldown == 0;
    final enabled = _codeSent
        ? _isValidPhone(phone) && code.isNotEmpty && !_submitting
        : canSend;

    return Scaffold(
      backgroundColor: colors.pageBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: SmsDimens.pageHPadding,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              // 平移量 = 绝对左距 - 页面边距，使图标左缘精确落在
              // backIconLeftInset 处（点击区宽度不影响图标位置）
              child: Transform.translate(
                offset: Offset(
                  SmsDimens.backIconLeftInset - SmsDimens.pageHPadding,
                  0,
                ),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(
                    width: SmsDimens.backIconSize,
                    height: SmsDimens.backTapHeight,
                  ),
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    size: SmsDimens.backIconSize,
                    color: colors.title,
                  ),
                ),
              ),
            ),
            const SizedBox(height: SmsDimens.titleTopGap),
            Text(
              '找回原用户',
              style: TextStyle(
                fontSize: SmsDimens.titleFontSize,
                fontWeight: SmsDimens.titleFontWeight,
                color: colors.title,
              ),
            ),
            const SizedBox(height: SmsDimens.subtitleTopGap),
            Text(
              '使用该账户绑定的手机号验证找回；账户未绑定过手机号时，'
              '可使用任意未被占用的手机号',
              style: TextStyle(
                fontSize: SmsDimens.subtitleFontSize,
                height: SmsDimens.subtitleLineHeight,
                color: colors.subtitle,
              ),
            ),
            const SizedBox(height: SmsDimens.formTopGap),
            _buildPhoneBox(colors),
            if (_codeSent) ...[
              const SizedBox(height: SmsDimens.fieldGap),
              _buildCodeBox(colors),
            ],
            const SizedBox(height: SmsDimens.buttonTopGap),
            _buildPrimaryButton(
              colors,
              _codeSent ? '验证并找回' : '发送验证码',
              enabled ? _onPrimary : null,
            ),
            const SizedBox(height: SmsDimens.tokenLoginTopGap),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openTokenLogin,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    '切换账户令牌登录',
                    style: TextStyle(
                      fontSize: SmsDimens.tokenLoginFontSize,
                      color: colors.suffixLink,
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: SmsDimens.errorTopGap),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: SmsDimens.errorFontSize,
                  color: colors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 圆角描边输入框容器
  Widget _buildBox(SmsPageColors colors, {required Widget child}) {
    return Container(
      height: SmsDimens.boxHeight,
      padding: const EdgeInsets.symmetric(horizontal: SmsDimens.boxHPadding),
      decoration: BoxDecoration(
        color: colors.boxBg,
        borderRadius: BorderRadius.circular(SmsDimens.boxRadius),
        border: Border.all(
          color: colors.boxBorder,
          width: SmsDimens.boxBorderWidth,
        ),
      ),
      child: child,
    );
  }

  Widget _buildPhoneBox(SmsPageColors colors) {
    return _buildBox(
      colors,
      child: Row(
        children: [
          Text(
            '+86',
            style: TextStyle(
              fontSize: SmsDimens.prefixFontSize,
              fontWeight: SmsDimens.prefixFontWeight,
              color: colors.fieldText,
            ),
          ),
          Icon(
            Icons.expand_more,
            size: SmsDimens.prefixIconSize,
            color: colors.prefixIcon,
          ),
          const SizedBox(width: SmsDimens.prefixGap),
          Container(
            width: SmsDimens.dividerWidth,
            height: SmsDimens.dividerHeight,
            color: colors.boxBorder,
          ),
          const SizedBox(width: SmsDimens.dividerGap),
          Expanded(
            child: TextField(
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              style: TextStyle(
                fontSize: SmsDimens.fieldFontSize,
                color: colors.fieldText,
              ),
              cursorColor: colors.fieldText,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '请输入手机号',
                hintStyle: TextStyle(
                  fontSize: SmsDimens.fieldFontSize,
                  color: colors.hintText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBox(SmsPageColors colors) {
    return _buildBox(
      colors,
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
                color: colors.fieldText,
              ),
              cursorColor: colors.fieldText,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '请输入验证码',
                hintStyle: TextStyle(
                  fontSize: SmsDimens.fieldFontSize,
                  color: colors.hintText,
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
                horizontal: SmsDimens.suffixHPadding,
                vertical: SmsDimens.suffixVPadding,
              ),
              child: Text(
                _cooldown > 0 ? '重新发送 $_cooldown s' : '重新发送',
                style: TextStyle(
                  fontSize: SmsDimens.suffixFontSize,
                  color: _cooldown > 0
                      ? colors.suffixDisabled
                      : colors.suffixLink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(
    SmsPageColors colors,
    String label,
    VoidCallback? onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      height: SmsDimens.buttonHeight,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.buttonBg,
          foregroundColor: colors.buttonText,
          disabledBackgroundColor: colors.buttonBg.withValues(alpha: 0.4),
          disabledForegroundColor: colors.buttonText,
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
                  valueColor: AlwaysStoppedAnimation(colors.buttonText),
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
