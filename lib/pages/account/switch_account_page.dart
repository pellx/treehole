import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/bound_device.dart';
import '../../services/api.dart';
import '../../services/binding_cache.dart';
import '../../services/device_credential_store.dart';
import '../../services/session_service.dart';
import '../../services/timezone_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_dimens_accent.dart';
import '../../widgets/account_card.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_snackbar.dart';
import '../settings/settings_navigation.dart';
import 'register_page.dart';

/// 账户切换页：先展示本地缓存，再请求最新并按需更新
class SwitchAccountPage extends StatefulWidget {
  const SwitchAccountPage({super.key});

  @override
  State<SwitchAccountPage> createState() => _SwitchAccountPageState();
}

class _SwitchAccountPageState extends State<SwitchAccountPage> {
  List<BoundAccountInfo> _accounts = [];
  /// 当前登录账户的完整 user_token
  String? _currentToken;
  bool _switching = false;
  String? _error;
  /// 切号锁过期时间（来自 binding/last-switch）
  DateTime? _switchLockExpiresAt;

  bool get _switchLocked {
    final exp = _switchLockExpiresAt;
    return exp != null && exp.isAfter(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    final cached = BindingCache.getAccounts();
    if (cached.isNotEmpty) {
      _accounts = cached;
    }
    // 用户页已预取：首帧即用缓存锁状态，避免可点→锁定闪一下
    _switchLockExpiresAt = BindingCache.getSwitchLockExpiresAt();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final token = await DeviceCredentialStore.getUserExternalToken();
    if (mounted) {
      setState(() {
        _currentToken = token;
        _accounts = _withCurrentFirst(_accounts);
      });
    }
    // 进页立刻查可否切号，并与账户列表并行刷新
    await _refreshPage();
  }

  /// 当前账户置顶，其余保持相对顺序
  List<BoundAccountInfo> _withCurrentFirst(List<BoundAccountInfo> list) {
    if (list.isEmpty) return list;
    final current = <BoundAccountInfo>[];
    final others = <BoundAccountInfo>[];
    for (final a in list) {
      if (_isCurrent(a)) {
        current.add(a);
      } else {
        others.add(a);
      }
    }
    return [...current, ...others];
  }

  Future<void> _loadAccounts() async {
    final list = await BindingCache.refreshAccounts();
    if (!mounted) return;

    if (list == null) {
      setState(() {
        if (_accounts.isEmpty) {
          _error = ApiService.lastError ?? '加载账户失败';
        } else {
          _accounts = _withCurrentFirst(_accounts);
        }
      });
      return;
    }

    final next = _withCurrentFirst(list);
    final changed = !BindingCache.accountsEqual(_accounts, next);
    setState(() {
      _error = null;
      if (changed) _accounts = next;
    });
  }

  Future<void> _refreshPage() async {
    await Future.wait([
      _loadSwitchLock(),
      _loadAccounts(),
    ]);
  }

  Future<void> _loadSwitchLock() async {
    final exp = await BindingCache.refreshSwitchLock();
    if (!mounted) return;
    setState(() => _switchLockExpiresAt = exp);
  }

  bool _isCurrent(BoundAccountInfo a) {
    final current = _currentToken?.trim() ?? '';
    if (current.isEmpty) return false;
    final token = a.userToken.trim();
    if (token.isEmpty) return false;
    if (token == current) return true;
    // 缓存仅有遮罩预览时，与当前令牌遮罩后比对
    return AccountCard.maskToken(token) == AccountCard.maskToken(current);
  }

  AccountCardData _toCard(BoundAccountInfo a) {
    final id = a.userDisplayId?.trim();
    final isCurrent = _isCurrent(a);
    return AccountCardData(
      bindingId: a.bindingId,
      deviceId: a.deviceId,
      status: a.status,
      displayId: (id != null && id.isNotEmpty) ? id : '未命名账户',
      createdAt: a.createdAt,
      userToken: a.userToken,
      isCurrent: isCurrent,
      // 冷却中仅当前账户可交互
      enabled: isCurrent || !_switchLocked,
    );
  }

  Future<String?> _resolveFullToken(BoundAccountInfo a) async {
    final token = a.userToken.trim();
    if (token.isEmpty) return null;
    if (!token.contains('...')) return token;

    final known = await DeviceCredentialStore.getKnownUserTokens();
    final preview = AccountCard.maskToken(token);
    for (final t in known) {
      if (AccountCard.maskToken(t) == preview) return t;
    }
    final current = _currentToken?.trim();
    if (current != null &&
        current.isNotEmpty &&
        AccountCard.maskToken(current) == preview) {
      return current;
    }
    return null;
  }

  Future<bool> _confirmSwitch(String displayId) async {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const message = '是否要切换到「{id}」？\n每两天仅可进行一次切换';
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
                message.replaceFirst('{id}', displayId),
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
    return confirmed == true;
  }

  String _loginErrorText(String? raw) {
    return switch (raw) {
      'TRANSFER_REQUIRED' => '需先在原设备发起转移申请（15 分钟内有效）',
      'TRANSFER_INVALID' => '转移申请无效或已过期，请在原设备重新申请',
      'DEVICE_COOLDOWN' => '解绑冷却中，暂不可登录',
      'DEVICE_SESSION_LOCKED' => '本机切号锁定中（约 2 天），暂不可切换到其他账户',
      'RATE_LIMITED' => '操作过于频繁，请稍后再试',
      _ => raw ?? '登录失败',
    };
  }

  String _formatSwitchAvailableAt(DateTime at) {
    final formatted = TimezoneService.formatDateTime(at);
    return '可于 $formatted 再次切换账户';
  }

  Future<void> _onAccountTap(BoundAccountInfo a) async {
    HapticFeedback.lightImpact();
    if (_switching) return;
    final card = _toCard(a);
    if (!card.enabled) return;
    if (card.isCurrent) {
      if (!mounted) return;
      showAppSnackBar(context, message: '已是当前账户', duration: const Duration(seconds: 1));
      return;
    }

    final ok = await _confirmSwitch(card.displayId);
    if (!ok || !mounted) return;

    HapticFeedback.mediumImpact();

    final token = await _resolveFullToken(a);
    if (!mounted) return;
    if (token == null) {
      showAppSnackBar(context, message: '令牌不可用，请下拉刷新后重试');
      return;
    }

    setState(() => _switching = true);
    final success = await SessionService.instance.switchToAccount(
      token,
      displayNameHint: a.userDisplayId,
    );
    if (!mounted) return;
    setState(() => _switching = false);

    if (!success) {
      showAppSnackBar(
        context,
        message: _loginErrorText(ApiService.lastError),
      );
      await _loadSwitchLock();
      return;
    }

    setState(() {
      _currentToken = token;
      _accounts = _withCurrentFirst(_accounts);
    });
    await _loadSwitchLock();
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: '已切换账户',
      duration: const Duration(seconds: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final loginDisabled = _switching || _switchLocked;

    Widget body;
    if (_error != null && _accounts.isEmpty) {
      body = AppErrorState(
        message: _error!,
        onRetry: _refreshPage,
      );
    } else if (_accounts.isEmpty) {
      body = const AppEmptyState(
        message: '暂无绑定账户',
        icon: Icons.account_circle_outlined,
      );
    } else {
      body = Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshPage,
              child: ListView.separated(
                padding: const EdgeInsets.all(AccentDimens.pagePadding),
                itemCount: _accounts.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AccentDimens.deviceCardGap),
                itemBuilder: (context, index) {
                  final a = _accounts[index];
                  return AccountCard(
                    data: _toCard(a),
                    onTap: () => _onAccountTap(a),
                  );
                },
              ),
            ),
          ),
          if (_switchLocked && _switchLockExpiresAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AccentDimens.switchLockTipHPadding,
                0,
                AccentDimens.switchLockTipHPadding,
                AccentDimens.switchLockTipBottom,
              ),
              child: Text(
                _formatSwitchAvailableAt(_switchLockExpiresAt!),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AccentDimens.switchLockTipFontSize,
                  height: AccentDimens.switchLockTipLineHeight,
                  color: onSurface.withValues(
                    alpha: AccentDimens.switchLockTipAlpha,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return AppScaffold(
      title: '账户切换',
      body: body,
      trailing: Padding(
        padding: const EdgeInsets.only(
            right: AppDimens.postCreateSubmitMarginRight),
        child: SizedBox(
          height: AppDimens.postCreateSubmitHeight,
          child: ElevatedButton(
            onPressed: loginDisabled ? null : _openLoginUser,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.postCreate.submitBg,
              foregroundColor: colors.postCreate.submitText,
              disabledBackgroundColor:
                  colors.postCreate.submitBg.withValues(alpha: 0.35),
              disabledForegroundColor:
                  colors.postCreate.submitText.withValues(alpha: 0.45),
              elevation: 0,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.postCreateSubmitHPadding),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                    AppDimens.postCreateSubmitRadius),
              ),
            ),
            child: const Text('登录用户'),
          ),
        ),
      ),
    );
  }

  Future<void> _openLoginUser() async {
    await Navigator.of(context).push(
      bottomUpRoute(const RegisterPage(startAtLogin: true)),
    );
    if (!mounted) return;
    final token = await DeviceCredentialStore.getUserExternalToken();
    setState(() {
      _currentToken = token;
      _accounts = _withCurrentFirst(_accounts);
    });
    await _refreshPage();
  }
}
