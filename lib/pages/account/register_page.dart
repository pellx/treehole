import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../models/device_fingerprint.dart';
import '../../services/account_display.dart';
import '../../services/api.dart';
import '../../services/device_credential_store.dart';
import '../../services/device_fingerprint.dart';
import '../../services/pow.dart';
import '../../services/session_service.dart';
import '../../services/storage.dart';
import 'captcha_view.dart';
import 'sms_login_page.dart';
import 'sms_register_page.dart';
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
  // checking | recovering | registered | failed | unregistered | registering
  // | naming | activating | activationPending | login | done
  String _phase = 'checking';
  String? _error;

  /// 检测请求序号：_reset/重复刷新后，旧请求不得再覆盖新请求的状态
  int _checkSeq = 0;

  DeviceFingerprint? _fingerprint;

  final _nameController = TextEditingController();
  final _tokenController = TextEditingController();
  final _tokenFocusNode = FocusNode();
  bool _loginTokenFocused = false;
  bool _submitting = false;
  String? _renameError;

  /// 激活失败原因（activationPending 阶段展示）
  String? _activationError;

  /// 注册请求幂等 ID：同一次注册尝试的重试复用同一 ID，
  /// 服务端凭此保证只创建一个用户；响应丢失时可凭 ID 查询结果
  String? _registrationRequestId;

  // 预取 PoW（页面加载时后台开始，纯后台进行，不在界面展示）
  int? _prePowNonce;
  PoWChallenge? _prePowChallenge;
  bool _powFetching = false;

  // 「通过一些测试」阶段即时二次校验通过后由服务端签发的 Redis 凭证
  // （10 分钟有效，注册失败可复用，注册成功后服务端销毁）
  String? _captchaTicket;

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
    } else if (PostStorage.isActivationPending()) {
      // 上次注册已建号但激活中断：直接恢复激活，不重新检测/注册
      _phase = 'activating';
      unawaited(_resumeActivation());
    } else {
      final savedRequestId = PostStorage.getRegistrationRequestId()?.trim();
      if (savedRequestId != null && savedRequestId.isNotEmpty) {
        // 上次请求可能已在服务端建号，但客户端在收到响应、落盘 token 前
        // 退出。必须先按幂等 ID 取回结果，不能直接发起新注册。
        _registrationRequestId = savedRequestId;
        _phase = 'recovering';
        unawaited(_recoverInterruptedRegistration(savedRequestId));
      } else {
        unawaited(_check());
        _preFetchPow();
      }
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
      case 'recovering':
      case 'registering':
      case 'activating':
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
      case 'activationPending':
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
      case 'recovering':
        return '正在恢复注册';
      case 'unregistered':
        return '您的设备可进行注册';
      case 'registered':
        return '该设备环境已注册';
      case 'failed':
        return '测试未通过，请重试';
      case 'registering':
        return '通过一些测试';
      case 'naming':
        return '注册成功！取个名字吧';
      case 'activating':
        return '正在建立会话';
      case 'activationPending':
        return '注册成功，激活未完成';
      case 'login':
        return '请粘贴用户令牌';
      default:
        return '';
    }
  }

  Future<void> _check() async {
    // 序号守卫：_reset/连续刷新后，旧请求的回包不得覆盖新请求的状态
    final seq = ++_checkSeq;
    bool stale() => !mounted || seq != _checkSeq;

    setState(() { _phase = 'checking'; _error = null; });
    final stopwatch = Stopwatch()..start();

    // 1) 采集设备指纹（本地失败与网络/服务端失败分开提示）
    DeviceFingerprint fp;
    try {
      fp = await DeviceFingerprintService.collect();
    } catch (e) {
      if (stale()) return;
      setState(() {
        _phase = 'failed';
        _error = '设备指纹采集失败，请重试';
      });
      return;
    }
    if (stale()) return;
    _fingerprint = fp;

    // 2) 请求服务端检测
    final registered = await ApiService.check(deviceFingerPrint: fp);
    if (stale()) return;

    // 至少显示 1300ms 的检测中状态
    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed < 1300) {
      await Future.delayed(Duration(milliseconds: 1300 - elapsed));
      if (stale()) return;
    }

    if (registered == null) {
      setState(() {
        _phase = 'failed';
        // check() 已写入当前失败原因：网络连接失败 / 服务器响应超时 /
        // 响应缺少字段 / 服务端错误消息
        _error = ApiService.lastError ?? '检测失败，请重试';
      });
      return;
    }
    setState(() => _phase = registered ? 'registered' : 'unregistered');
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

  /// 即时校验通过（用户在「通过一些测试」阶段真实点击，服务端已签发
  /// Redis 凭证）→ 进入取名
  void _onCaptchaVerified(String ticket) {
    if (!mounted) return;
    setState(() {
      _captchaTicket = ticket;
      _phase = 'naming';
    });
  }

  /// 重置页面状态，重新检测
  void _reset() {
    // 已建号的注册只能重试激活；此时清掉请求 ID 或重新检测会把用户带到
    // “设备已注册”的短信分支，并丢失当前恢复上下文。
    if (PostStorage.isActivationPending()) {
      unawaited(_resumeActivation());
      return;
    }
    // 使旧检测请求立即失效（序号守卫），并丢弃旧的注册幂等 ID
    _checkSeq++;
    _registrationRequestId = null;
    unawaited(PostStorage.clearRegistrationRequestId());
    _nameController.clear();
    _tokenController.clear();
    _prePowNonce = null;
    _prePowChallenge = null;
    _captchaTicket = null;
    setState(() {
      _phase = 'checking';
      _error = null;
      _submitting = false;
      _renameError = null;
      _activationError = null;
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

      // 验证码在「通过一些测试」阶段即时二次校验通过并已换取 Redis
      // 凭证（风控 F001 等结论当场可见）；凭证 10 分钟有效，注册失败
      // 可复用，过期后重新确认时自动回到验证阶段重新获取
      final captchaTicket = _captchaTicket;
      if (captchaTicket == null) {
        setState(() => _phase = 'registering');
        return;
      }

      // 注册幂等 ID：同一次尝试的重试复用同一 ID；持久化以便
      // 应用重启后仍能凭 ID 向服务端查询响应丢失的注册结果
      final requestId =
          _registrationRequestId ??= const Uuid().v4();
      await PostStorage.saveRegistrationRequestId(requestId);

      var result = await ApiService.registerV2(
        userDisplayId: name,
        deviceFingerPrint: fp,
        captchaTicket: captchaTicket,
        verificationPow: PoWResult(
          challengeId: _prePowChallenge!.challengeId,
          nonce: _prePowNonce!,
        ),
        registrationRequestId: requestId,
      );

      if (!mounted) return;

      // 响应丢失恢复：超时/断连时服务端可能已建号，凭请求 ID 取回结果，
      // 避免用户重试产生第二个账号（CAPTCHA ticket / PoW 已消耗也能恢复）
      if (result == null && ApiService.isNetworkError(ApiService.lastError)) {
        result = await ApiService.fetchRegistrationResult(requestId);
        if (!mounted) return;
      }

      if (result == null) {
        final err = ApiService.lastError ?? '';
        // PoW 校验不消费 challenge；仅过期被拒（TTL 约 3 分钟）时重取
        if (err == 'PoW 验证失败') {
          _prePowChallenge = null;
          _prePowNonce = null;
        }
        // 验证凭证过期（10 分钟）才清空回到验证阶段；其余失败（如昵称
        // 占用）保留凭证，改名后可直接重试，无需再次完成验证
        if (err.contains('验证码已使用或过期')) {
          _captchaTicket = null;
        }
        setState(() => _renameError = _mapRegisterError(err));
        return;
      }

      // 若从已有账号环境进入注册，先清掉旧顶层 session，避免新的 token
      // 与旧账户 session 在激活失败窗口内形成交叉状态。
      await DeviceCredentialStore.clearSession();
      await DeviceCredentialStore.saveUserExternalToken(result.userToken);
      await DeviceCredentialStore.mergeKnownUserTokens([result.userToken]);
      await DeviceCredentialStore.saveDeviceSecret(result.deviceSecret);
      await DeviceCredentialStore.saveRegisteredFingerprint(
        jsonEncode(fp.toJson()),
      );
      await PostStorage.saveDisplayName(name);
      // 关键顺序：先记录「待激活」，再建绑/会话；只有 session 建立成功
      // 才置 registered=true。中断后重启应用会自动恢复激活流程。
      await PostStorage.setActivationPending(true);
      setState(() => _phase = 'activating');
      await _activatePending(result.userToken);
    } catch (e) {
      if (mounted) setState(() => _renameError = '网络异常：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 应用在 registerV2 已提交后退出时，凭持久化请求 ID 取回同一建号结果。
  /// 查不到结果时再回到设备检测；保留请求 ID，后续提交仍复用它。
  Future<void> _recoverInterruptedRegistration(String requestId) async {
    final result = await ApiService.fetchRegistrationResult(
      requestId,
      preserveLastError: false,
    );
    if (!mounted || _registrationRequestId != requestId) return;

    if (result == null) {
      if (ApiService.isNetworkError(ApiService.lastError)) {
        setState(() {
          _phase = 'failed';
          _error = ApiService.lastError;
        });
        return;
      }
      unawaited(_check());
      _preFetchPow();
      return;
    }

    try {
      final fp = await DeviceFingerprintService.collect();
      if (!mounted || _registrationRequestId != requestId) return;

      await DeviceCredentialStore.clearSession();
      await DeviceCredentialStore.saveUserExternalToken(result.userToken);
      await DeviceCredentialStore.mergeKnownUserTokens([result.userToken]);
      await DeviceCredentialStore.saveDeviceSecret(result.deviceSecret);
      await DeviceCredentialStore.saveRegisteredFingerprint(
        jsonEncode(fp.toJson()),
      );
      await PostStorage.setActivationPending(true);
      if (!mounted) return;
      setState(() => _phase = 'activating');
      await _activatePending(result.userToken);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = 'failed';
        _error = '恢复注册凭证失败，请重试';
      });
    }
  }

  /// 建绑 → 建会话；成功才置 registered=true，失败进入 activationPending
  /// （不重试 registerV2，不重复建号；token/secret 已落盘保留）
  Future<void> _activatePending(String userToken) async {
    final activated =
        await SessionService.instance.activateAfterRegister(userToken);
    if (!mounted) return;
    if (!activated) {
      setState(() {
        _phase = 'activationPending';
        _activationError = ApiService.lastError ?? '未知错误';
      });
      return;
    }
    await PostStorage.setActivationPending(false);
    await PostStorage.setRegistered(true);
    await PostStorage.clearRegistrationRequestId();
    _registrationRequestId = null;
    // 昵称已经不是注册完成的必要条件；后台同步，避免网络慢时注册页
    // 在实际成功后仍停留到 profile 请求超时。
    unawaited(_syncDisplayNameFromProfile());
    _finishSuccessfully();
  }

  /// 注册/登录的统一成功出口：把 true 返回给唤起页面，并广播账户展示变化。
  void _finishSuccessfully({bool notifyDisplayChange = true}) {
    if (!mounted) return;
    if (notifyDisplayChange) notifyAccountDisplayChanged();
    setState(() => _phase = 'done');
    Navigator.of(context).pop(true);
  }

  /// 启动恢复路径没有本地昵称输入值；激活成功后从服务端补齐。
  /// 昵称同步失败不应回滚已经成功的账号激活。
  Future<void> _syncDisplayNameFromProfile() async {
    try {
      final sessionId = await DeviceCredentialStore.getSessionId();
      final sessionSecret = await DeviceCredentialStore.getSessionSecret();
      if (sessionId == null || sessionSecret == null) return;
      final profile = await ApiService.getUserProfile(
        sessionId: sessionId,
        sessionSecret: sessionSecret,
      );
      if (profile != null && profile.userDisplayId.isNotEmpty) {
        await PostStorage.saveDisplayName(profile.userDisplayId);
      }
    } catch (e) {
      debugPrint('[RegisterPage] 后台同步昵称失败: $e');
    }
  }

  /// activationPending 阶段的「重试建立会话」/ 重启后自动恢复入口：
  /// 只调用 activateAfterRegister，绝不重新调用 registerV2
  Future<void> _resumeActivation() async {
    if (!mounted) return;
    setState(() {
      _phase = 'activating';
      _activationError = null;
    });
    final ok = await SessionService.instance.resumePendingActivation();
    if (!mounted) return;
    if (ok) {
      _registrationRequestId = null;
      // resumePendingActivation 内部已经广播过账户变化。
      _finishSuccessfully(notifyDisplayChange: false);
      return;
    }
    setState(() {
      _phase = 'activationPending';
      _activationError = ApiService.lastError ?? '网络连接失败';
    });
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
      _finishSuccessfully();
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
            // 已注册 — 两个继续路径按钮（同一行）+ 下一行小字
            if (_phase == 'registered') ...[
              _offsetLayer(
                vOffset: RegisterDimens.deviceRegisteredButtonVOffset,
                hOffset: RegisterDimens.deviceRegisteredButtonHOffset,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildRegisteredButton(colors, '找回原用户', _openSmsLogin),
                    SizedBox(
                      width: RegisterDimens.deviceRegisteredButtonGap,
                    ),
                    _buildRegisteredButton(colors, '注册/登录', _openSmsRegister),
                  ],
                ),
              ),
              _offsetLayer(
                vOffset: RegisterDimens.deviceRegisteredHintVOffset,
                hOffset: RegisterDimens.deviceRegisteredHintHOffset,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _contactQQ,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      '如需帮助，请联系我们',
                      style: TextStyle(
                        fontSize: RegisterDimens.deviceRegisteredHintFontSize,
                        color: onSurface.withValues(
                          alpha: RegisterDimens.deviceRegisteredHintAlpha,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
            // 验证码 WebView：注册流程开始即隐藏挂载（WebView 需在树上
            // 才跑 JS），SDK 提前完成渲染；registering 阶段原地显示，
            // 无等待感。透明区域同时预留拼图/滑块挑战面板的展开空间
            if (!widget.startAtLogin &&
                (_phase == 'checking' ||
                    _phase == 'unregistered' ||
                    _phase == 'registering'))
              _offsetLayer(
                vOffset: RegisterDimens.captchaVOffset,
                hOffset: RegisterDimens.captchaHOffset,
                ignorePointer: _phase != 'registering',
                child: Opacity(
                  opacity: _phase == 'registering' ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: RegisterDimens.captchaHPadding),
                    child: CaptchaView(
                      height: RegisterDimens.captchaHeight,
                      verifyHandler: ApiService.verifyCaptcha,
                      onVerified: _onCaptchaVerified,
                    ),
                  ),
                ),
              ),
            // 登录 — 找回用户（账户切换进入的登录不显示）
            if (_phase == 'login' && !widget.startAtLogin)
              _offsetLayer(
                vOffset: RegisterDimens.loginRecoverVOffset,
                hOffset: RegisterDimens.loginRecoverHOffset,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openSmsLogin,
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
            // 右上角重新加载（相对右上角偏移）；激活阶段隐藏，
            // 防止 _reset 丢弃待激活状态导致重复注册
            if (!widget.startAtLogin &&
                _phase != 'recovering' &&
                _phase != 'activating' &&
                _phase != 'activationPending')
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

  /// 已注册阶段：手机号找回 / 手机号注册新账号（默认路由，右侧滑入子页）。
  /// 子页 pop(true) 表示找回/注册成功，本页与 RegisterPage 其余流程一样
  /// 直接退出回到进入前的页面；取消则停留在本阶段可换另一条路径。
  Future<void> _openSmsLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SmsLoginPage()),
    );
    if (ok == true && mounted) _finishSuccessfully();
  }

  Future<void> _openSmsRegister() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SmsRegisterPage()),
    );
    if (!mounted) return;
    if (ok == true) {
      _finishSuccessfully();
      return;
    }
    // 子页中建号成功后用户可能在激活失败状态直接返回；父页接管恢复，
    // 避免仍停留在“该设备环境已注册”的旧页面状态。
    if (PostStorage.isActivationPending()) {
      await _resumeActivation();
    }
  }

  Future<void> _contactQQ() async {
    final uri = Uri.parse(Platform.isIOS
        ? 'mqq://card/show_pslcard?src_type=internal&version=1&uin=1541578716&card_type=person&source=qrcode'
        : 'mqqapi://card/show_pslcard?src_type=internal&version=1&uin=1541578716&card_type=person&source=qrcode');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// 已注册阶段的两条路径按钮（与注册按钮同款式）
  Widget _buildRegisteredButton(
    AppColors colors,
    String label,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: RegisterDimens.deviceRegisteredButtonWidth,
      height: RegisterDimens.deviceRegisteredButtonHeight,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.register.buttonBg,
          foregroundColor: colors.register.buttonText,
          // 文字到边框的内边距（左右/上下均可调；左右过大可能导致标签换行）
          padding: const EdgeInsets.symmetric(
            horizontal: RegisterDimens.deviceRegisteredButtonPaddingH,
            vertical: RegisterDimens.deviceRegisteredButtonPaddingV,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(RegisterDimens.deviceRegisteredButtonRadius),
            side: BorderSide(
              color: colors.register.buttonBorderColor,
              width: RegisterDimens.deviceRegisteredButtonBorderWidth,
            ),
          ),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: RegisterDimens.deviceRegisteredButtonFontSize,
              fontWeight: FontWeight.w500,
              letterSpacing: RegisterDimens.deviceRegisteredButtonLetterSpacing,
            )),
      ),
    );
  }

  Widget _buildPhase(AppColors colors, Color onSurface) {
    switch (_phase) {
      case 'failed':
        // 检测失败：明确展示原因与「重试检测」按钮，
        // 不依赖右上角刷新图标
        return _buildError(onSurface);
      case 'activating':
      case 'recovering':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: RegisterDimens.stepIconSize,
              height: RegisterDimens.stepIconSize,
              child: CircularProgressIndicator(
                strokeWidth: RegisterDimens.stepLoadingStrokeWidth,
                color: onSurface.withValues(alpha: RegisterDimens.errorAlpha),
              ),
            ),
          ],
        );
      case 'activationPending':
        return _buildActivationPending(colors, onSurface);
      case 'unregistered':
        return _error != null
            ? _buildError(onSurface)
            : _buildRegisterButton(colors);
      default:
        return const SizedBox.shrink();
    }
  }

  /// 注册成功但建绑/会话未完成：重试激活 / 短信找回 / 返回上一页，
  /// 不留无法继续的死路，也不会重复创建用户
  Widget _buildActivationPending(AppColors colors, Color onSurface) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '账号已创建，但建立会话失败\n${_activationError ?? ''}',
          style: TextStyle(
            fontSize: RegisterDimens.errorFontSize,
            color: onSurface.withValues(alpha: RegisterDimens.errorAlpha),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: RegisterDimens.errorRetryGap),
        _buildRegisteredButton(colors, '重试建立会话', _resumeActivation),
        const SizedBox(height: RegisterDimens.stepGap),
        _buildRegisteredButton(colors, '短信找回', _openSmsLogin),
        const SizedBox(height: RegisterDimens.stepGap),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(
            '返回上一页',
            style: TextStyle(
              fontSize: RegisterDimens.stepFontSize,
              color: onSurface.withValues(alpha: RegisterDimens.errorAlpha),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(Color onSurface) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_error ?? '检测失败，请重试',
            style: TextStyle(
              fontSize: RegisterDimens.errorFontSize,
              color: onSurface.withValues(alpha: RegisterDimens.errorAlpha),
            ),
            textAlign: TextAlign.center),
        const SizedBox(height: RegisterDimens.errorRetryGap),
        TextButton(onPressed: _check, child: const Text('重试检测')),
      ],
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
        const SizedBox(height: RegisterDimens.namingErrorGap),
        SizedBox(
          height: RegisterDimens.loginErrorAreaHeight,
          child: _renameError != null
              ? Text(
                  _renameError!,
                  style: TextStyle(
                    fontSize: RegisterDimens.stepFontSize,
                    color: colors.register.errorText,
                  ),
                  textAlign: TextAlign.center,
                )
              : null,
        ),
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
        const SizedBox(height: RegisterDimens.namingErrorGap),
        SizedBox(
          height: RegisterDimens.loginErrorAreaHeight,
          child: _renameError != null
              ? Text(
                  _renameError!,
                  style: TextStyle(
                    fontSize: RegisterDimens.stepFontSize,
                    color: colors.register.errorText,
                  ),
                  textAlign: TextAlign.center,
                )
              : null,
        ),
      ],
    );
  }

}
