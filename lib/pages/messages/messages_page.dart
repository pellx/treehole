import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/dm_api.dart';
import '../../services/dm_notifications.dart';
import '../../services/dm_inbox.dart';
import '../../services/realtime_service.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/user_avatar.dart';
import '../account/register_page.dart';
import 'dm_chat_page.dart';
import 'system_inbox_page.dart';

class MessagesPage extends StatefulWidget {
  final bool active;
  const MessagesPage({super.key, this.active = true});

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
  bool _failed = false;
  bool _refreshPending = false;
  StreamSubscription? _realtimeSubscription;
  bool _requiresLogin = false;

  @override
  void initState() {
    super.initState();
    _realtimeSubscription = RealtimeService.instance.dmEvents.listen((event) {
      if (!mounted ||
          !widget.active ||
          _api == null ||
          event.sessionId != _api!.sessionId) {
        return;
      }
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (event.notify) showAppToast(context, message: '收到一条新私信');
      if (_busy) {
        _refreshPending = true;
        return;
      }
      _load(reset: true, silent: true);
    });
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _scheduleReload();
  }

  void _scheduleReload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _load(reset: true, silent: true);
    });
  }

  @override
  void didUpdateWidget(covariant MessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      _generation++;
      _busy = false;
      _items.clear();
      _userId = null;
      _api?.close();
      _api = null;
      if (widget.active) _scheduleReload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.active &&
        ModalRoute.of(context)?.isCurrent == true) {
      _load(reset: true);
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
        final local = await DmApi.openLocal();
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
        final api = await DmApi.open();
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
      }
      final data = await _api!.request(
        'conversations${!reset && _next != null ? '?before_id=$_next&before_pinned=$_nextPinned' : ''}',
      );
      final summary = await _api!.systemRequest('summary');
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.clear();
        _userId = data['user_id'] as int;
        _items.addAll((data['items'] as List).cast<Map<String, dynamic>>());
        _next = data['next_before_id'] as int?;
        _nextPinned = data['next_before_pinned'] as int? ?? 0;
        _systemCounts = summary['counts'] as Map<String, dynamic>;
      });
      unawaited(DmInbox.refresh());
      unawaited(
        DmNotifications.requestPermission(once: true).catchError((_) => false),
      );
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
        setState(() => _busy = false);
        if (_refreshPending && widget.active) {
          _refreshPending = false;
          _load(reset: true, silent: true);
        }
      }
    }
  }

  Future<void> _requestNotifications() async {
    try {
      final enabled = await DmNotifications.requestPermission();
      if (mounted) {
        showAppToast(
          context,
          message: enabled == true ? '已开启通知权限' : '未开启通知，可在系统设置中开启',
        );
      }
    } catch (_) {
      if (mounted) showAppToast(context, message: '无法申请通知权限，请在系统设置中检查');
    }
  }

  Future<void> _login() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterPage(startAtLogin: true)),
    );
    if (mounted) await _load(reset: true);
  }

  Future<void> _open(Map<String, dynamic> conversation) async {
    if (_busy || _api == null || _userId == null) return;
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
        AppSheetAction(
          icon: Icons.notifications_outlined,
          label: '通知权限',
          onTap: () => _requestNotifications(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _generation++;
    _realtimeSubscription?.cancel();
    _api?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '消息',
      automaticallyImplyLeading: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '一键清理未读',
            onPressed: _busy || _api == null || _userId == null
                ? null
                : _clearUnread,
            icon: const Icon(Icons.done_all),
          ),
          IconButton(
            tooltip: '更多消息操作',
            onPressed: _busy ? null : _showActions,
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: Column(
        children: [
          for (final category in [
            ('announcement', '公告', Icons.campaign_outlined),
            ('moderation', '审核与举报', Icons.verified_user_outlined),
            ('reply', '帖子回复', Icons.forum_outlined),
          ])
            ListTile(
              leading: Icon(category.$3),
              title: Text(category.$2),
              trailing: Badge(
                isLabelVisible:
                    _userId != null &&
                    (_systemCounts[category.$1] as int? ?? 0) > 0,
                label: Text((_systemCounts[category.$1] ?? 0).toString()),
                child: const Icon(Icons.chevron_right),
              ),
              onTap: _busy
                  ? null
                  : () async {
                      if (_api == null || _userId == null) {
                        await _login();
                        return;
                      }
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SystemInboxPage(
                            api: _api!,
                            category: category.$1,
                            title: category.$2,
                          ),
                        ),
                      );
                      if (mounted && widget.active) {
                        await _load(reset: true, silent: true);
                      }
                    },
            ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: _busy
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
                : RefreshIndicator(
                    onRefresh: () => _load(reset: true),
                    child: ListView.builder(
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
                        return ListTile(
                          leading: UserAvatar(
                            url:
                                (item['peer'] as Map?)?['avatar_url']
                                    as String?,
                            radius: 22,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                          ),
                          title: Row(
                            children: [
                              if (item['pinned'] == true)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.push_pin, size: 16),
                                ),
                              Expanded(
                                child: Text('用户 #${item['peer_user_id']}'),
                              ),
                            ],
                          ),
                          subtitle: Text('共 ${item['last_seq']} 条消息'),
                          tileColor: item['pinned'] == true
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.06)
                              : null,
                          trailing: Badge(
                            isLabelVisible:
                                (item['unread_count'] as int? ?? 0) > 0,
                            label: item['muted'] == true
                                ? null
                                : Text(
                                    (item['unread_count'] as int? ?? 0) > 99
                                        ? '99+'
                                        : (item['unread_count'] ?? 0)
                                              .toString(),
                                  ),
                            child: Icon(
                              item['muted'] == true
                                  ? Icons.notifications_off_outlined
                                  : Icons.chevron_right,
                            ),
                          ),
                          onTap: _busy ? null : () => _open(item),
                        );
                      },
                    ),
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
