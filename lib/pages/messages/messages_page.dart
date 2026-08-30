import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/account_display.dart';
import '../../services/chat_inbox.dart';
import '../../services/storage.dart';
import '../../services/timezone_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading_indicator.dart';
import '../account/register_page.dart';
import '../settings/settings_navigation.dart';
import 'chat_navigation.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => MessagesPageState();
}

class MessagesPageState extends State<MessagesPage> {
  final _inbox = ChatInbox.instance;

  @override
  void initState() {
    super.initState();
    _inbox.attach();
    _inbox.addListener(_onInbox);
    accountDisplayEpoch.addListener(_onAccountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (PostStorage.isRegistered()) {
        _inbox.reload();
      }
    });
  }

  @override
  void dispose() {
    accountDisplayEpoch.removeListener(_onAccountChanged);
    _inbox.removeListener(_onInbox);
    super.dispose();
  }

  void _onAccountChanged() {
    if (PostStorage.isRegistered()) {
      _inbox.reload();
    } else {
      _inbox.reset();
    }
  }

  void onBecameVisible() {
    if (PostStorage.isRegistered()) {
      if (_inbox.items.isEmpty && !_inbox.loading) {
        _inbox.reload();
      } else {
        setState(() {});
      }
    } else {
      setState(() {});
    }
  }

  void _onInbox() {
    if (mounted) setState(() {});
  }

  Future<void> _promptSearch() async {
    final colors = Theme.of(context).extension<AppColors>()!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.common.surface,
          title: const Text('发起私聊'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入对方当前昵称',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name != null && name.isNotEmpty && mounted) {
      await openPrivateChat(context, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final registered = PostStorage.isRegistered();

    return AppScaffold(
      title: '消息',
      automaticallyImplyLeading: false,
      trailing: registered
          ? IconButton(
              tooltip: '发起私聊',
              icon: Icon(Icons.edit_outlined, color: colors.common.barText),
              onPressed: () {
                HapticFeedback.lightImpact();
                _promptSearch();
              },
            )
          : null,
      body: !registered
          ? AppEmptyState(
              message: '登录后查看私信',
              icon: Icons.chat_bubble_outline,
              actionLabel: '去注册 / 登录',
              onAction: () async {
                await Navigator.of(context).push(bottomUpRoute(const RegisterPage()));
                if (!context.mounted) return;
                if (PostStorage.isRegistered()) {
                  await _inbox.reload();
                } else {
                  setState(() {});
                }
              },
            )
          : _buildBody(colors),
    );
  }

  Widget _buildBody(AppColors colors) {
    if (_inbox.loading && _inbox.items.isEmpty) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_inbox.error != null && _inbox.items.isEmpty) {
      return AppErrorState(
        message: _inbox.error!,
        onRetry: _inbox.reload,
      );
    }
    if (_inbox.items.isEmpty) {
      return AppEmptyState(
        message: '还没有私信\n可点右上角或广场署名作者发起',
        icon: Icons.chat_bubble_outline,
        actionLabel: '发起私聊',
        onAction: _promptSearch,
      );
    }

    return RefreshIndicator(
      color: colors.common.green,
      onRefresh: _inbox.reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _inbox.items.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 0.5,
          color: colors.common.divider,
        ),
        itemBuilder: (context, index) {
          final conv = _inbox.items[index];
          final unread = conv.unreadCount > 0;
          return ListTile(
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            title: Text(
              conv.peerDisplayId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                color: colors.common.onSurface,
              ),
            ),
            subtitle: Text(
              conv.lastPreview?.isNotEmpty == true ? conv.lastPreview! : '暂无消息',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: colors.common.onSurface.withValues(alpha: unread ? 0.75 : 0.45),
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  TimezoneService.format(conv.lastMessageAt, showDate: false),
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.common.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                if (unread) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: colors.postCreate.submitBg,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              openConversation(context, conv);
            },
          );
        },
      ),
    );
  }
}
