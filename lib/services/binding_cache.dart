import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/api_results.dart';
import '../models/bound_account.dart';
import '../models/bound_device.dart';
import 'api.dart';
import 'device_credential_store.dart';
import 'session_service.dart';
import 'timezone_service.dart';

/// 设备/账户绑定列表本地缓存；账户侧不落盘 user_token
class BindingCache {
  static const _devicesKey = 'devices2user';
  static const _accountsKey = 'user2device';
  /// 切号锁过期时刻（ISO8601）；无键或已过期表示可切换
  static const _switchLockExpiresKey = 'last_switch_expires_at';
  static const _primaryTransferExecuteKey = 'primary_transfer_execute_at';
  static const _primaryPendingDeviceKey = 'primary_device_pending_id';
  static late Box _box;

  static DateTime? _switchLockExpiresAt;
  static bool _switchLockLoaded = false;
  static DateTime? _primaryTransferExecuteAt;
  static int? _primaryPendingDeviceId;

  static Future<void> init() async {
    _box = await Hive.openBox('binding_cache');
  }

  static List<BoundDeviceInfo> getDevices() {
    final raw = _box.get(_devicesKey);
    if (raw is! String || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => BoundDeviceInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[BindingCache] getDevices parse error: $e');
      return [];
    }
  }

  static Future<void> saveDevices(List<BoundDeviceInfo> devices) async {
    final encoded = jsonEncode(devices.map((d) => d.toJson()).toList());
    await _box.put(_devicesKey, encoded);
  }

  static Future<void> saveDevicesResult(BoundDevicesResult result) async {
    await saveDevices(result.devices);
    _primaryPendingDeviceId = result.primaryDevicePendingId;
    _primaryTransferExecuteAt = result.primaryTransferExecuteAt;
    if (_primaryPendingDeviceId == null) {
      await _box.delete(_primaryPendingDeviceKey);
    } else {
      await _box.put(_primaryPendingDeviceKey, _primaryPendingDeviceId);
    }
    final exp = _primaryTransferExecuteAt;
    if (exp == null) {
      await _box.delete(_primaryTransferExecuteKey);
    } else {
      await _box.put(
          _primaryTransferExecuteKey, exp.toUtc().toIso8601String());
    }
  }

  static int? getPrimaryPendingDeviceId() {
    if (_primaryPendingDeviceId != null) return _primaryPendingDeviceId;
    final raw = _box.get(_primaryPendingDeviceKey);
    if (raw is int) {
      _primaryPendingDeviceId = raw;
    } else if (raw is num) {
      _primaryPendingDeviceId = raw.toInt();
    }
    return _primaryPendingDeviceId;
  }

  static DateTime? getPrimaryTransferExecuteAt() {
    if (_primaryTransferExecuteAt != null) {
      return _primaryTransferExecuteAt;
    }
    final raw = _box.get(_primaryTransferExecuteKey);
    if (raw is String && raw.isNotEmpty) {
      _primaryTransferExecuteAt = TimezoneService.parseServerDateTime(raw);
    }
    return _primaryTransferExecuteAt;
  }

  /// 缓存不含 user_token，仅展示用字段
  static List<BoundAccountInfo> getAccounts() {
    final raw = _box.get(_accountsKey);
    if (raw is! String || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => BoundAccountInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[BindingCache] getAccounts parse error: $e');
      return [];
    }
  }

  static Future<void> saveAccounts(List<BoundAccountInfo> accounts) async {
    final encoded = jsonEncode(accounts.map((a) => a.toCacheJson()).toList());
    await _box.put(_accountsKey, encoded);
    // 令牌只进安全存储，供解绑后切号；Hive 仍不含 user_token
    final tokens = accounts
        .map((a) => a.userToken.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isNotEmpty) {
      await DeviceCredentialStore.mergeKnownUserTokens(tokens);
    }
  }

  static bool devicesEqual(List<BoundDeviceInfo> a, List<BoundDeviceInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].bindingId != b[i].bindingId ||
          a[i].deviceId != b[i].deviceId ||
          a[i].status != b[i].status ||
          a[i].unbindRequestedAt != b[i].unbindRequestedAt ||
          a[i].unbindExecuteAt != b[i].unbindExecuteAt ||
          a[i].deviceDisplayName != b[i].deviceDisplayName ||
          a[i].deviceName != b[i].deviceName ||
          a[i].brand != b[i].brand ||
          a[i].model != b[i].model ||
          a[i].os != b[i].os ||
          a[i].abi != b[i].abi ||
          a[i].isPrimary != b[i].isPrimary ||
          a[i].isPrimaryPending != b[i].isPrimaryPending) {
        return false;
      }
    }
    return true;
  }

  static bool accountsEqual(List<BoundAccountInfo> a, List<BoundAccountInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].bindingId != b[i].bindingId ||
          a[i].deviceId != b[i].deviceId ||
          a[i].status != b[i].status ||
          a[i].unbindRequestedAt != b[i].unbindRequestedAt ||
          a[i].userDisplayId != b[i].userDisplayId ||
          a[i].createdAt != b[i].createdAt ||
          a[i].userToken != b[i].userToken) {
        return false;
      }
    }
    return true;
  }

  static Future<({int id, String secret})?> _readySession() async {
    final ok = await SessionService.instance.ensureSession();
    if (!ok) return null;
    final id = await DeviceCredentialStore.getSessionId();
    final secret = await DeviceCredentialStore.getSessionSecret();
    if (id == null || secret == null) return null;
    return (id: id, secret: secret);
  }

  /// 当前切号锁过期时间；未锁定或已过期返回 null
  static DateTime? getSwitchLockExpiresAt() {
    if (!_switchLockLoaded) {
      _switchLockLoaded = true;
      final raw = _box.get(_switchLockExpiresKey);
      if (raw is String && raw.isNotEmpty) {
        _switchLockExpiresAt = TimezoneService.parseServerDateTime(raw);
      }
    }
    final exp = _switchLockExpiresAt;
    if (exp == null) return null;
    if (!exp.isAfter(DateTime.now())) {
      _switchLockExpiresAt = null;
      return null;
    }
    return exp;
  }

  static Future<void> saveSwitchLock(LastSwitchResult? last) async {
    final exp = last?.isLocked == true ? last!.expiresAt : null;
    _switchLockExpiresAt = exp;
    _switchLockLoaded = true;
    if (exp == null) {
      await _box.delete(_switchLockExpiresKey);
    } else {
      await _box.put(_switchLockExpiresKey, exp.toUtc().toIso8601String());
    }
  }

  /// 用户页打开时预取，写入本地缓存（含切号锁，避免进切换页闪烁）
  static Future<void> prefetchAll() async {
    final session = await _readySession();
    if (session == null) {
      debugPrint('[BindingCache] prefetch: session 未就绪');
      return;
    }
    await Future.wait([
      _prefetchDevices(session.id, session.secret),
      _prefetchAccounts(session.id, session.secret),
      _prefetchSwitchLock(session.id, session.secret),
    ]);
  }

  static Future<DateTime?> _prefetchSwitchLock(
      int sessionId, String sessionSecret) async {
    final last = await ApiService.getLastSwitch(
      sessionId: sessionId,
      sessionSecret: sessionSecret,
    );
    if (last != null) await saveSwitchLock(last);
    return getSwitchLockExpiresAt();
  }

  /// 刷新切号锁；失败保留旧缓存
  static Future<DateTime?> refreshSwitchLock() async {
    final session = await _readySession();
    if (session == null) return getSwitchLockExpiresAt();
    return _prefetchSwitchLock(session.id, session.secret);
  }

  /// Hive 整盒清空后调用，避免内存仍持有旧锁
  static void invalidateMemory() {
    _switchLockLoaded = false;
    _switchLockExpiresAt = null;
    _primaryPendingDeviceId = null;
    _primaryTransferExecuteAt = null;
  }

  static Future<List<BoundDeviceInfo>?> _prefetchDevices(
      int sessionId, String sessionSecret) async {
    final result = await ApiService.listBoundDevices(
      sessionId: sessionId,
      sessionSecret: sessionSecret,
    );
    if (result != null) {
      await saveDevicesResult(result);
      return result.devices;
    }
    return null;
  }

  static Future<List<BoundAccountInfo>?> _prefetchAccounts(
      int sessionId, String sessionSecret) async {
    final list = await ApiService.listBoundAccounts(
      sessionId: sessionId,
      sessionSecret: sessionSecret,
    );
    if (list != null) await saveAccounts(list);
    return list;
  }

  /// 拉取最新设备列表并更新缓存；失败返回 null（保留旧缓存）
  static Future<List<BoundDeviceInfo>?> refreshDevices() async {
    final session = await _readySession();
    if (session == null) {
      ApiService.lastError = '会话验证失败，请稍后重试';
      return null;
    }
    return _prefetchDevices(session.id, session.secret);
  }

  /// 拉取最新账户列表并更新缓存；失败返回 null（保留旧缓存）
  static Future<List<BoundAccountInfo>?> refreshAccounts() async {
    final session = await _readySession();
    if (session == null) {
      ApiService.lastError = '会话验证失败，请稍后重试';
      return null;
    }
    return _prefetchAccounts(session.id, session.secret);
  }
}
