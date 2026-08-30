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
import 'captcha_view.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens_accent.dart';
import '../../theme/app_dimens_register.dart';

class RegisterPage extends StatefulWidget {
  /// 为 true 时直接进入令牌登录（供账户切换页「登录用户」）
  final bool startAtLogin;

  const RegisterPage({super.key, this.startAtLogin = false});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  String _phase = 'checking'; // checking | registered | failed | unregistered | registering | naming | login | done
  String? _error;

  DeviceFingerprint? _fingerprint;

  final _nameController = TextEditingController();
  final _tokenController = TextEditingController();
  final _tokenFocusNode = FocusNode();
  bool _loginTokenFocused = false;
  bool _submitting = false;
  String? _renameError;

  // 预取 PoW（页面加载时后台开始，纯后台进行，不在界面展示）
  int? _prePowNonce;
  PoWChallenge? _prePowChallenge;
  bool _powFetching = false;

  // 「通过一些测试」阶段由用户完成阿里云点击验证后持有，提交时使用
  String? _captchaToken;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
    _tokenController.addListener(() {
      if (mounted) setState(() {});
    });
    _tokenFocusNode.addListener(() {
      if (!mounted) return;
      setState(() => _loginTokenFocused = _tokenFocusNode.hasFocus);
    });
    if (widget.startAtLogin) {
      _phase = 'login';
    } else {
      _check();
      _preFetchPow();
    }
  }

  /// Stack 内相对中心偏移定位（与椭圆/插图同一套坐标系）
  Widget _offsetLayer({
    required double vOffset,
    double hOffset = 0,
    bool ignorePointer = false,
    required Widget child,
  }) {
    final layer = Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(hOffset, vOffset),
        child: child,
      ),
    );
    return Positioned.fill(
      child: ignorePointer ? IgnorePointer(child: layer) : layer,
    );
  }

  /// 阶段插图：[vOffset] 相对垂直中心，[hOffset] 水平偏移
  ({String path, double width, double height, double vOffset, double hOffset})
      get _phaseImageConfig {
    switch (_phase) {
      case 'checking':
      case 'registering':
        return (
          path: 'assets/mu/mu-think.png',
          width: RegisterDimens.thinkWidth,
          height: RegisterDimens.thinkHeight,
          vOffset: RegisterDimens.thinkVOffset,
          hOffset: RegisterDimens.thinkHOffset,
        );
      case 'unregistered':
        return (
          path: 'assets/mu/mu-true.png',
          width: RegisterDimens.trueWidth,
          height: RegisterDimens.trueHeight,
          vOffset: RegisterDimens.trueVOffset,
          hOffset: RegisterDimens.trueHOffset,
        );
      case 'registered':
      case 'failed':
        return (
          path: 'assets/mu/mu-flase.png',
          width: RegisterDimens.flaseWidth,
          height: RegisterDimens.flaseHeight,
          vOffset: RegisterDimens.flaseVOffset,
          hOffset: RegisterDimens.flaseHOffset,
        );
      case 'naming':
        return (
          path: 'assets/mu/mu-flower.png',
          width: RegisterDimens.flowerWidth,
          height: RegisterDimens.flowerHeight,
          vOffset: RegisterDimens.flowerVOffset,
          hOffset: RegisterDimens.flowerHOffset,
        );
      case 'login':
        return (
          path: 'assets/mu/mu-login.png',
          width: RegisterDimens.loginImageWidth,
          height: RegisterDimens.loginImageHeight,
          vOffset: RegisterDimens.loginImageVOffset,
          hOffset: RegisterDimens.loginImageHOffset,
        );
      default:
        return (
          path: 'assets/mu/mu-think.png',
          width: RegisterDimens.thinkWidth,
          height: RegisterDimens.thinkHeight,
          vOffset: RegisterDimens.thinkVOffset,
          hOffset: RegisterDimens.thinkHOffset,
        );
    }
  }

  String get _phaseTitle {
    switch (_phase) {
      case 'checking':
        return '让我康康';
      case 'unregistered':
        return '您的设备可进行注册';
      case 'registered':
        return '设备环境无法注册';
      case 'failed':
        return '测试未通过，请重试';
      case 'registering':
        return '通过一些测试';
      case 'naming':
        return '注册成功！取个名字吧';
      case 'login':
        return '请粘贴用户令牌';
      default:
        return '';
    }
  }

  Future<void> _check() async {
    setState(() { _phase = 'checking'; _error = null; });
    final stopwatch = Stopwatch()..start();
    try {
      final fp = await DeviceFingerprintService.collect();
      if (!mounted) return;
      _fingerprint = fp;
      final registered = await ApiService.check(deviceFingerPrint: fp);
      if (!mounted) return;

      // 至少显示 1300ms 的检测中状态
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 1300) {
        await Future.delayed(Duration(milliseconds: 1300 - elapsed));
        if (!mounted) return;
      }

      if (registered == null) {
        setState(() => _phase = 'failed');
        return;
      }
      setState(() => _phase = registered ? 'registered' : 'unregistered');
    } catch (e) {
      if (mounted) setState(() => _phase = 'failed');
    }
  }

  /// 后台预取 PoW（纯后台，不在界面展示），缩短提交时的等待
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

  /// 验证通过（用户在「通过一些测试」阶段真实点击完成）→ 进入取名
  void _onCaptchaVerified(String token) {
    if (!mounted) return;
    setState(() {
      _captchaToken = token;
      _phase = 'naming';
    });
  }

  /// 重置页面状态，重新检测
  void _reset() {
    _nameController.clear();
    _tokenController.clear();
    _prePowNonce = null;
    _prePowChallenge = null;
    _captchaToken = null;
    setState(() {
      _phase = 'checking';
      _error = null;
      _submitting = false;
      _renameError = null;
    });
    _check();
    _preFetchPow();
  }

  /// 点击「注册」→ 进入「通过一些测试」阶段，页面上嵌入阿里云点击验证；
  /// PoW 在后台预取，用户完成验证后即进入取名
  void _startRegister() {
    final fp = _fingerprint;
    if (fp == null) {
      setState(() => _phase = 'failed');
      return;
    }
    setState(() {
      _phase = 'registering';
      _error = null;
    });
    _preFetchPow();
  }

  Future<void> _confirmName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() { _submitting = true; _renameError = null; });

    try {
      final fp = _fingerprint;
      if (fp == null) {
        setState(() => _renameError = '设备指纹丢失，请重试');
        return;
      }

      // PoW challenge TTL 约 3 分钟（API.md 3a）：在取名页停留过久会过期
      // （服务端报「PoW 验证失败」后已清空），缺失时重新获取
      if (_prePowChallenge == null || _prePowNonce == null) {
        final challenge = await ApiService.getPoWChallenge();
        if (!mounted) return;
        if (challenge == null) {
          setState(() => _renameError = 'PoW 获取失败，请重试');
          return;
        }
        final nonce = await PoWService.solve(challenge);
        if (!mounted) return;
        if (nonce == null) {
          setState(() => _renameError = 'PoW 计算失败，请重试');
          return;
        }
        _prePowChallenge = challenge;
        _prePowNonce = nonce;
      }

      // 验证码在「通过一些测试」阶段由用户真实点击完成（官方明确 App 内
      // 自动触发无痕验证会被风控拒绝）。token 一次性：提交失败后清空，
      // 再次确认时自动回到验证阶段重新获取
      final captchaToken = _captchaToken;
      if (captchaToken == null) {
        setState(() => _phase = 'registering');
        return;
      }

      final result = await ApiService.registerV2(
        userDisplayId: name,
        deviceFingerPrint: fp,
        verificationCaptcha: captchaToken,
        verificationPow: PoWResult(
          challengeId: _prePowChallenge!.challengeId,
          nonce: _prePowNonce!,
        ),
      );

      if (!mounted) return;

      if (result == null) {
        // PoW 校验不消费 challenge；仅过期被拒（TTL 约 3 分钟）时重取。
        // 验证码 param 一次性：任何到达服务端的尝试都会消费它，必须清空，
        // 再次确认时回到验证阶段重新获取（复用报 F008）
        _captchaToken = null;
        if (ApiService.lastError == 'PoW 验证失败') {
          _prePowChallenge = null;
          _prePowNonce = null;
        }
        setState(() => _renameError = _mapRegisterError(ApiService.lastError));
        return;
      }

      await DeviceCredentialStore.saveUserExternalToken(result.userToken);
      await DeviceCredentialStore.mergeKnownUserTokens([result.userToken]);
      await DeviceCredentialStore.saveDeviceSecret(result.deviceSecret);
      await PostStorage.saveDisplayName(name);
      await PostStorage.setRegistered(true);

      // 注册未写 binding：建绑后再申请 session
      final activated =
          await SessionService.instance.activateAfterRegister(result.userToken);
      if (!activated) {
        setState(() => _renameError =
            '注册成功，但建绑/会话失败：${ApiService.lastError ?? '未知错误'}');
        return;
      }

      setState(() => _phase = 'done');
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _renameError = '网络异常：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmLogin() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;

    setState(() {
      _submitting = true;
      _renameError = null;
    });

    try {
      final ok = await SessionService.instance.loginWithToken(token);
      if (!mounted) return;
      if (!ok) {
        setState(() => _renameError = _mapLoginError(ApiService.lastError));
        return;
      }

      await PostStorage.setRegistered(true);
      final sessionId = await DeviceCredentialStore.getSessionId();
      final sessionSecret = await DeviceCredentialStore.getSessionSecret();
      if (sessionId != null && sessionSecret != null) {
        final profile = await ApiService.getUserProfile(
          sessionId: sessionId,
          sessionSecret: sessionSecret,
        );
        if (profile != null && profile.userDisplayId.isNotEmpty) {
          await PostStorage.saveDisplayName(profile.userDisplayId);
        }
      }

      if (!mounted) return;
      setState(() => _phase = 'done');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _renameError = '网络异常：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _mapRegisterError(String? raw) {
    return switch (raw) {
      'NAME_TAKEN' => '用户名被占用',
      'NAME_EMPTY' => '名字不能为空',
      null || '' => '注册失败',
      final code => '注册失败：$code',
    };
  }

  String _mapLoginError(String? raw) {
    return switch (raw) {
      'TOKEN_EMPTY' => '请输入用户令牌',
      'USER_NOT_FOUND' => '用户令牌无效',
      'FINGERPRINT_MISMATCH' => '设备指纹不匹配',
      'DEVICE_NOT_FOUND' => '本机设备未找到，请先在本机完成注册',
      'REBIND_COOLDOWN' => '解绑冷却中，请 2 天后再登录此账户',
      'TRANSFER_REQUIRED' => '需先在原设备发起转移申请（15 分钟内有效）',
      'TRANSFER_INVALID' => '转移申请无效或已过期，请在原设备重新申请',
      'DEVICE_SESSION_LOCKED' => '本机切号锁定中（约 2 天），暂不可切换到其他账户',
      'RATE_LIMITED' => '操作过于频繁，请稍后再试',
      _ => (raw == null || raw.isEmpty) ? '登录失败' : raw,
    };
  }

  String _maskLoginToken(String token) {
    const head = AccentDimens.tokenHeadChars;
    const tail = AccentDimens.tokenTailChars;
    if (token.length > head + tail) {
      return '${token.substring(0, head)}...${token.substring(token.length - tail)}';
    }
    return token;
  }

  Future<void> _pasteLoginToken() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      setState(() => _renameError = '剪贴板为空');
      return;
    }
    setState(() {
      _tokenController.text = text;
      _renameError = null;
    });
  }

  @override
  void dispose() {
    _tokenFocusNode.dispose();
    _nameController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: colors.register.pageBg,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 中心 + V/HOffset → Positioned 左上角；定宽高避免 Image 无界约束崩溃
              double centerLeft(double width, double hOffset) =>
                  constraints.maxWidth / 2 - width / 2 + hOffset;
              double centerTop(double height, double vOffset) =>
                  constraints.maxHeight / 2 - height / 2 + vOffset;
              final img = _phaseImageConfig;
              return Stack(
            clipBehavior: Clip.none,
            children: [
            // 白色椭圆 — 相对中心偏移
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
            // 悬浮图片 — 宽高为 max 约束，框内等比缩放不拉伸
            if (_phase != 'done')
              Positioned(
                left: centerLeft(img.width, img.hOffset),
                top: centerTop(img.height, img.vOffset),
                width: img.width,
                height: img.height,
                child: IgnorePointer(
                  child: Image.asset(
                    img.path,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            // 阶段标题
            if (_phase != 'done' && _phaseTitle.isNotEmpty)
              _offsetLayer(
                vOffset: RegisterDimens.phaseTitleVOffset,
                hOffset: RegisterDimens.phaseTitleHOffset,
                child: Text(_phaseTitle,
                    style: TextStyle(
                      fontSize: RegisterDimens.phaseTitleFontSize,
                      fontWeight: FontWeight.bold,
                      color: onSurface,
                    )),
              ),
            // 已注册提示文字
            if (_phase == 'registered')
              _offsetLayer(
                vOffset: RegisterDimens.registeredVOffset,
                hOffset: RegisterDimens.registeredHOffset,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RegisterDimens.contentHPadding),
                  child: _buildRegistered(colors),
                ),
              ),
            // 已注册 — 登录按钮
            if (_phase == 'registered')
              _offsetLayer(
                vOffset: RegisterDimens.registeredLoginButtonVOffset,
                hOffset: RegisterDimens.registeredLoginButtonHOffset,
                child: SizedBox(
                  width: RegisterDimens.registeredLoginButtonWidth,
                  height: RegisterDimens.registeredLoginButtonHeight,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _phase = 'login';
                        _renameError = null;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.register.buttonBg,
                      foregroundColor: colors.register.buttonText,
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            RegisterDimens.registeredLoginButtonPaddingH,
                        vertical:
                            RegisterDimens.registeredLoginButtonPaddingV,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            RegisterDimens.registeredLoginButtonRadius),
                        side: BorderSide(
                          color: colors.register.buttonBorderColor,
                          width: RegisterDimens
                              .registeredLoginButtonBorderWidth,
                        ),
                      ),
                    ),
                    child: Text('登录',
                        style: TextStyle(
                          fontSize: RegisterDimens
                              .registeredLoginButtonFontSize,
                          fontWeight: FontWeight.w500,
                          letterSpacing: RegisterDimens
                              .registeredLoginButtonLetterSpacing,
                        )),
                  ),
                ),
              ),
            // 已注册 — 联系我们按钮
            if (_phase == 'registered')
              _offsetLayer(
                vOffset: RegisterDimens.registeredContactButtonVOffset,
                hOffset: RegisterDimens.registeredContactButtonHOffset,
                child: SizedBox(
                  width: RegisterDimens.registeredContactButtonWidth,
                  height: RegisterDimens.registeredContactButtonHeight,
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: 导航到联系我们页
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.register.buttonBg,
                      foregroundColor: colors.register.buttonText,
                      padding: EdgeInsets.symmetric(
                        horizontal: RegisterDimens
                            .registeredContactButtonPaddingH,
                        vertical: RegisterDimens
                            .registeredContactButtonPaddingV,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            RegisterDimens.registeredContactButtonRadius),
                        side: BorderSide(
                          color: colors.register.buttonBorderColor,
                          width: RegisterDimens
                              .registeredContactButtonBorderWidth,
                        ),
                      ),
                    ),
                    child: Text('联系我们',
                        style: TextStyle(
                          fontSize: RegisterDimens
                              .registeredContactButtonFontSize,
                          fontWeight: FontWeight.w500,
                          letterSpacing: RegisterDimens
                              .registeredContactButtonLetterSpacing,
                        )),
                  ),
                ),
              ),
            // 交互内容 — 按钮/输入框等
            if (_phase == 'unregistered' && _error == null)
              _offsetLayer(
                vOffset: RegisterDimens.buttonVOffset,
                hOffset: RegisterDimens.buttonHOffset,
                child: SizedBox(
                  width: RegisterDimens.buttonWidth,
                  height: RegisterDimens.buttonHeight,
                  child: ElevatedButton(
                    onPressed: _startRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.register.buttonBg,
                      foregroundColor: colors.register.buttonText,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(RegisterDimens.buttonRadius),
                        side: BorderSide(
                          color: colors.register.buttonBorderColor,
                          width: RegisterDimens.buttonBorderWidth,
                        ),
                      ),
                    ),
                    child: Text('注册',
                        style: TextStyle(
                          fontSize: RegisterDimens.buttonFontSize,
                          fontWeight: FontWeight.w500,
                          letterSpacing: RegisterDimens.buttonLetterSpacing,
                        )),
                  ),
                ),
              )
            else if (_phase == 'registering')
              _offsetLayer(
                vOffset: RegisterDimens.captchaVOffset,
                hOffset: RegisterDimens.captchaHOffset,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RegisterDimens.captchaHPadding),
                  child: CaptchaView(
                    height: RegisterDimens.captchaHeight,
                    onVerified: _onCaptchaVerified,
                  ),
                ),
              )
            else if (_phase == 'naming')
              _offsetLayer(
                vOffset: RegisterDimens.namingInputVOffset,
                hOffset: RegisterDimens.namingInputHOffset,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RegisterDimens.contentHPadding),
                  child: _buildNamingInput(colors, onSurface),
                ),
              )
            else if (_phase == 'login')
              _offsetLayer(
                vOffset: RegisterDimens.loginInputVOffset,
                hOffset: RegisterDimens.loginInputHOffset,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RegisterDimens.contentHPadding),
                  child: _buildLoginInput(colors, onSurface),
                ),
              )
            else
              _offsetLayer(
                vOffset: RegisterDimens.stepVOffset,
                hOffset: RegisterDimens.stepHOffset,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RegisterDimens.contentHPadding),
                  child: _buildPhase(colors, onSurface),
                ),
              ),
            // 登录 — 找回用户（账户切换进入的登录不显示）
            if (_phase == 'login' && !widget.startAtLogin)
              _offsetLayer(
                vOffset: RegisterDimens.loginRecoverVOffset,
                hOffset: RegisterDimens.loginRecoverHOffset,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // TODO: 找回用户逻辑
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RegisterDimens.loginRecoverHitPaddingH,
                      vertical: RegisterDimens.loginRecoverHitPaddingV,
                    ),
                    child: Text(
                      '找回用户',
                      style: TextStyle(
                        fontSize: RegisterDimens.loginRecoverFontSize,
                        color: colors.register.loginRecoverColor,
                      ),
                    ),
                  ),
                ),
              ),
            // 右上角重新加载（相对右上角偏移）
            if (!widget.startAtLogin)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Transform.translate(
                    offset: Offset(RegisterDimens.refreshHOffset,
                        RegisterDimens.refreshVOffset),
                    child: IconButton(
                      icon: Icon(Icons.refresh,
                          size: RegisterDimens.refreshIconSize,
                          color: onSurface.withValues(alpha: 0.35)),
                      tooltip: '重新加载',
                      onPressed: _reset,
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

  Widget _buildPhase(AppColors colors, Color onSurface) {
    switch (_phase) {
      case 'checking':
        return const SizedBox.shrink();
      case 'registered':
        return const SizedBox.shrink();
      case 'failed':
        return const SizedBox.shrink();
      case 'unregistered':
        return _error != null
            ? _buildError(onSurface)
            : _buildRegisterButton(colors);
      case 'naming':
        return const SizedBox.shrink();
      case 'login':
        return const SizedBox.shrink();
      case 'done':
        return const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildError(Color onSurface) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_error!,
            style: TextStyle(
              fontSize: RegisterDimens.errorFontSize,
              color: onSurface.withValues(alpha: RegisterDimens.errorAlpha),
            ),
            textAlign: TextAlign.center),
        const SizedBox(height: RegisterDimens.errorRetryGap),
        TextButton(onPressed: _check, child: const Text('重试')),
      ],
    );
  }

  Widget _buildRegistered(AppColors colors) {
    return Text(
      '设备环境已被注册，请登录已有账户或联系我们进行注册',
      style: TextStyle(
        fontSize: RegisterDimens.registeredFontSize,
        color: colors.register.registeredTextColor,
        height: RegisterDimens.registeredLineHeight,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildRegisterButton(AppColors colors) {
    return SizedBox(
      width: RegisterDimens.buttonWidth,
      height: RegisterDimens.buttonHeight,
      child: ElevatedButton(
        onPressed: _startRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.register.buttonBg,
          foregroundColor: colors.register.buttonText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RegisterDimens.buttonRadius),
            side: BorderSide(
              color: colors.register.buttonBorderColor,
              width: RegisterDimens.buttonBorderWidth,
            ),
          ),
        ),
        child: Text('注册',
            style: TextStyle(
              fontSize: RegisterDimens.buttonFontSize,
              fontWeight: FontWeight.w500,
              letterSpacing: RegisterDimens.buttonLetterSpacing,
            )),
      ),
    );
  }

  Widget _buildNamingInput(AppColors colors, Color onSurface) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: RegisterDimens.namingInputWidth,
              height: RegisterDimens.namingInputHeight,
              child: TextField(
                controller: _nameController,
                autofocus: true,
                maxLength: 100,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: RegisterDimens.namingInputFontSize,
                  color: onSurface,
                ),
                decoration: InputDecoration(
                  hintText: '请输入（每14天可更改一次）',
                  hintStyle: TextStyle(
                    fontSize: RegisterDimens.namingHintFontSize,
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
                    horizontal: RegisterDimens.namingInputPaddingH,
                    vertical: RegisterDimens.namingInputPaddingV,
                  ),
                ),
              ),
            ),
            SizedBox(width: RegisterDimens.namingButtonGap),
            SizedBox(
              width: RegisterDimens.namingConfirmButtonWidth,
              height: RegisterDimens.namingConfirmButtonHeight,
              child: ElevatedButton(
                onPressed: (_submitting || _nameController.text.trim().isEmpty) ? null : _confirmName,
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
                    borderRadius: BorderRadius.circular(RegisterDimens.namingConfirmButtonRadius),
                    side: BorderSide(
                      color: (_submitting || _nameController.text.trim().isEmpty)
                          ? colors.register.disabledButtonBorderColor
                          : colors.register.buttonBorderColor,
                      width: RegisterDimens.namingConfirmButtonBorderWidth,
                    ),
                  )),
                  padding: WidgetStateProperty.all(EdgeInsets.symmetric(
                    horizontal: RegisterDimens.namingConfirmButtonPaddingH,
                    vertical: RegisterDimens.namingConfirmButtonPaddingV,
                  )),
                ),
                child: _submitting
                    ? SizedBox(
                        width: RegisterDimens.namingButtonConfirmSize,
                        height: RegisterDimens.namingButtonConfirmSize,
                        child: CircularProgressIndicator(
                          strokeWidth: RegisterDimens.namingButtonStrokeWidth,
                          valueColor: AlwaysStoppedAnimation(colors.register.buttonText),
                        ),
                      )
                    : Text('确认',
                        style: TextStyle(
                          fontSize: RegisterDimens.namingConfirmButtonFontSize,
                          fontWeight: FontWeight.w500,
                          letterSpacing: RegisterDimens.namingConfirmButtonLetterSpacing,
                        )),
              ),
            ),
          ],
        ),
        if (_renameError != null) ...[
          const SizedBox(height: RegisterDimens.namingErrorGap),
          Text(_renameError!,
              style: TextStyle(
                fontSize: RegisterDimens.stepFontSize,
                color: colors.register.errorText,
              ),
              textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Widget _buildLoginInput(AppColors colors, Color onSurface) {
    final token = _tokenController.text.trim();
    final hasToken = token.isNotEmpty;
    // 失焦且超过 8 字才掩码；一旦聚焦/输入则始终明文
    final showMask = !_loginTokenFocused &&
        token.length > AccentDimens.tokenHeadChars + AccentDimens.tokenTailChars;
    // 空：粘贴；有内容：确认登录
    final onButtonPressed = _submitting
        ? null
        : (hasToken ? _confirmLogin : _pasteLoginToken);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: RegisterDimens.loginInputWidth,
              height: widget.startAtLogin
                  ? RegisterDimens.loginFromUserInputHeight
                  : RegisterDimens.loginInputHeight,
              child: showMask
                  ? GestureDetector(
                      onTap: _submitting
                          ? null
                          : () {
                              setState(() => _loginTokenFocused = true);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _tokenFocusNode.requestFocus();
                              });
                            },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: onSurface, width: 1),
                          ),
                        ),
                        child: Transform.translate(
                          offset: Offset(
                            RegisterDimens.loginMaskedHOffset,
                            RegisterDimens.loginMaskedVOffset,
                          ),
                          child: Text(
                            _maskLoginToken(token),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: RegisterDimens.loginMaskedFontSize,
                              color: onSurface.withValues(
                                  alpha: RegisterDimens.loginMaskedAlpha),
                            ),
                          ),
                        ),
                      ),
                    )
                  : TextField(
                      controller: _tokenController,
                      focusNode: _tokenFocusNode,
                      enabled: !_submitting,
                      autofocus: !hasToken || _loginTokenFocused,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: RegisterDimens.loginInputFontSize,
                        color: onSurface,
                      ),
                      cursorColor: onSurface,
                      onTap: () {
                        if (!_loginTokenFocused) {
                          setState(() => _loginTokenFocused = true);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: '请输入令牌',
                        hintStyle: TextStyle(
                          fontSize: RegisterDimens.loginHintFontSize,
                          color: onSurface.withValues(
                              alpha: RegisterDimens.loginHintAlpha),
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
                          horizontal: RegisterDimens.loginInputPaddingH,
                          vertical: RegisterDimens.loginInputPaddingV,
                        ),
                      ),
                    ),
            ),
            SizedBox(width: RegisterDimens.loginButtonGap),
            SizedBox(
              width: RegisterDimens.loginConfirmButtonWidth,
              height: RegisterDimens.loginConfirmButtonHeight,
              child: ElevatedButton(
                onPressed: onButtonPressed,
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
                    borderRadius: BorderRadius.circular(RegisterDimens.loginConfirmButtonRadius),
                    side: BorderSide(
                      color: _submitting
                          ? colors.register.disabledButtonBorderColor
                          : colors.register.buttonBorderColor,
                      width: RegisterDimens.loginConfirmButtonBorderWidth,
                    ),
                  )),
                  padding: WidgetStateProperty.all(EdgeInsets.symmetric(
                    horizontal: RegisterDimens.loginConfirmButtonPaddingH,
                    vertical: RegisterDimens.loginConfirmButtonPaddingV,
                  )),
                ),
                child: _submitting
                    ? SizedBox(
                        width: RegisterDimens.loginButtonConfirmSize,
                        height: RegisterDimens.loginButtonConfirmSize,
                        child: CircularProgressIndicator(
                          strokeWidth: RegisterDimens.loginButtonStrokeWidth,
                          valueColor: AlwaysStoppedAnimation(colors.register.buttonText),
                        ),
                      )
                    : Text(hasToken ? '确认' : '粘贴',
                        style: TextStyle(
                          fontSize: RegisterDimens.loginConfirmButtonFontSize,
                          fontWeight: FontWeight.w500,
                          letterSpacing: RegisterDimens.loginConfirmButtonLetterSpacing,
                        )),
              ),
            ),
          ],
        ),
        if (widget.startAtLogin) ...[
          const SizedBox(height: RegisterDimens.loginTransferTipGap),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RegisterDimens.loginTransferTipHPadding,
            ),
            child: Text(
              '请在已登录账户设备的 [用户]=>[设备绑定] 页面中点击 [转移申请] 发出登录许可后进行登录',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: RegisterDimens.loginTransferTipFontSize,
                height: RegisterDimens.loginTransferTipLineHeight,
                color: onSurface.withValues(
                  alpha: RegisterDimens.loginTransferTipAlpha,
                ),
              ),
            ),
          ),
        ],
        if (_renameError != null) ...[
          const SizedBox(height: RegisterDimens.namingErrorGap),
          Text(
            _renameError!,
            style: TextStyle(
              fontSize: RegisterDimens.stepFontSize,
              color: colors.register.errorText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

}
