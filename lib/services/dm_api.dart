import 'message_cache.dart';
import 'message_sync.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'device_credential_store.dart';
import 'session_service.dart';
import 'api.dart';
import 'realtime_service.dart';

class DmException implements Exception {
  final String message;
  final bool requiresLogin;
  final String? code;
  const DmException(this.message, {this.requiresLogin = false, this.code});
  @override
  String toString() => message;
}

/// One instance belongs to one authenticated session; never reuse after switching.
class DmApi {
  final int sessionId;
  final String sessionSecret;
  final http.Client _client = http.Client();
  final String accountToken;
  DmApi._(this.sessionId, this.sessionSecret, this.accountToken);
  Future<MessageSync> _sync() async =>
      MessageSync(await MessageCache.open(accountToken), _request);

  static Future<DmApi?> openLocal() async {
    final id = await DeviceCredentialStore.getSessionId();
    final secret = await DeviceCredentialStore.getSessionSecret();
    final token = await DeviceCredentialStore.getUserExternalToken();
    if (id == null || secret == null || token == null) return null;
    return DmApi._(id, secret, token);
  }

  Future<Map<String, dynamic>?> cached(String namespace, String path) async {
    await _checkSession();
    final key = MessageSync.keyFor(namespace, path);
    if (key == null) return null;
    final data = (await MessageCache.open(accountToken)).read(key);
    await _checkSession();
    return data;
  }

  Future<Map<String, dynamic>> _load(String namespace, String path) async {
    await _checkSession();
    final result = await (await _sync()).load(namespace, path);
    await _checkSession();
    return result;
  }

  static Future<DmApi> open() async {
    if (!await SessionService.instance.ensureSession()) {
      if (ApiService.isNetworkError(ApiService.lastError)) {
        final local = await openLocal();
        if (local != null) return local;
        throw DmException(ApiService.lastError!);
      }
      throw const DmException('请先登录，再打开消息', requiresLogin: true);
    }
    final id = await DeviceCredentialStore.getSessionId();
    final secret = await DeviceCredentialStore.getSessionSecret();
    if (id == null || secret == null) {
      throw const DmException('请先登录，再打开消息', requiresLogin: true);
    }
    final token = await DeviceCredentialStore.getUserExternalToken();
    if (token == null) throw const DmException('请先登录', requiresLogin: true);
    return DmApi._(id, secret, token);
  }

  Future<void> _checkSession() async {
    if (await DeviceCredentialStore.getSessionId() != sessionId ||
        await DeviceCredentialStore.getSessionSecret() != sessionSecret ||
        await DeviceCredentialStore.getUserExternalToken() != accountToken) {
      throw const DmException('登录状态已变化，请返回消息页重新进入');
    }
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (body == null) return _load('dm', path);
    final data = await _request('dm', path, body: body);
    if (path == 'conversations') {
      try {
        final row = data['conversation'] as Map<String, dynamic>;
        final cache = await MessageCache.open(accountToken);
        await cache.serial('dm/conversations', () async {
          final saved = cache.read('dm/conversations');
          if (saved != null &&
              !(saved['items'] as List).any(
                (item) => item['id'] == row['id'],
              )) {
            final state = await _request(
              'dm',
              'conversations/state',
              body: {
                'known': [
                  {'id': row['id'], 'hash': List.filled(64, '0').join()},
                ],
              },
            );
            (saved['items'] as List).addAll(state['items'] as List);
            await cache.write('dm/conversations', saved);
          }
        });
      } catch (_) {}
    }
    if (RegExp(r'^conversations/[0-9]+/messages$').hasMatch(path)) {
      try {
        await (await _sync()).recordSent(path, data);
      } catch (_) {}
    }
    return data;
  }

  Future<Map<String, dynamic>> systemRequest(
    String path, {
    Map<String, dynamic>? body,
  }) => body == null
      ? _load('system', path)
      : _request('system', path, body: body);

  Future<Map<String, dynamic>> _request(
    String namespace,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    await _checkSession();
    final uri = Uri.parse(
      'https://tree.leisure.xin/node/messages/$namespace/$path',
    );
    final headers = {
      'x-session-id': '$sessionId',
      'x-session-secret': sessionSecret,
      'Content-Type': 'application/json',
    };
    try {
      final response =
          await (body == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 20));
      await _checkSession();
      if (response.statusCode == 401) {
        SessionService.instance.invalidate();
        await (await MessageCache.open(accountToken)).clear();
        throw const DmException('登录已失效，请返回消息页重新登录', requiresLogin: true);
      }
      if (response.statusCode == 404 &&
          !response.headers['content-type'].toString().contains('json')) {
        throw const DmException('私信接口尚未就绪，请检查后端部署');
      }
      if (response.statusCode >= 500) {
        throw const DmException('私信服务暂不可用，请稍后重试');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded['message'];
        throw DmException(
          message is String
              ? message
              : message is List
              ? message.join('；')
              : '请求失败，请重试',
          code: decoded['code'] as String?,
        );
      }
      return decoded;
    } on TimeoutException {
      throw const DmException('请求超时，请重试');
    } on http.ClientException {
      throw const DmException('网络连接失败，请重试');
    } on FormatException {
      throw const DmException('私信接口响应异常，请检查后端部署');
    }
  }

  Future<void> reconnectRealtime() async {
    await _checkSession();
    RealtimeService.instance.connect(
      sessionId: sessionId,
      sessionSecret: sessionSecret,
    );
  }

  void close() => _client.close();
}
