import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/dm_api.dart';
import '../../services/dm_inbox.dart';
import '../../services/dm_notifications.dart';
import '../../services/realtime_service.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/app_confirm_dialog.dart';

class DmChatPage extends StatefulWidget {
  final DmApi api;
  final int conversationId;
  final int peerId;
  final int userId;
  const DmChatPage({
    super.key,
    required this.api,
    required this.conversationId,
    required this.peerId,
    required this.userId,
  });
  @override
  State<DmChatPage> createState() => _DmChatPageState();
}

class _DmChatPageState extends State<DmChatPage> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  int? _next;
  bool _busy = false;
  bool _sending = false;
  bool _loaded = false;
  bool _reading = false;
  int _lastRead = 0;
  bool _muted = false;
  bool _pinned = false;
  bool _blocked = false;
  bool _canSend = true;
  Timer? _banExpiry;
  Map<String, dynamic>? _peerProfile;
  Map<String, dynamic>? _selfProfile;
  void _applyDetails(Map<String, dynamic> data) {
    _muted = data['muted'] == true;
    _pinned = data['pinned'] == true;
    _blocked = data['blocked'] == true;
    _canSend = data['can_send'] != false;
    _banExpiry?.cancel();
    final until = DateTime.tryParse(data['banned_until']?.toString() ?? '');
    if (data['send_disabled'] == true &&
        data['permanent'] != true &&
        until != null) {
      final delay = until.difference(DateTime.now());
      if (!delay.isNegative) {
        _banExpiry = Timer(delay + const Duration(seconds: 1), () {
          if (mounted) _load(silent: true);
        });
      }
    }
    _peerProfile = data['peer'] as Map<String, dynamic>?;
    _selfProfile = data['self'] as Map<String, dynamic>?;
  }

  Future<void> _changePreference(String field) async {
    if (_busy || _sending) return;
    final value = switch (field) {
      'muted' => !_muted,
      'pinned' => !_pinned,
      _ => !_blocked,
    };
    if (field == 'blocked' && value) {
      final ok = await showAppConfirmDialog(
        context,
        title: '加入黑名单',
        message: '加入后双方将无法继续发送私信，历史消息保留。',
        confirmText: '加入黑名单',
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final data = await widget.api.request(
        'conversations/${widget.conversationId}/preferences',
        body: {field: value},
      );
      if (!mounted) return;
      setState(() => _applyDetails(data));
      showAppToast(
        context,
        message: field == 'pinned'
            ? (value ? '已置顶聊天' : '已取消置顶')
            : field == 'muted'
            ? (value ? '已开启消息免打扰' : '已关闭消息免打扰')
            : (value ? '已加入黑名单' : '已移出黑名单'),
      );
    } catch (error) {
      if (mounted) showAppToast(context, message: error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      _drainRefresh();
    }
  }

  bool _refreshPending = false;
  StreamSubscription? _realtimeSubscription;
  String? _pendingKey;
  String? _pendingText;

  @override
  void initState() {
    super.initState();
    DmInbox.visibleConversationId = widget.conversationId;
    _scroll.addListener(_markVisibleRead);
    WidgetsBinding.instance.addObserver(this);
    _realtimeSubscription = RealtimeService.instance.dmEvents.listen((event) {
      if (event.sessionId != widget.api.sessionId) return;
      if (event.conversationId == null ||
          event.conversationId == widget.conversationId) {
        _refreshLive();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeRealtime();
    }
  }

  Future<void> _resumeRealtime() async {
    try {
      await widget.api.reconnectRealtime();
      _refreshLive();
    } catch (error) {
      if (mounted) showAppToast(context, message: error.toString());
    }
  }

  Future<void> _markVisibleRead() async {
    if (!mounted ||
        _reading ||
        _messages.isEmpty ||
        ModalRoute.of(context)?.isCurrent != true ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) ||
        (_scroll.hasClients && _scroll.offset > 80)) {
      return;
    }
    final seq = _messages.first['seq'] as int;
    if (seq <= _lastRead) return;
    _reading = true;
    var saved = false;
    try {
      await widget.api.request(
        'conversations/${widget.conversationId}/read',
        body: {'last_read_seq': seq},
      );
      if (seq > _lastRead) _lastRead = seq;
      saved = true;
      unawaited(DmInbox.refresh());
      unawaited(DmNotifications.cancel(widget.conversationId));
    } catch (_) {
      // Reconnect or the next visible refresh retries the cursor.
    } finally {
      _reading = false;
      if (saved &&
          mounted &&
          _messages.isNotEmpty &&
          (_messages.first['seq'] as int) > _lastRead) {
        _markVisibleRead();
      }
    }
  }

  void _refreshLive() {
    if (!mounted) return;
    if (_busy || _sending) {
      _refreshPending = true;
      return;
    }
    _load(silent: true);
  }

  void _drainRefresh() {
    if (!mounted || !_refreshPending || _busy || _sending) return;
    _refreshPending = false;
    _load(silent: true);
  }

  Future<void> _load({bool older = false, bool silent = false}) async {
    if (_busy || _sending) return;
    setState(() => _busy = true);
    final dismiss = silent
        ? () {}
        : showAppToast(
            context,
            message: '正在获取私信',
            duration: const Duration(seconds: 25),
          );
    try {
      if (!_loaded) {
        try {
          final cached = await widget.api.cached(
            'dm',
            'conversations/${widget.conversationId}/messages',
          );
          if (mounted && cached != null && cached['user_id'] == widget.userId) {
            setState(() {
              _messages
                ..clear()
                ..addAll(
                  (cached['items'] as List).cast<Map<String, dynamic>>(),
                );
              _next = cached['next_before_seq'] as int?;
              _lastRead = cached['last_read_seq'] as int? ?? 0;
              _applyDetails(cached);
              _loaded = true;
            });
          }
        } catch (_) {}
      }
      final result = await widget.api.request(
        'conversations/${widget.conversationId}/messages${older && _next != null ? '?before_seq=$_next' : ''}',
      );
      if (result['user_id'] != widget.userId) {
        throw const DmException('账号已变化，请返回消息页');
      }
      if (!mounted) return;
      setState(() {
        if (!older) _messages.clear();
        final known = _messages.map((m) => m['id']).toSet();
        _messages.addAll(
          (result['items'] as List).cast<Map<String, dynamic>>().where(
            (m) => !known.contains(m['id']),
          ),
        );
        _messages.sort((a, b) => (b['seq'] as int).compareTo(a['seq'] as int));
        _next = result['next_before_seq'] as int?;
        final acknowledged = result['last_read_seq'] as int? ?? 0;
        if (acknowledged > _lastRead) _lastRead = acknowledged;
        _applyDetails(result);
        _loaded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _markVisibleRead());
    } catch (error) {
      dismiss();
      if (mounted && error is DmException && error.requiresLogin) {
        setState(() {
          _messages.clear();
          _canSend = false;
        });
      }
      if (mounted && !silent) showAppToast(context, message: error.toString());
    } finally {
      dismiss();
      if (mounted) setState(() => _busy = false);
      _drainRefresh();
    }
  }

  Future<void> _send() async {
    if (_busy || _sending) return;
    if (!_canSend) {
      showAppToast(context, message: '当前无法向该用户发送私信');
      return;
    }
    final text = _input.text.trim();
    if (text.isEmpty || text.length > 2000) {
      showAppToast(context, message: '请输入 1–2000 字的消息');
      return;
    }
    // A failed request keeps its UUID so a retry cannot insert the same message twice.
    if (_pendingText != text) {
      _pendingText = text;
      _pendingKey = const Uuid().v4();
    }
    setState(() => _sending = true);
    final dismiss = showAppToast(
      context,
      message: '正在发送',
      duration: const Duration(seconds: 25),
    );
    try {
      final message = await widget.api.request(
        'conversations/${widget.conversationId}/messages',
        body: {'content': text, 'client_message_id': _pendingKey},
      );
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m['id'] == message['id']);
        _messages.add(message);
        _messages.sort((a, b) => (b['seq'] as int).compareTo(a['seq'] as int));
        _input.clear();
        _pendingKey = null;
        _pendingText = null;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _refreshPending = true;
    } catch (error) {
      dismiss();
      if (mounted) {
        if (error is DmException &&
            (error.code == 'ACCOUNT_BANNED' ||
                error.code == 'DM_SEND_DISABLED')) {
          setState(() => _canSend = false);
        }
        showAppToast(
          context,
          message:
              error is DmException &&
                  (error.code == 'ACCOUNT_BANNED' ||
                      error.code == 'DM_SEND_DISABLED')
              ? error.toString()
              : '${error.toString()}；可修改内容或重试',
        );
      }
    } finally {
      dismiss();
      if (mounted) setState(() => _sending = false);
      _drainRefresh();
    }
  }

  @override
  void dispose() {
    _banExpiry?.cancel();
    _realtimeSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (DmInbox.visibleConversationId == widget.conversationId) {
      DmInbox.visibleConversationId = null;
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppScaffold(
      title: '用户 #${widget.peerId}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '刷新私信',
            onPressed: _busy || _sending ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '聊天设置',
            enabled: _loaded && !_busy && !_sending,
            onSelected: _changePreference,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'muted',
                child: Text(_muted ? '关闭消息免打扰' : '开启消息免打扰'),
              ),
              PopupMenuItem(
                value: 'pinned',
                child: Text(_pinned ? '取消置顶聊天' : '置顶聊天'),
              ),
              PopupMenuItem(
                value: 'blocked',
                child: Text(_blocked ? '移出黑名单' : '加入黑名单'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(child: Text(_loaded ? '还没有消息，打个招呼吧' : ''))
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_next == null ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return TextButton(
                            onPressed: _busy || _sending
                                ? null
                                : () => _load(older: true),
                            child: const Text('加载更早消息'),
                          );
                        }
                        final item = _messages[index];
                        final mine = item['sender_id'] == widget.userId;
                        final date = DateTime.tryParse(
                          item['created_at'] as String? ?? '',
                        )?.toLocal();
                        final time = date == null
                            ? ''
                            : '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * .78,
                            ),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: mine
                                  ? colors.primary.withValues(alpha: 0.16)
                                  : colors.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                UserAvatar(
                                  url:
                                      (mine
                                              ? _selfProfile
                                              : _peerProfile)?['avatar_url']
                                          as String?,
                                  radius: 16,
                                  backgroundColor: colors.surface,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item['content'] as String,
                                  style: TextStyle(
                                    color: mine
                                        ? colors.onSurface
                                        : colors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: mine
                                        ? colors.onSurface
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      readOnly: _sending || !_canSend,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        hintText: _canSend ? '输入私信' : '当前无法发送私信',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy || _sending || !_canSend ? null : _send,
                    child: const Text('发送'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
