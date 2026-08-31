import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 设备与用户凭证安全存储
///
/// 全部存入 Keystore (Android) / Keychain (iOS)，不写入普通 SharedPreferences、日志或分析平台：
///   - device_id            服务端设备记录 ID
///   - device_secret        服务端设备凭证（保密）
///   - user_external_token  服务端用户凭证（保密）
///   - session_id           当前会话 ID（保密）
///   - session_secret       当前会话密钥（保密）
///   - fingerprint_hash     服务端返回的设备环境哈希（诊断用）
///
/// 普通退出只清 session；绑定已 unbound 时清该账号令牌（保留 device 凭证）。
class DeviceCredentialStore {
  static const _storage = FlutterSecureStorage();

  static const _kDeviceId = 'device_id';
  static const _kDeviceSecret = 'device_secret';
  static const _kUserExternalToken = 'user_external_token';
  static const _kSessionId = 'session_id';
  static const _kSessionSecret = 'session_secret';
  static const _kFingerprintHash = 'fingerprint_hash';
  static const _kRegisteredFingerprint = 'registered_fingerprint';
  /// 本机曾见过的其他账户 user_token（JSON 字符串数组），用于解绑后切号
  static const _kKnownUserTokens = 'known_user_tokens';
  /// 各账户缓存的 session：`{ user_token: { session_id, session_secret } }`
  static const _kAccountSessions = 'account_sessions';
  /// 各账户最近一次成功建 session 的时间（仅排序用，不存 secret）
  /// `{ user_token: { last_session_at: ISO8601 } }`
  static const _kAccountSessionMeta = 'account_session_meta';

  /// 保存注册时使用的设备指纹数据（JSON），用于后续 session 创建时不因设备状态变化导致指纹不匹配
  static Future<void> saveRegisteredFingerprint(String fpJson) async {
    await _storage.write(key: _kRegisteredFingerprint, value: fpJson);
  }

  /// 获取注册时保存的设备指纹 JSON
  static Future<String?> getRegisteredFingerprintJson() async {
    return _storage.read(key: _kRegisteredFingerprint);
  }

  // ── device_id ──

  static Future<int?> getDeviceId() async {
    final raw = await _storage.read(key: _kDeviceId);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  static Future<void> saveDeviceId(int id) async {
    await _storage.write(key: _kDeviceId, value: id.toString());
  }

  // ── device_secret ──

  static Future<String?> getDeviceSecret() async {
    return _storage.read(key: _kDeviceSecret);
  }

  static Future<void> saveDeviceSecret(String secret) async {
    await _storage.write(key: _kDeviceSecret, value: secret);
  }

  // ── user_external_token ──

  static Future<String?> getUserExternalToken() async {
    return _storage.read(key: _kUserExternalToken);
  }

  static Future<void> saveUserExternalToken(String token) async {
    await _storage.write(key: _kUserExternalToken, value: token);
  }

  // ── session ──

  static Future<int?> getSessionId() async {
    final raw = await _storage.read(key: _kSessionId);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  static Future<void> saveSessionId(int id) async {
    await _storage.write(key: _kSessionId, value: id.toString());
  }

  static Future<String?> getSessionSecret() async {
    return _storage.read(key: _kSessionSecret);
  }

  static Future<void> saveSessionSecret(String secret) async {
    await _storage.write(key: _kSessionSecret, value: secret);
  }

  // ── fingerprint_hash ──

  static Future<String?> getFingerprintHash() async {
    return _storage.read(key: _kFingerprintHash);
  }

  static Future<void> saveFingerprintHash(String hash) async {
    await _storage.write(key: _kFingerprintHash, value: hash);
  }

  // ── 组合查询 ──

  /// 本地是否已有设备凭证（device_id + device_secret）
  static Future<bool> hasDeviceCredentials() async {
    final id = await _storage.read(key: _kDeviceId);
    final secret = await _storage.read(key: _kDeviceSecret);
    return id != null && secret != null;
  }

  /// 本地是否已有完整用户凭证（设备 + 用户 + session）
  static Future<bool> hasActiveSession() async {
    final sid = await _storage.read(key: _kSessionId);
    final ssec = await _storage.read(key: _kSessionSecret);
    final user = await _storage.read(key: _kUserExternalToken);
    return sid != null && ssec != null && user != null;
  }

  // ── 本机已知账户令牌 ──

  static Future<List<String>> getKnownUserTokens() async {
    final raw = await _storage.read(key: _kKnownUserTokens);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.whereType<String>().where((t) => t.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveKnownUserTokens(List<String> tokens) async {
    final unique = <String>{
      for (final t in tokens)
        if (t.trim().isNotEmpty) t.trim(),
    };
    if (unique.isEmpty) {
      await _storage.delete(key: _kKnownUserTokens);
      return;
    }
    await _storage.write(
        key: _kKnownUserTokens, value: jsonEncode(unique.toList()));
  }

  static Future<void> mergeKnownUserTokens(Iterable<String> tokens) async {
    final current = await getKnownUserTokens();
    await saveKnownUserTokens([...current, ...tokens]);
  }

  static Future<void> removeKnownUserToken(String token) async {
    final current = await getKnownUserTokens();
    current.removeWhere((t) => t == token);
    await saveKnownUserTokens(current);
    await removeAccountSession(token);
    await removeAccountSessionMeta(token);
  }

  // ── 账户建 session 时间元数据（解绑 failover 排序）──

  static Future<Map<String, dynamic>> _readAccountSessionMetaMap() async {
    final raw = await _storage.read(key: _kAccountSessionMeta);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeAccountSessionMetaMap(
      Map<String, dynamic> map) async {
    if (map.isEmpty) {
      await _storage.delete(key: _kAccountSessionMeta);
      return;
    }
    await _storage.write(key: _kAccountSessionMeta, value: jsonEncode(map));
  }

  /// 记录该账户最近一次成功建立 session 的时间
  static Future<void> touchLastSessionAt(String userToken) async {
    final token = userToken.trim();
    if (token.isEmpty) return;
    final map = await _readAccountSessionMetaMap();
    map[token] = {
      'last_session_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeAccountSessionMetaMap(map);
  }

  static Future<DateTime?> getLastSessionAt(String userToken) async {
    final token = userToken.trim();
    if (token.isEmpty) return null;
    final map = await _readAccountSessionMetaMap();
    final entry = map[token];
    if (entry is! Map) return null;
    final raw = entry['last_session_at'];
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  static Future<void> removeAccountSessionMeta(String userToken) async {
    final token = userToken.trim();
    if (token.isEmpty) return;
    final map = await _readAccountSessionMetaMap();
    if (map.remove(token) != null) {
      await _writeAccountSessionMetaMap(map);
    }
  }

  static Future<void> clearAccountSessionMeta() async {
    await _storage.delete(key: _kAccountSessionMeta);
  }

  /// 按最近建 session 时间降序；无记录的排在后面并保持原相对顺序
  static Future<List<String>> sortTokensByLastSession(
      Iterable<String> tokens) async {
    final list = tokens
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (list.length <= 1) return list;

    final meta = await _readAccountSessionMetaMap();
    DateTime? at(String token) {
      final entry = meta[token];
      if (entry is! Map) return null;
      final raw = entry['last_session_at'];
      if (raw is! String || raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toUtc();
    }

    final indexed = <({String token, int index, DateTime? at})>[];
    for (var i = 0; i < list.length; i++) {
      indexed.add((token: list[i], index: i, at: at(list[i])));
    }
    indexed.sort((a, b) {
      final aAt = a.at;
      final bAt = b.at;
      if (aAt != null && bAt != null) return bAt.compareTo(aAt);
      if (aAt != null) return -1;
      if (bAt != null) return 1;
      return a.index.compareTo(b.index);
    });
    return indexed.map((e) => e.token).toList();
  }

  // ── 按账户缓存的 session（切号复用，避免反复 session/create 触发限流）──

  static Future<Map<String, dynamic>> _readAccountSessionsMap() async {
    final raw = await _storage.read(key: _kAccountSessions);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeAccountSessionsMap(Map<String, dynamic> map) async {
    if (map.isEmpty) {
      await _storage.delete(key: _kAccountSessions);
      return;
    }
    await _storage.write(key: _kAccountSessions, value: jsonEncode(map));
  }

  /// 读取某账户缓存的 session；无效或缺字段返回 null
  static Future<({int id, String secret})?> getAccountSession(
      String userToken) async {
    final token = userToken.trim();
    if (token.isEmpty) return null;
    final map = await _readAccountSessionsMap();
    final entry = map[token];
    if (entry is! Map) return null;
    final idRaw = entry['session_id'];
    final secret = entry['session_secret'];
    final id = idRaw is num ? idRaw.toInt() : int.tryParse('$idRaw');
    if (id == null || secret is! String || secret.isEmpty) return null;
    return (id: id, secret: secret);
  }

  static Future<void> saveAccountSession(
    String userToken,
    int sessionId,
    String sessionSecret,
  ) async {
    final token = userToken.trim();
    if (token.isEmpty || sessionSecret.isEmpty) return;
    final map = await _readAccountSessionsMap();
    map[token] = {
      'session_id': sessionId,
      'session_secret': sessionSecret,
    };
    await _writeAccountSessionsMap(map);
  }

  static Future<void> removeAccountSession(String userToken) async {
    final token = userToken.trim();
    if (token.isEmpty) return;
    final map = await _readAccountSessionsMap();
    if (map.remove(token) != null) {
      await _writeAccountSessionsMap(map);
    }
  }

  static Future<void> clearAccountSessions() async {
    await _storage.delete(key: _kAccountSessions);
  }

  // ── 清除 ──

  /// 退出登录：只清当前 session，保留设备和用户凭证
  static Future<void> clearSession() async {
    final token = await getUserExternalToken();
    await _storage.delete(key: _kSessionId);
    await _storage.delete(key: _kSessionSecret);
    if (token != null) await removeAccountSession(token);
  }

  /// 当前账号已解绑：清该账号令牌与 session，保留 device_id / device_secret
  static Future<void> clearUserAccount() async {
    final token = await getUserExternalToken();
    await _storage.delete(key: _kUserExternalToken);
    await _storage.delete(key: _kSessionId);
    await _storage.delete(key: _kSessionSecret);
    if (token != null) {
      await removeAccountSession(token);
      await removeAccountSessionMeta(token);
    }
  }

  /// 调试用：清除全部凭证（模拟卸载重装）
  static Future<void> clearAll() async {
    await _storage.delete(key: _kDeviceId);
    await _storage.delete(key: _kDeviceSecret);
    await _storage.delete(key: _kUserExternalToken);
    await _storage.delete(key: _kSessionId);
    await _storage.delete(key: _kSessionSecret);
    await _storage.delete(key: _kFingerprintHash);
    await _storage.delete(key: _kKnownUserTokens);
    await _storage.delete(key: _kAccountSessions);
    await _storage.delete(key: _kAccountSessionMeta);
  }
}
