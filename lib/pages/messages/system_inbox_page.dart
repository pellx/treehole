import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/dm_api.dart';
import '../../services/dm_inbox.dart';
import '../../services/realtime_service.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_toast.dart';

class SystemInboxPage extends StatefulWidget {
  final DmApi api;
  final String category;
  final String title;
  const SystemInboxPage({
    super.key,
    required this.api,
    required this.category,
    required this.title,
  });
  @override
  State<SystemInboxPage> createState() => _SystemInboxPageState();
}

class _SystemInboxPageState extends State<SystemInboxPage>
    with WidgetsBindingObserver {
  final List<Map<String, dynamic>> _items = [];
  int? _next;
  bool _busy = false;
  bool _failed = false;
  bool _pending = false;
  StreamSubscription? _events;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events = RealtimeService.instance.dmEvents.listen((event) {
      if (event.sessionId == widget.api.sessionId &&
          (event.conversationId == null || event.conversationId == 0)) {
        if (_busy) {
          _pending = true;
        } else {
          _load(reset: true, silent: true);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(reset: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_busy) {
        _pending = true;
      } else {
        _load(reset: true, silent: true);
      }
    }
  }

  Future<void> _load({bool reset = false, bool silent = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final dismiss = silent
        ? () {}
        : showAppToast(
            context,
            message: '正在获取消息',
            duration: const Duration(seconds: 25),
          );
    try {
      final data = await widget.api.systemRequest(
        '?category=${widget.category}${!reset && _next != null ? '&before_id=$_next' : ''}',
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll((data['items'] as List).cast<Map<String, dynamic>>());
        _next = data['next_before_id'] as int?;
      });
    } catch (error) {
      dismiss();
      if (mounted) {
        setState(() => _failed = true);
        if (!silent) showAppToast(context, message: error.toString());
      }
    } finally {
      dismiss();
      if (mounted) {
        setState(() => _busy = false);
        if (_pending) {
          _pending = false;
          _load(reset: true, silent: true);
        }
      }
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SystemMessageDetail(api: widget.api, item: item),
      ),
    );
    if (mounted) await _load(reset: true, silent: true);
  }

  @override
  void dispose() {
    _events?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: widget.title,
    trailing: IconButton(
      tooltip: '刷新',
      onPressed: _busy ? null : () => _load(reset: true),
      icon: const Icon(Icons.refresh),
    ),
    body: _items.isEmpty
        ? Center(
            child: _busy
                ? const SizedBox.shrink()
                : _failed
                ? TextButton(
                    onPressed: () => _load(reset: true),
                    child: const Text('获取失败，点击重试'),
                  )
                : Text('暂无${widget.title}'),
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
                    child: const Text('查看更多'),
                  );
                }
                final item = _items[index];
                return ListTile(
                  leading: Badge(
                    isLabelVisible: item['is_read'] != true,
                    child: const Icon(Icons.article_outlined),
                  ),
                  title: Text(item['title'] as String),
                  subtitle: Text(
                    item['content'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _open(item),
                );
              },
            ),
          ),
  );
}

class _SystemMessageDetail extends StatefulWidget {
  final DmApi api;
  final Map<String, dynamic> item;
  const _SystemMessageDetail({required this.api, required this.item});
  @override
  State<_SystemMessageDetail> createState() => _SystemMessageDetailState();
}

class _SystemMessageDetailState extends State<_SystemMessageDetail> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  Future<void> _read() async {
    try {
      await widget.api.systemRequest('${widget.item['id']}/read', body: {});
      await DmInbox.refresh();
    } catch (error) {
      if (mounted) showAppToast(context, message: '标记已读失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final date = DateTime.tryParse(
      item['created_at']?.toString() ?? '',
    )?.toLocal();
    return AppScaffold(
      title: item['title'] as String,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (date != null)
              Text(
                date.toString().split('.').first,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            const SizedBox(height: 16),
            SelectableText(item['content'] as String),
            if (item['post_id'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SelectableText('关联帖子 #${item['post_id']}'),
              ),
          ],
        ),
      ),
    );
  }
}
