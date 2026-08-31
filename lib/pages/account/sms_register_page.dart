import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/device_fingerprint.dart';
import '../../services/api.dart';
import '../../services/device_credential_store.dart';
import '../../services/device_fingerprint.dart';
import '../../services/session_service.dart';
import '../../services/storage.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens_sms.dart';

/// 注册/登录页（官方「手机号登录」样式，系统默认路由推入）。
///
/// 第一步输入手机号点「发送验证码」——请求携带设备指纹，服务端判定并
/// 返回模式，第二步按模式提交：
///   login    手机号已注册 → 验证并登录（/user/sms/login）
///   register 注册新账户（/user/sms/register，手机号绑定到新账户、
///            主设备为本机），仅此模式需要填写昵称
/// 绑定到本机主设备账户的找回在「找回原用户」页的链路进行。
/// 成功后 pop(true)，由注册页收尾退出。
///
/// 样式集中在 SmsDimens（形状）与 SmsPageColors（颜色，亮/暗成对）。
class SmsRegisterPage extends StatefulWidget {
  const SmsRegisterPage({super.key});

  @override
  State<SmsRegisterPage> createState() => _SmsRegisterPageState();
}

class _SmsRegisterPageState extends State<SmsRegisterPage> {
  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _codeFocusNode = FocusNode();

  bool _sending = false;
  bool _submitting = false;
  bool _codeSent = false;
  int _cooldown = 0;
  String? _error;

  /// 发送时服务端判定的模式：login | register
  String? _mode;

  /// 发送时采集的硬件指纹 hash（提交 login 时复用）
  String? _fingerprintHash;

  bool _isValidPhone(String phone) => RegExp(r'^\d{11}$').hasMatch(phone);

  /// register 模式需要昵称，login/recover 不需要
  bool get _needsName => _mode == 'register';

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(() => _onTextChanged());
    _codeController.addListener(() => _onTextChanged());
    _nameController.addListener(() => _onTextChanged());
    // 转场动画结束后再唤起键盘，避免转场与键盘动画打架
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) _phoneFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  /// 主按钮：未发送时发送验证码，已发送后按模式提交
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
    await _submit();
  }

  void _startCooldown(int seconds) {
    // 冷却递减：页面生命周期短，简单实现即可
    Future<void> tick(int remaining) async {
      if (!mounted) return;
      setState(() => _cooldown = remaining);
      if (remaining <= 0) return;
      await Future.delayed(const Duration(seconds: 1));
      await tick(remaining - 1);
    }

    tick(seconds);
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!_isValidPhone(phone) || _sending || _cooldown > 0) return;

    setState(() => _sending = true);
    try {
      // 服务端需要指纹判定模式（login/recover/register）
      final fingerprint = await DeviceFingerprintService.collect();
      final hash = SessionService.computeFingerprintHash(fingerprint);

      final result = await ApiService.smsSend(
        phone: phone,
        scene: 'register',
        fingerprintHash: hash,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() => _error = _mapSendError(ApiService.lastError));
        return;
      }
      setState(() {
        _error = null;
        _codeSent = true;
        _mode = result.mode;
        _fingerprintHash = hash;
      });
      _startCooldown(result.cooldownSeconds);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 按模式提交：register → sms/register；login → sms/login
  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    if (!_isValidPhone(phone) || code.isEmpty || _submitting) return;
    if (_needsName && name.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final fp = await DeviceFingerprintService.collect();
      if (!mounted) return;
      if (fp.platform == DevicePlatform.unknown) {
        setState(() => _error = '设备指纹不可用，请重试');
        return;
      }

      if (_mode == 'register') {
        await _submitRegister(phone, code, name, fp);
      } else {
        await _submitLogin(phone, code);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '网络异常：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// register 模式：注册新账户（手机号绑定到新账户、主设备为本机）
  Future<void> _submitRegister(
    String phone,
    String code,
    String name,
    DeviceFingerprint fp,
  ) async {
    final result = await ApiService.smsRegister(
      phone: phone,
      code: code,
      userDisplayId: name,
      deviceFingerPrint: fp,
    );
    if (!mounted) return;

    if (result == null) {
      setState(() => _error = _mapRegisterError(ApiService.lastError));
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
      setState(() =>
          _error = '注册成功，但建绑/会话失败：${ApiService.lastError ?? '未知错误'}');
      return;
    }
    if (!mounted) return;

    Navigator.of(context).pop(true);
  }

  /// login 模式：短信登录。指纹 hash 复用发送时采集的值（同机同会话，
  /// 结果一致）
  Future<void> _submitLogin(String phone, String code) async {
    final hash = _fingerprintHash ??
        SessionService.computeFingerprintHash(
          await DeviceFingerprintService.collect(),
        );

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
    // 完成账户令牌登记（切号/failover 机制依赖）
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

  String _mapLoginError(String? raw) {
    return switch (raw) {
      'SMS_CODE_INVALID' => '验证码错误',
      'SMS_CODE_EXPIRED' => '验证码已过期，请重新获取',
      'SMS_CODE_ATTEMPTS_EXCEEDED' => '验证码错误次数过多，请重新获取',
      'USER_NOT_FOUND' => '该手机号未注册，且本机没有可找回的账户',
      'FINGERPRINT_MISMATCH' => '本机设备不在该账户的绑定范围内',
      'DEVICE_SESSION_LOCKED' => '本机切号锁定中（约 2 天），暂不可切换',
      'DEVICE_NOT_PRIMARY' => '该账户的主设备不是本机，无法在此登录',
      'REBIND_COOLDOWN' => '解绑冷却中，请 2 天后再登录此账户',
      'TRANSFER_REQUIRED' => '需先在原设备发起转移申请（15 分钟内有效）',
      'TRANSFER_INVALID' => '转移申请无效或已过期，请在原设备重新申请',
      null || '' => '登录失败',
      final code => '登录失败：$code',
    };
  }

  /// 按模式显示的副标题
  String get _subtitle {
    switch (_mode) {
      case 'login':
        return '该手机号已注册，验证后将登录';
      case 'register':
        return '该手机号未注册，验证后将注册新账号';
      default:
        return '未注册的手机号验证后将自动注册新账号';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!.smsPage;

    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final canSend = _isValidPhone(phone) && !_sending && _cooldown == 0;
    final enabled = _codeSent
        ? _isValidPhone(phone) &&
            code.isNotEmpty &&
            (!(_mode == 'register') || name.isNotEmpty) &&
            !_submitting
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
              '注册/登录',
              style: TextStyle(
                fontSize: SmsDimens.titleFontSize,
                fontWeight: SmsDimens.titleFontWeight,
                color: colors.title,
              ),
            ),
            const SizedBox(height: SmsDimens.subtitleTopGap),
            Text(
              _subtitle,
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
              if (_mode == 'register') ...[
                const SizedBox(height: SmsDimens.fieldGap),
                _buildNameBox(colors),
              ],
            ],
            const SizedBox(height: SmsDimens.buttonTopGap),
            _buildPrimaryButton(
              colors,
              _codeSent
                  ? (_mode == 'register' ? '验证并注册' : '验证并登录')
                  : '发送验证码',
              enabled ? _onPrimary : null,
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

  Widget _buildNameBox(SmsPageColors colors) {
    return _buildBox(
      colors,
      child: Center(
        child: TextField(
          controller: _nameController,
          maxLength: 100,
          style: TextStyle(
            fontSize: SmsDimens.fieldFontSize,
            color: colors.fieldText,
          ),
          cursorColor: colors.fieldText,
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            counterText: '',
            hintText: '请输入名字（每14天可更改一次）',
            hintStyle: TextStyle(
              fontSize: SmsDimens.nameHintFontSize,
              color: colors.hintText,
            ),
          ),
        ),
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
