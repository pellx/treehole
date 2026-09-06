import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api.dart';
import '../../services/account_display.dart';
import '../../services/avatar_storage.dart';
import '../../services/binding_cache.dart';
import '../../services/session_service.dart';
import '../../services/storage.dart';
import '../../services/timezone_service.dart';
import '../../services/device_credential_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens_accent.dart';
import '../settings/settings_navigation.dart';
import '../settings/settings_page.dart';
import '../settings/version_page.dart';
import '../../widgets/app_snackbar.dart';
import 'device_binding_page.dart';
import 'register_page.dart';
import 'switch_account_page.dart';
import 'user_profile_page.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _editingName = false;
  bool _submittingName = false;
  bool _resettingToken = false;
  String? _error;
  String _externalToken = '';
  Uint8List? _avatarBytes;
  DateTime? _displayIdChangedAt;

  /// 用户页打开时预取绑定列表 + 切号锁；进切换页前等待完成以免闪烁
  Future<void>? _prefetchFuture;

  @override
  void initState() {
    super.initState();
    _nameController.text =
        PostStorage.getDisplayName() ?? PostStorage.getUserName();
    _nameFocus.addListener(_onNameFocusChange);
    _reloadAccountUi();
    // 预取绑定列表与切号锁，进入子页时首帧即可正确展示
    _prefetchFuture = BindingCache.prefetchAll();
    accountDisplayEpoch.addListener(_onAccountDisplayChanged);
  }

  void _onAccountDisplayChanged() {
    if (!mounted) return;
    _reloadAccountUi();
    _prefetchFuture = BindingCache.prefetchAll();
  }

  void _reloadAccountUi() {
    _nameController.text =
        PostStorage.getDisplayName() ?? PostStorage.getUserName();
    _loadExternalToken();
    _loadAvatar();
    _loadProfile();
  }

  /// 点到输入框外导致失焦时退出编辑；延后一帧以免与「提交」按钮抢序
  void _onNameFocusChange() {
    if (_nameFocus.hasFocus || !_editingName || _submittingName) return;
    Future.microtask(() {
      if (!mounted || _nameFocus.hasFocus || !_editingName || _submittingName) {
        return;
      }
      _exitNameEditing();
    });
  }

  Future<void> _loadAvatar() async {
    final bytes = await AvatarStorage.load();
    if (mounted) setState(() => _avatarBytes = bytes);
  }

  /// 从存储选择一张图片作为头像并保存到本地（与发帖页相同的文件选择方式）
  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      await AvatarStorage.save(bytes);
      if (mounted) setState(() => _avatarBytes = bytes);
    } catch (e) {
      debugPrint('[UserPage] 更换头像失败: $e');
      if (mounted) {
        showAppSnackBar(
          context,
          message: '头像更换失败',
          duration: const Duration(seconds: 1),
        );
      }
    }
  }

  Future<void> _loadExternalToken() async {
    final token = await DeviceCredentialStore.getUserExternalToken();
    if (mounted) setState(() => _externalToken = token ?? '');
  }

  Future<({int id, String secret})?> _readySession() async {
    final ok = await SessionService.instance.ensureSession();
    if (!ok) return null;
    final id = await DeviceCredentialStore.getSessionId();
    final secret = await DeviceCredentialStore.getSessionSecret();
    if (id == null || secret == null) return null;
    return (id: id, secret: secret);
  }

  Future<void> _loadProfile() async {
    final session = await _readySession();
    if (session == null) {
      debugPrint('[UserPage] profile: session 未就绪');
      return;
    }
    final profile = await ApiService.getUserProfile(
      sessionId: session.id,
      sessionSecret: session.secret,
    );
    if (!mounted || profile == null) return;
    setState(() {
      if (profile.userDisplayId.isNotEmpty) {
        _nameController.text = profile.userDisplayId;
      }
      _displayIdChangedAt = profile.displayIdChangedAt;
    });
    if (profile.userDisplayId.isNotEmpty) {
      await PostStorage.saveDisplayName(profile.userDisplayId);
    }
  }

  @override
  void dispose() {
    accountDisplayEpoch.removeListener(_onAccountDisplayChanged);
    _nameFocus.removeListener(_onNameFocusChange);
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String _formatRenameDate(DateTime dt) {
    return TimezoneService.formatDateTime(dt, showTime: false);
  }

  /// 冷却结束日：优先用错误体 next_rename_at，否则上次改名 + 14 天
  DateTime? _nextRenameAt() {
    final fromApi = ApiService.lastNextRenameAt;
    if (fromApi != null) return fromApi;
    final last = ApiService.lastDisplayIdChangedAt ?? _displayIdChangedAt;
    if (last == null) return null;
    return last.add(const Duration(days: 14));
  }

  String _mapRenameError(String? raw) {
    return switch (raw) {
      'NAME_EMPTY' => '名字不能为空',
      'NAME_UNCHANGED' => '名字未改变',
      'RENAME_TOO_FREQUENT' => () {
        final next = _nextRenameAt();
        if (next == null) return '改名冷却中，每两周可改一次';
        return '改名冷却中，每两周可改一次\n下一次可更改日期：${_formatRenameDate(next)}';
      }(),
      'NAME_TAKEN' => '用户名被占用',
      null => '改名失败',
      _ => raw,
    };
  }

  /// 「更改」→ 进入原位编辑；「提交」→ 调后端改名
  Future<void> _onNameButtonTap() async {
    if (!_editingName) {
      setState(() {
        _editingName = true;
        _error = null;
      });
      _nameFocus.requestFocus();
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _exitNameEditing(error: '名字不能为空');
      return;
    }
    final current = PostStorage.getDisplayName() ?? PostStorage.getUserName();
    if (name == current) {
      _nameFocus.unfocus();
      setState(() {
        _editingName = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _submittingName = true;
      _error = null;
    });
    try {
      final session = await _readySession();
      if (session == null) {
        if (mounted) _exitNameEditing(error: '会话验证失败，请稍后重试');
        return;
      }
      final result = await ApiService.rename(
        sessionId: session.id,
        sessionSecret: session.secret,
        newName: name,
      );
      if (!mounted) return;
      if (result == null) {
        final changedAt = ApiService.lastDisplayIdChangedAt;
        if (changedAt != null) _displayIdChangedAt = changedAt;
        _exitNameEditing(error: _mapRenameError(ApiService.lastError));
        return;
      }
      await PostStorage.saveDisplayName(result.userDisplayId);
      _nameController.text = result.userDisplayId;
      setState(() {
        _editingName = false;
        _displayIdChangedAt = result.displayIdChangedAt ?? DateTime.now();
      });
    } catch (e) {
      if (mounted) _exitNameEditing(error: '网络异常：$e');
    } finally {
      if (mounted) setState(() => _submittingName = false);
    }
  }

  /// 提交失败后退出编辑态，恢复为上次已保存名字
  void _exitNameEditing({String? error}) {
    _nameFocus.unfocus();
    _nameController.text =
        PostStorage.getDisplayName() ?? PostStorage.getUserName();
    setState(() {
      _editingName = false;
      _error = error;
    });
  }

  void _copyToken() {
    if (_externalToken.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _externalToken));
    showAppSnackBar(
      context,
      message: '已复制用户令牌',
      duration: const Duration(seconds: 1),
    );
  }

  Future<void> _confirmChangeToken() async {
    if (_resettingToken) return;
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colors.common.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AccentDimens.dialogRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AccentDimens.dialogPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '是否确认更改用户令牌？更改之后原令牌作废，如需登录，需使用新签发令牌',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AccentDimens.dialogMessageFontSize,
                  height: AccentDimens.dialogMessageLineHeight,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: AccentDimens.dialogActionsTopGap),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: AccentDimens.dialogActionHeight,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: TextButton.styleFrom(
                          foregroundColor: onSurface.withValues(
                            alpha: AccentDimens.dialogCancelTextAlpha,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AccentDimens.dialogActionHPadding,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AccentDimens.dialogActionRadius,
                            ),
                          ),
                          textStyle: const TextStyle(
                            fontSize: AccentDimens.dialogActionFontSize,
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AccentDimens.dialogActionGap),
                  Expanded(
                    child: SizedBox(
                      height: AccentDimens.dialogActionHeight,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.postCreate.submitBg,
                          foregroundColor: colors.postCreate.submitText,
                          elevation: 0,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AccentDimens.dialogActionHPadding,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AccentDimens.dialogActionRadius,
                            ),
                          ),
                          textStyle: const TextStyle(
                            fontSize: AccentDimens.dialogActionFontSize,
                          ),
                        ),
                        child: const Text('确认'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) await _onChangeToken();
  }

  Future<void> _onChangeToken() async {
    if (_resettingToken) return;
    setState(() => _resettingToken = true);
    try {
      final session = await _readySession();
      if (session == null) {
        if (mounted) {
          showAppSnackBar(
            context,
            message: '会话验证失败，请稍后重试',
            duration: const Duration(seconds: 2),
          );
        }
        return;
      }
      final result = await ApiService.resetUserToken(
        sessionId: session.id,
        sessionSecret: session.secret,
      );
      if (!mounted) return;
      if (result == null) {
        showAppSnackBar(
          context,
          message: ApiService.lastError ?? '令牌重置失败',
          duration: const Duration(seconds: 2),
        );
        return;
      }
      final oldToken = await DeviceCredentialStore.getUserExternalToken();
      if (oldToken != null) {
        await DeviceCredentialStore.removeKnownUserToken(oldToken);
      }
      await DeviceCredentialStore.saveUserExternalToken(result.userToken);
      await DeviceCredentialStore.mergeKnownUserTokens([result.userToken]);
      setState(() => _externalToken = result.userToken);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: '用户令牌已重置',
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: '网络异常：$e',
          duration: const Duration(seconds: 2),
        );
      }
    } finally {
      if (mounted) setState(() => _resettingToken = false);
    }
  }

  Future<void> _openDeviceBinding() async {
    HapticFeedback.lightImpact();
    // 未注册账户时先走注册流程
    if (!PostStorage.isRegistered()) {
      await Navigator.of(context).push(bottomUpRoute(const RegisterPage()));
      if (!mounted) return;
      _reloadAccountUi();
      _prefetchFuture = BindingCache.prefetchAll();
      return;
    }
    Navigator.of(context).push(topDownRoute(const DeviceBindingPage()));
  }

  void _openSettings() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(topDownRoute(const SettingsPage()));
  }

  void _openVersionUpdate() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(topDownRoute(const VersionPage()));
  }

  Future<void> _openLoginOther() async {
    HapticFeedback.lightImpact();
    // 未注册账户时先走注册流程
    if (!PostStorage.isRegistered()) {
      await Navigator.of(context).push(bottomUpRoute(const RegisterPage()));
      if (!mounted) return;
      _reloadAccountUi();
      _prefetchFuture = BindingCache.prefetchAll();
      return;
    }
    final pending = _prefetchFuture;
    if (pending != null) {
      try {
        await pending.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.of(context).push(topDownRoute(const SwitchAccountPage()));
    if (!mounted) return;
    // 切号后立刻用本地已写入的昵称刷新，再拉 profile/令牌/头像
    _reloadAccountUi();
    _prefetchFuture = BindingCache.prefetchAll();
  }

  /// 退出登录：确认后注销服务端 session 并清空本机登录态，跳转注册/登录页
  Future<void> _confirmAndLogout() async {
    HapticFeedback.lightImpact();
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const message = '退出后本机将清除该账户的登录凭证\n'
        '再次使用需重新注册或短信验证码登录\n是否退出登录？';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colors.common.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AccentDimens.dialogRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AccentDimens.dialogPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AccentDimens.dialogMessageFontSize,
                  height: AccentDimens.dialogMessageLineHeight,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: AccentDimens.dialogActionsTopGap),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: AccentDimens.dialogActionHeight,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: TextButton.styleFrom(
                          foregroundColor: onSurface.withValues(
                              alpha: AccentDimens.dialogCancelTextAlpha),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AccentDimens.dialogActionHPadding),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AccentDimens.dialogActionRadius),
                          ),
                          textStyle: const TextStyle(
                              fontSize: AccentDimens.dialogActionFontSize),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AccentDimens.dialogActionGap),
                  Expanded(
                    child: SizedBox(
                      height: AccentDimens.dialogActionHeight,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.postCreate.submitBg,
                          foregroundColor: colors.postCreate.submitText,
                          elevation: 0,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AccentDimens.dialogActionHPadding),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AccentDimens.dialogActionRadius),
                          ),
                          textStyle: const TextStyle(
                              fontSize: AccentDimens.dialogActionFontSize),
                        ),
                        child: const Text('退出'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    await SessionService.instance.logout();
    if (!mounted) return;
    _reloadAccountUi();
    _prefetchFuture = BindingCache.prefetchAll();
    await Navigator.of(context).push(bottomUpRoute(const RegisterPage()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isRegistered = PostStorage.isRegistered();

    final pageBg = isLight
        ? const Color(0xFFF2F2F2)
        : const Color(0xFF111111);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: pageBg,
        statusBarIconBrightness:
            isLight ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: pageBg,
        body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_editingName && !_submittingName) _exitNameEditing();
        },
        child: SafeArea(
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                // 不设垂直 padding，让首尾卡片贴边：内容放得下时 scrollExtent
                // 与视口等长（min==max），ClampingScrollPhysics 会直接禁用拖动，
                // 不会再出现拉伸形变
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _profileCard(colors, onSurface),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 12,
                                left: 4,
                                right: 4,
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.register.errorText,
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),
                          if (isRegistered) ...[
                            _sectionTitle('账户安全', onSurface),
                            _sectionCard(colors, [
                              _tokenTile(colors, onSurface),
                              _navDivider(colors),
                              _resetTokenTile(colors, onSurface),
                            ]),
                            const SizedBox(height: 20),
                          ],
                          _sectionTitle('应用', onSurface),
                          _sectionCard(colors, [
                            _navTile(
                              colors,
                              onSurface,
                              '设置',
                              Icons.settings_outlined,
                              _openSettings,
                            ),
                            if (Platform.isAndroid) ...[
                              _navDivider(colors),
                              _navTile(
                                colors,
                                onSurface,
                                '更新',
                                Icons.system_update_outlined,
                                _openVersionUpdate,
                              ),
                            ],
                          ]),
                          const SizedBox(height: 20),
                          if (isRegistered) ...[
                            _sectionTitle('账户管理', onSurface),
                            _sectionCard(colors, [
                              _navTile(
                                colors,
                                onSurface,
                                '设备绑定',
                                Icons.devices_outlined,
                                _openDeviceBinding,
                              ),
                              _navDivider(colors),
                              _navTile(
                                colors,
                                onSurface,
                                '账户切换',
                                Icons.switch_account_outlined,
                                _openLoginOther,
                              ),
                              _navDivider(colors),
                              _navTile(
                                colors,
                                onSurface,
                                '退出登录',
                                Icons.logout_outlined,
                                _confirmAndLogout,
                              ),
                            ]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  }

  // ---- 个人资料卡片 ----

  void _openProfile() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      topDownRoute(
        UserProfilePage(
          avatarBytes: _avatarBytes,
          name: _nameController.text,
          token: _externalToken,
        ),
      ),
    );
  }

  Future<void> _openRegister() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(bottomUpRoute(const RegisterPage()));
    if (!mounted) return;
    _reloadAccountUi();
    _prefetchFuture = BindingCache.prefetchAll();
  }

  Widget _profileCard(AppColors colors, Color onSurface) {
    final isRegistered = PostStorage.isRegistered();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.common.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: isRegistered ? _pickAvatar : _openRegister,
            child: CircleAvatar(
              radius: 36,
              backgroundColor: colors.common.idTint.withValues(alpha: 0.2),
              backgroundImage: _avatarBytes != null
                  ? MemoryImage(_avatarBytes!) as ImageProvider
                  : const AssetImage('assets/420px-Transparent_Akkarin.jpg'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isRegistered ? _openProfile : _openRegister,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isRegistered) ...[
                          _editingName
                              ? TextField(
                                  controller: _nameController,
                                  focusNode: _nameFocus,
                                  maxLength: AccentDimens.nameMaxLength,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: onSurface,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    counterText: '',
                                    hintText: '昵称',
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: onSurface.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: colors.common.green,
                                      ),
                                    ),
                                  ),
                                )
                              : Text(
                                  _nameController.text.isEmpty
                                      ? '未设置昵称'
                                      : _nameController.text,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                          const SizedBox(height: 6),
                          if (_submittingName)
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.common.green,
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: _onNameButtonTap,
                              child: Text(
                                _editingName ? '保存' : '点击修改昵称',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _editingName
                                      ? colors.common.green
                                      : onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                        ] else ...[
                          Text(
                            '注册用户',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '点击前往注册',
                            style: TextStyle(
                              fontSize: 13,
                              color: onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!_editingName)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.chevron_right,
                        size: 21,
                        color: colors.common.arrowIcon,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_editingName && isRegistered)
            IconButton(
              icon: Icon(
                Icons.close,
                size: 20,
                color: onSurface.withValues(alpha: 0.5),
              ),
              onPressed: _exitNameEditing,
            ),
        ],
      ),
    );
  }

  // ---- 分组卡片 ----

  Widget _sectionTitle(String title, Color onSurface) => Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: onSurface.withValues(alpha: 0.5),
      ),
    ),
  );

  Widget _sectionCard(AppColors colors, List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: colors.common.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(children: children),
  );

  // ---- 列表行 ----

  Widget _tokenTile(AppColors colors, Color onSurface) {
    const head = AccentDimens.tokenHeadChars;
    const tail = AccentDimens.tokenTailChars;
    final display = _externalToken.isEmpty
        ? '—'
        : (_externalToken.length > head + tail
              ? '${_externalToken.substring(0, head)}...'
                    '${_externalToken.substring(_externalToken.length - tail)}'
              : _externalToken);

    return _listTile(
      colors,
      onSurface,
      icon: Icons.key_outlined,
      title: '用户令牌',
      onTap: _copyToken,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            display,
            style: TextStyle(
              fontSize: 14,
              color: onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.copy_outlined, size: 16, color: colors.common.green),
        ],
      ),
    );
  }

  Widget _resetTokenTile(AppColors colors, Color onSurface) => _listTile(
    colors,
    onSurface,
    icon: Icons.refresh,
    title: '令牌重置',
    onTap: _resettingToken ? null : _confirmChangeToken,
    trailing: _resettingToken
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.common.green,
            ),
          )
        : null,
  );

  Widget _navTile(
    AppColors colors,
    Color onSurface,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) => _listTile(
    colors,
    onSurface,
    icon: icon,
    title: title,
    onTap: () {
      HapticFeedback.lightImpact();
      onTap();
    },
    trailing: null,
  );

  Widget _listTile(
    AppColors colors,
    Color onSurface, {
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colors.common.green),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(fontSize: 16, color: onSurface)),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _navDivider(AppColors colors) => Divider(
    height: 1,
    thickness: 0.5,
    indent: 50,
    color: colors.common.divider,
  );
}
