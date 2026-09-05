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
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading_indicator.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/device_card.dart';

/// 设备绑定页：先展示本地缓存，再请求最新并按需更新
class DeviceBindingPage extends StatefulWidget {
  const DeviceBindingPage({super.key});

  @override
  State<DeviceBindingPage> createState() => _DeviceBindingPageState();
}

class _DeviceBindingPageState extends State<DeviceBindingPage> {
  List<DeviceCardData> _devices = [];

  /// 本机 device_id，用于置顶与绿点
  int? _localDeviceId;

  /// 仅在无缓存且首次请求未完成时显示加载
  bool _loading = false;
  bool _transferring = false;

  /// 已确认「进行主设备迁移」、等待点选目标
  bool _pickingPrimaryTarget = false;
  int? _primaryPendingDeviceId;
  DateTime? _primaryTransferExecuteAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _primaryPendingDeviceId = BindingCache.getPrimaryPendingDeviceId();
    _primaryTransferExecuteAt = BindingCache.getPrimaryTransferExecuteAt();
    if (_primaryPendingDeviceId != null) {
      _pickingPrimaryTarget = true;
    }
    final cached = BindingCache.getDevices();
    if (cached.isNotEmpty) {
      _devices = _decorate(cached.map(_toCard).toList());
    } else {
      _loading = true;
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final localId = await DeviceCredentialStore.getDeviceId();
    if (mounted) {
      setState(() {
        _localDeviceId = localId;
        _devices = _decorate(
          _withCurrentFirst(_devices.map(_refreshCurrentFlag).toList()),
        );
      });
    }
    await _loadDevices();
  }

  Future<({int id, String secret})?> _readySession() async {
    final ok = await SessionService.instance.ensureSession();
    if (!ok) return null;
    final id = await DeviceCredentialStore.getSessionId();
    final secret = await DeviceCredentialStore.getSessionSecret();
    if (id == null || secret == null) return null;
    return (id: id, secret: secret);
  }

  DeviceCardData _toCard(BoundDeviceInfo info) {
    final fallbackName = (info.deviceName?.trim().isNotEmpty == true)
        ? info.deviceName!.trim()
        : (info.model?.trim().isNotEmpty == true ? info.model!.trim() : '设备');
    return DeviceCardData(
      bindingId: info.bindingId,
      deviceId: info.deviceId,
      status: info.status,
      unbindRequestedAt: info.unbindRequestedAt,
      unbindExecuteAt: info.unbindExecuteAt ?? info.effectiveUnbindExecuteAt,
      customName: info.deviceDisplayName,
      deviceName: fallbackName,
      brand: info.brand?.trim().isNotEmpty == true ? info.brand!.trim() : '未知',
      model: info.model?.trim().isNotEmpty == true ? info.model!.trim() : '未知',
      os: info.os?.trim().isNotEmpty == true ? info.os!.trim() : '未知',
      abi: info.abi?.trim().isNotEmpty == true ? info.abi!.trim() : '未知',
      isCurrent: _localDeviceId != null && info.deviceId == _localDeviceId,
      isPrimary: info.isPrimary,
      isPrimaryPending: info.isPrimaryPending,
    );
  }

  DeviceCardData _refreshCurrentFlag(DeviceCardData d) {
    return d.copyWith(
      isCurrent: _localDeviceId != null && d.deviceId == _localDeviceId,
    );
  }

  /// 按主设备 / 选目标态刷新右侧操作
  List<DeviceCardData> _decorate(List<DeviceCardData> list) {
    final localIsPrimary = list.any((d) => d.isCurrent && d.isPrimary);
    final serverPending =
        _primaryPendingDeviceId != null || list.any((d) => d.isPrimaryPending);
    final showCancelOnPrimary = _pickingPrimaryTarget || serverPending;
    // 仅本地选目标且尚未提交时，其它卡显示星标；已提交待生效则只留取消
    final showTransferStars =
        _pickingPrimaryTarget && !serverPending && localIsPrimary;
    return list
        .map(
          (d) => d.copyWith(
            action: _actionFor(
              d,
              localIsPrimary: localIsPrimary,
              showCancelOnPrimary: showCancelOnPrimary,
              showTransferStars: showTransferStars,
            ),
          ),
        )
        .toList();
  }

  DeviceCardAction _actionFor(
    DeviceCardData d, {
    required bool localIsPrimary,
    required bool showCancelOnPrimary,
    required bool showTransferStars,
  }) {
    if (d.isUnbindPending) return DeviceCardAction.cancelUnbind;
    if (d.isPrimary) {
      if (showCancelOnPrimary) return DeviceCardAction.primaryCancel;
      if (localIsPrimary) return DeviceCardAction.primaryStar;
      return DeviceCardAction.primaryStarReadonly;
    }
    if (d.isPrimaryPending) return DeviceCardAction.primaryStarReadonly;
    if (showTransferStars) return DeviceCardAction.transferTarget;
    return DeviceCardAction.delete;
  }

  /// 本机设备置顶，其余保持相对顺序
  List<DeviceCardData> _withCurrentFirst(List<DeviceCardData> list) {
    if (list.isEmpty) return list;
    final current = <DeviceCardData>[];
    final others = <DeviceCardData>[];
    for (final d in list) {
      if (d.isCurrent) {
        current.add(d);
      } else {
        others.add(d);
      }
    }
    return [...current, ...others];
  }

  bool _cardListEqual(List<DeviceCardData> a, List<DeviceCardData> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].bindingId != b[i].bindingId ||
          a[i].deviceId != b[i].deviceId ||
          a[i].status != b[i].status ||
          a[i].unbindRequestedAt != b[i].unbindRequestedAt ||
          a[i].unbindExecuteAt != b[i].unbindExecuteAt ||
          a[i].customName != b[i].customName ||
          a[i].deviceName != b[i].deviceName ||
          a[i].brand != b[i].brand ||
          a[i].model != b[i].model ||
          a[i].os != b[i].os ||
          a[i].abi != b[i].abi ||
          a[i].isCurrent != b[i].isCurrent ||
          a[i].isPrimary != b[i].isPrimary ||
          a[i].isPrimaryPending != b[i].isPrimaryPending ||
          a[i].action != b[i].action) {
        return false;
      }
    }
    return true;
  }

  Future<void> _persistDevicesFromCards() async {
    await BindingCache.saveDevices(
      _devices
          .map(
            (d) => BoundDeviceInfo(
              bindingId: d.bindingId,
              deviceId: d.deviceId,
              status: d.status,
              unbindRequestedAt: d.unbindRequestedAt,
              unbindExecuteAt: d.unbindExecuteAt,
              deviceDisplayName: d.customName,
              deviceName: d.deviceName,
              brand: d.brand,
              model: d.model,
              os: d.os,
              abi: d.abi,
              isPrimary: d.isPrimary,
              isPrimaryPending: d.isPrimaryPending,
            ),
          )
          .toList(),
    );
  }

  Future<void> _loadDevices() async {
    // 刷新时同步本机 id，避免缓存阶段绿点/排序缺失
    _localDeviceId ??= await DeviceCredentialStore.getDeviceId();
    final list = await BindingCache.refreshDevices();
    if (!mounted) return;

    if (list == null) {
      setState(() {
        _loading = false;
        if (_devices.isEmpty) {
          _error = ApiService.lastError ?? '加载设备失败';
        } else {
          _devices = _decorate(
            _withCurrentFirst(_devices.map(_refreshCurrentFlag).toList()),
          );
        }
      });
      return;
    }

    final pendingId = BindingCache.getPrimaryPendingDeviceId();
    final executeAt = BindingCache.getPrimaryTransferExecuteAt();
    final next = _decorate(_withCurrentFirst(list.map(_toCard).toList()));
    final changed = !_cardListEqual(_devices, next);
    setState(() {
      _loading = false;
      _error = null;
      _primaryPendingDeviceId = pendingId;
      _primaryTransferExecuteAt = executeAt;
      if (pendingId != null) {
        _pickingPrimaryTarget = true;
      }
      if (changed || pendingId != null) {
        _devices = next;
      } else {
        _devices = _decorate(_devices);
      }
    });
  }

  String _primaryErrorText(String? raw) {
    return switch (raw) {
      'PRIMARY_DEVICE_PROTECTED' => '主设备不可解绑，请先迁移主设备',
      'PRIMARY_TRANSFER_REQUIRES_PRIMARY_DEVICE' => '仅可在主设备上发起迁移',
      'PRIMARY_TRANSFER_ALREADY_PENDING' => '已有主设备迁移进行中',
      'ALREADY_PRIMARY_DEVICE' => '该设备已是主设备',
      'DEVICE_NOT_BOUND' => '设备未绑定',
      null || '' => '操作失败',
      _ => raw,
    };
  }

  Future<void> _onPrimaryStar() async {
    setState(() {
      _pickingPrimaryTarget = true;
      _devices = _decorate(_devices);
    });
  }

  Future<void> _onPrimaryCancel() async {
    final hasServerPending =
        _primaryPendingDeviceId != null ||
        _devices.any((d) => d.isPrimaryPending);
    if (!hasServerPending) {
      setState(() {
        _pickingPrimaryTarget = false;
        _devices = _decorate(_devices);
      });
      return;
    }

    final session = await _readySession();
    if (session == null) {
      if (!mounted) return;
      showAppSnackBar(context, message: '会话验证失败，请稍后重试');
      return;
    }
    final ok = await ApiService.cancelPrimaryTransfer(
      sessionId: session.id,
      sessionSecret: session.secret,
    );
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(
        context,
        message: _primaryErrorText(ApiService.lastError),
      );
      return;
    }
    setState(() {
      _pickingPrimaryTarget = false;
      _primaryPendingDeviceId = null;
      _primaryTransferExecuteAt = null;
    });
    await BindingCache.saveDevicesResult(
      BoundDevicesResult(
        devices: _devices
            .map(
              (d) => BoundDeviceInfo(
                bindingId: d.bindingId,
                deviceId: d.deviceId,
                status: d.status,
                unbindRequestedAt: d.unbindRequestedAt,
                unbindExecuteAt: d.unbindExecuteAt,
                deviceDisplayName: d.customName,
                deviceName: d.deviceName,
                brand: d.brand,
                model: d.model,
                os: d.os,
                abi: d.abi,
                isPrimary: d.isPrimary,
                isPrimaryPending: false,
              ),
            )
            .toList(),
      ),
    );
    await _loadDevices();
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: '已取消主设备迁移',
      duration: const Duration(seconds: 1),
    );
  }

  Future<void> _onTransferTarget(int index) async {
    final device = _devices[index];
    final session = await _readySession();
    if (session == null) {
      if (!mounted) return;
      showAppSnackBar(context, message: '会话验证失败，请稍后重试');
      return;
    }
    final result = await ApiService.requestPrimaryTransfer(
      sessionId: session.id,
      sessionSecret: session.secret,
      bindingId: device.bindingId,
    );
    if (!mounted) return;
    if (result == null) {
      showAppSnackBar(
        context,
        message: _primaryErrorText(ApiService.lastError),
      );
      return;
    }
    setState(() {
      _pickingPrimaryTarget = true;
      _primaryPendingDeviceId = result.primaryDevicePendingId;
      _primaryTransferExecuteAt = result.primaryTransferExecuteAt;
    });
    await _loadDevices();
    if (!mounted) return;
    final tip = result.primaryTransferExecuteAt != null
        ? '主设备迁移已申请，将于 ${_formatTransferTime(result.primaryTransferExecuteAt!)} 生效'
        : '主设备迁移已申请，将于两天后生效';
    showAppSnackBar(
      context,
      message: tip,
      duration: const Duration(seconds: 2),
    );
  }

  String _formatTransferTime(DateTime dt) {
    return TimezoneService.formatDateTime(dt);
  }

  Future<void> _onRename(int index, String name) async {
    final device = _devices[index];
    final previous = device;
    setState(() {
      _devices[index] = name == device.deviceName
          ? device.copyWith(clearCustomName: true)
          : device.copyWith(customName: name);
    });
    await _persistDevicesFromCards();
    if (!mounted) return;

    final session = await _readySession();
    if (session == null) {
      if (!mounted) return;
      setState(() => _devices[index] = previous);
      await _persistDevicesFromCards();
      if (!mounted) return;
      showAppSnackBar(context, message: '会话验证失败，请稍后重试');
      return;
    }

    final result = await ApiService.renameBinding(
      sessionId: session.id,
      sessionSecret: session.secret,
      bindingId: device.bindingId,
      newName: name,
    );
    if (!mounted) return;
    if (result == null) {
      setState(() => _devices[index] = previous);
      await _persistDevicesFromCards();
      if (!mounted) return;
      showAppSnackBar(context, message: ApiService.lastError ?? '设备改名失败');
      return;
    }

    setState(() {
      final d = _devices[index];
      _devices[index] = result == d.deviceName
          ? d.copyWith(clearCustomName: true)
          : d.copyWith(customName: result);
    });
    await _persistDevicesFromCards();
  }

  Future<void> _onDelete(int index) async {
    final device = _devices[index];
    final session = await _readySession();
    if (session == null) {
      if (!mounted) return;
      showAppSnackBar(context, message: '会话验证失败，请稍后重试');
      return;
    }

    final result = await ApiService.deleteBinding(
      sessionId: session.id,
      sessionSecret: session.secret,
      bindingId: device.bindingId,
    );
    if (!mounted) return;
    if (result == null) {
      showAppSnackBar(
        context,
        message: _primaryErrorText(ApiService.lastError),
      );
      return;
    }
    // 其他设备立刻 unbound：移出列表；本机则进入等待态
    if (result.status == 'unbound') {
      setState(() {
        _devices.removeAt(index);
        _devices = _decorate(_devices);
      });
      showAppSnackBar(
        context,
        message: '已解绑该设备',
        duration: const Duration(seconds: 1),
      );
    } else {
      setState(() {
        _devices[index] = device.copyWith(
          status: result.status,
          unbindRequestedAt: result.unbindRequestedAt,
          unbindExecuteAt: result.unbindExecuteAt,
        );
        _devices = _decorate(_devices);
      });
    }
    await _persistDevicesFromCards();
  }

  Future<bool> _confirmTransfer() async {
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
                '发起转移后，15 分钟内可在其他设备用本账户登录并绑定。是否继续？',
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
    return confirmed == true;
  }

  Future<void> _onTransferRequest() async {
    if (_transferring) return;
    final ok = await _confirmTransfer();
    if (!ok || !mounted) return;

    HapticFeedback.lightImpact();

    final session = await _readySession();
    if (session == null) {
      if (!mounted) return;
      showAppSnackBar(context, message: '会话验证失败，请稍后重试');
      return;
    }

    setState(() => _transferring = true);
    final result = await ApiService.requestBindingTransfer(
      sessionId: session.id,
      sessionSecret: session.secret,
    );
    if (!mounted) return;
    setState(() => _transferring = false);

    if (result == null) {
      showAppSnackBar(context, message: ApiService.lastError ?? '转移申请失败');
      return;
    }

    final minutes = (result.expiresIn / 60).ceil();
    showAppSnackBar(
      context,
      message: '转移申请已创建，$minutes分钟内有效',
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _onCancelDelete(int index) async {
    final device = _devices[index];
    final session = await _readySession();
    if (session == null) {
      if (!mounted) return;
      showAppSnackBar(context, message: '会话验证失败，请稍后重试');
      return;
    }

    final ok = await ApiService.cancelDeleteBinding(
      sessionId: session.id,
      sessionSecret: session.secret,
      bindingId: device.bindingId,
    );
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(context, message: ApiService.lastError ?? '取消解绑失败');
      return;
    }
    setState(() {
      _devices[index] = device.copyWith(status: 'active', clearUnbind: true);
      _devices = _decorate(_devices);
    });
    await _persistDevicesFromCards();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    Widget body;
    if (_loading) {
      body = const AppLoadingCenter(message: '加载中...');
    } else if (_error != null) {
      body = AppErrorState(message: _error!, onRetry: _loadDevices);
    } else if (_devices.isEmpty) {
      body = const AppEmptyState(
        message: '暂无绑定设备',
        icon: Icons.devices_outlined,
      );
    } else {
      body = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: RefreshIndicator(
          onRefresh: _loadDevices,
          child: ListView.separated(
            padding: const EdgeInsets.all(AccentDimens.pagePadding),
            itemCount: _devices.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AccentDimens.deviceCardGap),
            itemBuilder: (context, index) {
              return DeviceCard(
                key: ValueKey('${_devices[index].deviceId}-$index'),
                data: _devices[index],
                onRenameSubmit: (name) => _onRename(index, name),
                onDelete: () => _onDelete(index),
                onCancelDelete: () => _onCancelDelete(index),
                onPrimaryStar: _onPrimaryStar,
                onPrimaryCancel: _onPrimaryCancel,
                onTransferTarget: () => _onTransferTarget(index),
              );
            },
          ),
        ),
      );

      if (_primaryTransferExecuteAt != null) {
        final tip =
            '主设备迁移将于 ${_formatTransferTime(_primaryTransferExecuteAt!)} 生效';
        body = Column(
          children: [
            Expanded(child: body),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AccentDimens.pagePadding,
                0,
                AccentDimens.pagePadding,
                AccentDimens.deviceCardPrimaryTipBottom,
              ),
              child: Text(
                tip,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AccentDimens.deviceCardPrimaryTipFontSize,
                  height: 1.4,
                  color: onSurface.withValues(
                    alpha: AccentDimens.deviceCardPrimaryTipAlpha,
                  ),
                ),
              ),
            ),
          ],
        );
      }
    }

    return AppScaffold(
      title: '设备绑定',
      body: body,
      trailing: Padding(
        padding: const EdgeInsets.only(
          right: AppDimens.postCreateSubmitMarginRight,
        ),
        child: SizedBox(
          height: AppDimens.postCreateSubmitHeight,
          child: ElevatedButton(
            onPressed: _transferring ? null : _onTransferRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.postCreate.submitBg,
              foregroundColor: colors.postCreate.submitText,
              elevation: 0,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.postCreateSubmitHPadding,
                vertical: 0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppDimens.postCreateSubmitRadius,
                ),
              ),
              textStyle: const TextStyle(
                fontSize: AppDimens.postCreateSubmitFontSize,
              ),
            ),
            child: _transferring
                ? SizedBox(
                    width: AccentDimens.submitSpinnerSize,
                    height: AccentDimens.submitSpinnerSize,
                    child: CircularProgressIndicator(
                      strokeWidth: AccentDimens.submitSpinnerStroke,
                      color: colors.postCreate.submitText,
                    ),
                  )
                : const Text('转移申请'),
          ),
        ),
      ),
    );
  }
}
