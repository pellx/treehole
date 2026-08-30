import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import 'api.dart';
import 'chat_api.dart';
import 'device_credential_store.dart';
import 'realtime_service.dart';
import 'session_service.dart';
import 'storage.dart';

/// 会话列表 + 实时新消息。消息 Tab 在 IndexedStack 中常驻，启动即 attach。
class ChatInbox extends ChangeNotifier {
  ChatInbox._();
  static final ChatInbox instance = ChatInbox._();

  List<ChatConversation> items = [];
  bool loading = false;
  String? error;
  int? selfUserId;
  bool _attached = false;

  final List<void Function(ChatRealtimePayload payload)> _messageListeners = [];

  void attach() {
    if (_attached) return;
    _attached = true;
    RealtimeService.instance.onChatMessage = _onRealtime;
  }

  void addMessageListener(void Function(ChatRealtimePayload payload) fn) {
    _messageListeners.add(fn);
  }

  void removeMessageListener(void Function(ChatRealtimePayload payload) fn) {
    _messageListeners.remove(fn);
  }

  Future<bool> ensureReady() async {
    attach();
    if (!PostStorage.isRegistered()) {
      selfUserId = null;
      items = [];
      error = null;
      notifyListeners();
      return false;
    }
    final ok = await SessionService.instance.ensureSession();
    if (!ok) {
      error = '请先登录';
      notifyListeners();
      return false;
    }
    await _refreshSelfUserId();
    return selfUserId != null;
  }

  Future<void> reload() async {
    loading = true;
    error = null;
    notifyListeners();
    final ready = await ensureReady();
    if (!ready) {
      loading = false;
      notifyListeners();
      return;
    }
    final list = await ChatApi.listConversations();
    loading = false;
    if (list == null) {
      error = friendlyError(ApiService.lastError);
      notifyListeners();
      return;
    }
    items = list;
    error = null;
    notifyListeners();
  }

  void upsertConversation(ChatConversation conv) {
    final next = [...items.where((e) => e.id != conv.id)];
    next.insert(0, conv);
    items = next;
    notifyListeners();
  }

  void reset() {
    items = [];
    selfUserId = null;
    error = null;
    loading = false;
    notifyListeners();
  }

  void markLocalRead(int conversationId) {
    items = [
      for (final c in items)
        if (c.id == conversationId) c.copyWith(unreadCount: 0) else c,
    ];
    notifyListeners();
  }

  Future<void> _refreshSelfUserId() async {
    var id = await DeviceCredentialStore.getUserId();
    if (id != null) {
      selfUserId = id;
      return;
    }
    final sessionId = await DeviceCredentialStore.getSessionId();
    final secret = await DeviceCredentialStore.getSessionSecret();
    if (sessionId == null || secret == null) return;
    final result = await ApiService.validateSession(
      sessionId: sessionId,
      sessionSecret: secret,
    );
    if (result != null && result.valid && result.userId != null) {
      await DeviceCredentialStore.saveUserId(result.userId!);
      selfUserId = result.userId;
    }
  }

  void _onRealtime(ChatRealtimePayload payload) {
    upsertConversation(payload.conversation);
    for (final fn in List.of(_messageListeners)) {
      fn(payload);
    }
  }

  static String friendlyError(String? raw) {
    switch (raw) {
      case 'MISSING_SESSION':
      case 'SESSION_INVALID':
        return '请先登录';
      case 'USER_NOT_FOUND':
        return '找不到该用户';
      case 'CHAT_SELF':
        return '不能给自己发私信';
      case 'RATE_LIMITED':
        return '发送太频繁，请稍后再试';
      case 'MESSAGE_EMPTY':
        return '请输入内容';
      case 'PEER_REQUIRED':
        return '请填写对方昵称';
      case 'CONVERSATION_NOT_FOUND':
      case 'CONVERSATION_FORBIDDEN':
        return '会话不存在';
      default:
        if (raw != null && raw.startsWith('内容审核未通过')) return raw;
        return raw ?? '加载失败';
    }
  }
}
