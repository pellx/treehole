import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/dm_api.dart';
import '../../services/account_display.dart';
import '../../services/dm_notifications.dart';
import '../../services/dm_inbox.dart';
import '../../services/realtime_service.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/dm_conversation_tile.dart';
import '../../widgets/message_inbox_shortcuts.dart';
import '../../theme/app_messages_theme.dart';
import '../account/register_page.dart';
import 'dm_chat_page.dart';
import 'system_inbox_page.dart';

class MessagesPage extends StatefulWidget {
  final bool active;
  final DmApi? api;
  const MessagesPage({super.key, this.active = true, this.api});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage>
    with WidgetsBindingObserver {
  DmApi? _api;
  final List<Map<String, dynamic>> _items = [];
  int? _userId;
  int? _next;
  int _nextPinned = 0;
  Map<String, dynamic> _systemCounts = {};
  int _generation = 0;
  bool _busy = false;
  bool _initializing = true;
  bool _openingSystemInbox = false;
  bool _failed = false;
  bool _refreshPending = false;
  StreamSubscription? _realtimeSubscription;
  bool _requiresLogin = false;
  bool _notificationsEnabled = false;

  Future<void> _prefetchSystemInboxes(DmApi api) async {
    await Future.wait([
      for (final category in ['reply', 'announcement', 'moderation'])
        api
            .systemRequest('?category=$category')
            .then((_) {}, onError: (Object _) {}),
    ]);
  }

  Future<void> _refreshNotificationPermission() async {
    try {
      final enabled = await DmNotifications.permissionEnabled();
      if (mounted) setState(() => _notificationsEnabled = enabled == true);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _realtimeSubscription = RealtimeService.instance.dmEvents.listen((event) {
      if (!mounted || _api == null || event.sessionId != _api!.sessionId) {
        return;
      }
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (event.notify && widget.active) {
        showAppToast(context, message: '收到一条新私信');
      }
      if (_busy) {
        _refreshPending = true;
        return;
      }
      _load(reset: true, silent: true);
    });
    WidgetsBinding.instance.addObserver(this);
    accountDisplayEpoch.addListener(_accountChanged);
    unawaited(_refreshNotificationPermission());
    _scheduleReload();
  }

  void _scheduleReload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_busy) {
        _refreshPending = true;
      } else {
        _load(reset: true, silent: true);
      }
    });
  }

  void _accountChanged() {
    if (!mounted) return;
    _generation++;
    _api?.close();
    _api = null;
    setState(() {
      _busy = false;
      _initializing = true;
      _items.clear();
      _userId = null;
      _next = null;
      _nextPinned = 0;
      _systemCounts = {};
      _refreshPending = false;
    });
    _scheduleReload();
  }

  @override
  void didUpdateWidget(covariant MessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _scheduleReload();
      unawaited(_refreshNotificationPermission());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      _load(reset: true, silent: true);
      unawaited(_refreshNotificationPermission());
    }
  }

  Future<void> _load({bool reset = false, bool silent = false}) async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      _requiresLogin = false;
    });
    try {
      if (reset && (!silent || _api == null)) {
        _api?.close();
        _api = null;
        final local = widget.api == null ? await DmApi.openLocal() : null;
        final cachedAccount = local?.accountToken;
        if (local != null) {
          try {
            final cached = await local.cached('dm', 'conversations');
            final summary = await local.cached('system', 'summary');
            if (mounted && generation == _generation && cached != null) {
              setState(() {
                _items
                  ..clear()
                  ..addAll(
                    (cached['items'] as List).cast<Map<String, dynamic>>(),
                  );
                _userId = cached['user_id'] as int?;
                _next = cached['next_before_id'] as int?;
                _nextPinned = cached['next_before_pinned'] as int? ?? 0;
                _systemCounts =
                    summary?['counts'] as Map<String, dynamic>? ?? {};
              });
            }
          } finally {
            local.close();
          }
        } else {
          setState(() {
            _items.clear();
            _userId = null;
            _next = null;
            _systemCounts = {};
          });
        }
        final api = widget.api ?? await DmApi.open();
        if (!mounted || generation != _generation) {
          api.close();
          return;
        }
        if (cachedAccount != api.accountToken) {
          setState(() {
            _items.clear();
            _userId = null;
            _next = null;
            _systemCounts = {};
          });
        }
        _api = api;
        unawaited(_prefetchSystemInboxes(api));
      }
      if (!mounted || generation != _generation || _api == null) return;
      final api = _api!;
      final data = await api.request(
        'conversations${!reset && _next != null ? '?before_id=$_next&before_pinned=$_nextPinned' : ''}',
      );
      if (!mounted || generation != _generation) return;
      final summary = await api.systemRequest('summary');
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.clear();
        _userId = data['user_id'] as int;
        _items.addAll((data['items'] as List).cast<Map<String, dynamic>>());
        _next = data['next_before_id'] as int?;
        _nextPinned = data['next_before_pinned'] as int? ?? 0;
        _systemCounts = summary['counts'] as Map<String, dynamic>;
      });
      if (widget.active) unawaited(DmInbox.refresh());
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _failed = true;
          _requiresLogin = error is DmException && error.requiresLogin;
          if (_requiresLogin) {
            _items.clear();
            _userId = null;
            _systemCounts = {};
          }
        });
        if (!silent) showAppToast(context, message: error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _initializing = false;
        });
        if (_refreshPending) {
          _refreshPending = false;
          _load(reset: true, silent: true);
        }
      }
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      await DmNotifications.openSystemNotificationSettings();
      await _refreshNotificationPermission();
    } catch (_) {
      if (mounted) showAppToast(context, message: '无法打开通知设置');
    }
  }

  Future<void> _login() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterPage(startAtLogin: true)),
    );
    if (mounted) await _load(reset: true);
  }

  Future<void> _open(Map<String, dynamic> conversation) async {
    if (_api == null || _userId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DmChatPage(
          api: _api!,
          conversationId: conversation['id'] as int,
          peerId: conversation['peer_user_id'] as int,
          userId: _userId!,
        ),
      ),
    );
    if (mounted && widget.active) await _load(reset: true, silent: true);
  }

  Future<void> _openSystemInbox(String category, String title) async {
    if (_openingSystemInbox || (_busy && _api == null)) return;
    if (_api == null || _userId == null) {
      await _login();
      return;
    }
    final api = _api!;
    final path = '?category=$category';
    setState(() => _openingSystemInbox = true);
    Map<String, dynamic>? initialData;
    var refreshOnOpen = false;
    try {
      initialData = await api.cached('system', path);
      if (initialData == null || (initialData['items'] as List).isEmpty) {
        initialData = await api.systemRequest(path);
      } else {
        refreshOnOpen = true;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _openingSystemInbox = false);
      showAppToast(context, message: error.toString());
      return;
    }
    if (!mounted) return;
    setState(() => _openingSystemInbox = false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SystemInboxPage(
          api: api,
          category: category,
          title: title,
          initialData: initialData,
          refreshOnOpen: refreshOnOpen,
        ),
      ),
    );
    if (mounted && widget.active) await _load(reset: true, silent: true);
  }

  Future<void> _create() async {
    if (_busy || _api == null || _userId == null) return;
    final peer = await showDialog<int>(
      context: context,
      builder: (_) => _PeerDialog(userId: _userId!),
    );
    if (peer == null || !mounted) return;
    setState(() => _busy = true);
    Map<String, dynamic>? conversation;
    try {
      final result = await _api!.request(
        'conversations',
        body: {'peer_user_id': peer},
      );
      conversation = result['conversation'] as Map<String, dynamic>;
    } catch (error) {
      if (mounted) showAppToast(context, message: error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && conversation != null) await _open(conversation);
  }

  Future<void> _clearUnread() async {
    if (_busy || _api == null || _userId == null) return;
    setState(() => _busy = true);
    try {
      await _api!.request('read-all', body: {});
      if (!mounted) return;
      setState(() {
        for (final item in _items) {
          item['unread_count'] = 0;
        }
        _systemCounts = {'announcement': 0, 'moderation': 0, 'reply': 0};
      });
      unawaited(DmInbox.refresh());
      showAppToast(context, message: '已清理未读消息');
    } catch (error) {
      if (mounted) showAppToast(context, message: error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && widget.active) await _load(reset: true, silent: true);
  }

  void _showActions() {
    showAppActionsSheet(
      context: context,
      actions: [
        AppSheetAction(
          icon: Icons.add_comment_outlined,
          label: '发起私信',
          onTap: () => _create(),
        ),
        AppSheetAction(
          icon: Icons.refresh,
          label: '刷新消息',
          onTap: () => _load(reset: true, silent: true),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _generation++;
    _realtimeSubscription?.cancel();
    _api?.close();
    accountDisplayEpoch.removeListener(_accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesTheme = AppMessagesTheme.forBrightness(
      Theme.of(context).brightness,
    );
    return AppScaffold(
      title: '消息',
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppMessagesTheme.backgroundDark
          : AppMessagesTheme.backgroundLight,
      appBarBackgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppMessagesTheme.headerBackgroundDark
          : AppMessagesTheme.headerBackgroundLight,
      appBarHeight: AppMessagesTheme.headerHeight,
      appBarTitleOffsetY: AppMessagesTheme.headerTitleOffsetY,
      automaticallyImplyLeading: false,
      leading: Transform.translate(
        offset: const Offset(
          AppMessagesTheme.notificationBellOffsetX,
          AppMessagesTheme.notificationBellOffsetY,
        ),
        child: IconButton(
          tooltip: _notificationsEnabled ? '消息通知已开启，打开系统设置' : '开启消息通知',
          onPressed: _openNotificationSettings,
          iconSize: AppMessagesTheme.notificationBellSize,
          icon: _notificationsEnabled
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.notifications,
                      color: messagesTheme.notificationBellOnColor,
                    ),
                    Icon(
                      Icons.check,
                      size: AppMessagesTheme.notificationCheckSize,
                      color: messagesTheme.notificationCheckColor,
                    ),
                  ],
                )
              : Icon(
                  Icons.notifications_none,
                  color: messagesTheme.notificationBellOffColor,
                ),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(0, AppMessagesTheme.clearUnreadOffsetY),
            child: IconButton(
              tooltip: '一键清理未读',
              onPressed: _clearUnread,
              iconSize: AppMessagesTheme.headerActionIconSize,
              icon: const Icon(Icons.done_all),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, AppMessagesTheme.moreActionsOffsetY),
            child: IconButton(
              tooltip: '更多消息操作',
              onPressed: _showActions,
              iconSize: AppMessagesTheme.headerActionIconSize,
              icon: const Icon(Icons.more_vert),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              MessageInboxShortcuts(
                counts: _systemCounts,
                showUnread: _userId != null,
                onOpen: _openingSystemInbox || (_busy && _api == null)
                    ? null
                    : _openSystemInbox,
              ),
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: _busy || _initializing
                            ? const SizedBox.shrink()
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_failed ? '暂未获取到会话' : '还没有私信会话'),
                                  const SizedBox(height: 12),
                                  if (_userId != null)
                                    FilledButton(
                                      onPressed: _create,
                                      child: const Text('发起私信'),
                                    ),
                                  if (_requiresLogin)
                                    TextButton(
                                      onPressed: _login,
                                      child: const Text('登录'),
                                    ),
                                  if (_failed)
                                    TextButton(
                                      onPressed: () => _load(reset: true),
                                      child: const Text('重试'),
                                    ),
                                ],
                              ),
                      )
                    : Transform.translate(
                        offset: Offset(
                          0,
                          AppMessagesTheme.conversationFirstTopPadding < 0
                              ? AppMessagesTheme.conversationFirstTopPadding
                              : 0,
                        ),
                        child: RefreshIndicator(
                          onRefresh: () => _load(reset: true),
                          child: ListView.builder(
                            padding: EdgeInsets.only(
                              top:
                                  AppMessagesTheme.conversationFirstTopPadding >
                                      0
                                  ? AppMessagesTheme.conversationFirstTopPadding
                                  : 0,
                            ),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _items.length + (_next == null ? 0 : 1),
                            itemBuilder: (context, index) {
                              if (index == _items.length) {
                                return TextButton(
                                  onPressed: _busy ? null : () => _load(),
                                  child: const Text('加载更多会话'),
                                );
                              }
                              final item = _items[index];
                              return DmConversationTile(
                                conversation: item,
                                isFirst: index == 0,
                                onTap: _api == null ? null : () => _open(item),
                              );
                            },
                          ),
                        ),
                      ),
              ),
            ],
          ),
          if (_openingSystemInbox)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _PeerDialog extends StatefulWidget {
  final int userId;
  const _PeerDialog({required this.userId});
  @override
  State<_PeerDialog> createState() => _PeerDialogState();
}

class _PeerDialogState extends State<_PeerDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final id = int.tryParse(_controller.text);
    if (id == null || id < 1 || id > 2147483647 || id == widget.userId) {
      showAppToast(context, message: '请输入其他用户的有效 ID');
      return;
    }
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('发起私信'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      decoration: const InputDecoration(labelText: '对方用户 ID'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('开始聊天')),
    ],
  );
}
