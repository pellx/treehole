import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/chat.dart';
import 'api.dart';
import 'device_credential_store.dart';

bool _ok(int code) => code >= 200 && code < 300;

/// 私聊 HTTP。独立文件，避免与协作者在 api.dart 末尾追加短信方法冲突。
class ChatApi {
  ChatApi._();

  static const _base = 'https://tree.leisure.xin/node/chat';
  static const _timeout = Duration(seconds: 30);
  static final http.Client _client = http.Client();

  static Future<ChatLookupResult?> lookup(String displayId) async {
    final data = await _post('/lookup', {'display_id': displayId.trim()});
    if (data == null) return null;
    return ChatLookupResult.fromJson(data);
  }

  static Future<ChatConversation?> openDm({
    int? peerUserId,
    String? peerDisplayId,
  }) async {
    final body = <String, dynamic>{};
    if (peerUserId != null) body['peer_user_id'] = peerUserId;
    if (peerDisplayId != null && peerDisplayId.trim().isNotEmpty) {
      body['peer_display_id'] = peerDisplayId.trim();
    }
    final data = await _post('/dm', body);
    if (data == null) return null;
    return ChatConversation.fromJson(data);
  }

  static Future<List<ChatConversation>?> listConversations() async {
    final data = await _post('/conversations', {});
    if (data == null) return null;
    final items = data['items'];
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((e) => ChatConversation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<ChatMessage?> send({
    required int conversationId,
    required String body,
    String? clientMsgId,
  }) async {
    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'body': body,
    };
    if (clientMsgId != null) payload['client_msg_id'] = clientMsgId;
    final data = await _post('/send', payload);
    if (data == null) return null;
    return ChatMessage.fromJson(data);
  }

  static Future<List<ChatMessage>?> history({
    required int conversationId,
    int? beforeId,
    int limit = 30,
  }) async {
    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'limit': limit,
    };
    if (beforeId != null) payload['before_id'] = beforeId;
    final data = await _post('/history', payload);
    if (data == null) return null;
    final items = data['items'];
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<bool> markRead({
    required int conversationId,
    required int lastReadMessageId,
  }) async {
    final data = await _post('/read', {
      'conversation_id': conversationId,
      'last_read_message_id': lastReadMessageId,
    });
    return data != null;
  }

  static Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> extra,
  ) async {
    final sessionId = await DeviceCredentialStore.getSessionId();
    final sessionSecret = await DeviceCredentialStore.getSessionSecret();
    if (sessionId == null || sessionSecret == null || sessionSecret.isEmpty) {
      ApiService.lastError = 'MISSING_SESSION';
      return null;
    }
    try {
      final res = await _client
          .post(
            Uri.parse('$_base$path'),
            headers: {
              'Content-Type': 'application/json',
              'x-session-id': '$sessionId',
              'x-session-secret': sessionSecret,
            },
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
              ...extra,
            }),
          )
          .timeout(_timeout);
      if (_ok(res.statusCode)) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'items': decoded};
      }
      ApiService.lastError = _parseError(res.body);
      debugPrint('[ChatApi] $path status=${res.statusCode} body=${res.body}');
      return null;
    } catch (e) {
      ApiService.lastError = '网络连接失败';
      debugPrint('[ChatApi] $path error: $e');
      return null;
    }
  }

  static String _parseError(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) {
        return msg.map((e) => e.toString()).join('；');
      }
      return '操作失败';
    } catch (_) {
      return '操作失败';
    }
  }
}
