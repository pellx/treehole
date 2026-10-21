import 'package:flutter/material.dart';

import '../../services/dm_mock_data.dart';
import '../../theme/app_dm_theme.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/user_avatar.dart';

/// 消息模块测试模式下的聊天页。
///
/// 数据全部来自 [DmMockData]，不访问网络；视觉与真实聊天页共用
/// [AppDmTheme] 的参数，因此这里看到的间距/字号就是正式页面调整后的效果。
class DmMockChatPage extends StatefulWidget {
  final int conversationId;

  const DmMockChatPage({super.key, required this.conversationId});

  @override
  State<DmMockChatPage> createState() => _DmMockChatPageState();
}

class _DmMockChatPageState extends State<DmMockChatPage> {
  static const int _pageSize = 10;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _visible = _pageSize;
  bool _sending = false;

  DmMockData get _store => DmMockData.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _store.markRead(widget.conversationId);
    });
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final conversation = _store.conversationOf(widget.conversationId);
    if (text.isEmpty || _sending || conversation == null) return;
    if (conversation['status'] != 'accepted') return;
    setState(() => _sending = true);
    _input.clear();
    final message = _store.sendMessage(widget.conversationId, text);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _store.completeSend(widget.conversationId, message['id'] as int);
    setState(() => _sending = false);
    _scrollToBottom();
  }

  String _peerAsset(Map? peer) => peer?['avatar_asset'] as String? ?? '';

  String _time(Map<String, dynamic> item) {
    final date = DateTime.tryParse(
      item['created_at'] as String? ?? '',
    )?.toLocal();
    if (date == null) return '';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.month}/${date.day} $hour:$minute';
  }

  Widget _bubble(Map<String, dynamic> item, String peerAsset) {
    final colors = Theme.of(context).colorScheme;
    final mine = item['sender_id'] == DmMockData.selfUserId;
    final failed = item['local_status'] == 'failed';
    final sending = item['local_status'] == 'sending';
    final messageId = item['id'] as int;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.sizeOf(context).width * AppDmTheme.bubbleMaxWidthRatio,
        ),
        margin: const EdgeInsets.only(bottom: AppDmTheme.bubbleBottomGap),
        padding: const EdgeInsets.all(AppDmTheme.bubblePadding),
        decoration: BoxDecoration(
          color: mine
              ? colors.primary.withValues(alpha: AppDmTheme.bubbleMineAlpha)
              : colors.surface,
          borderRadius: BorderRadius.circular(AppDmTheme.bubbleRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              url: null,
              assetPath: mine ? null : peerAsset,
              radius: AppDmTheme.bubbleAvatarRadius,
              backgroundColor: colors.surface,
            ),
            const SizedBox(height: AppDmTheme.bubbleAvatarGap),
            Text(
              item['content'] as String,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: AppDmTheme.messageTextFontSize,
              ),
            ),
            const SizedBox(height: AppDmTheme.bubbleTimeGap),
            if (failed)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: '测试：发送失败，点击重试',
                  icon: Icon(
                    Icons.error_outline,
                    color: colors.error,
                    size: AppDmTheme.failedIconSize,
                  ),
                  onPressed: () {
                    _store.retrySend(widget.conversationId, messageId);
                    showAppToast(context, message: '正在重试发送');
                  },
                ),
              )
            else if (sending)
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: AppDmTheme.failedIconSize,
                  height: AppDmTheme.failedIconSize,
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
              ),
            Text(
              _time(item),
              style: TextStyle(
                fontSize: AppDmTheme.bubbleTimeFontSize,
                color: mine ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner(Map<String, dynamic> conversation) {
    final colors = Theme.of(context).colorScheme;
    final status = conversation['status'] as String?;
    final isRequester = conversation['is_requester'] == true;
    final rejected = status == 'rejected';
    final text = isRequester
        ? (rejected ? '对方已拒绝你的私信请求，24 小时后可再次申请' : '已发送私信请求，等待对方接受')
        : (rejected ? '你已拒绝该私信请求' : '对方请求与你私信，接受后才能互发消息');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppDmTheme.bannerHorizontalMargin,
        0,
        AppDmTheme.bannerHorizontalMargin,
        AppDmTheme.bannerBottomMargin,
      ),
      padding: const EdgeInsets.all(AppDmTheme.bannerPadding),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: AppDmTheme.bannerBackgroundAlpha),
        borderRadius: BorderRadius.circular(AppDmTheme.bannerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: AppDmTheme.bannerTextFontSize,
            ),
          ),
          if (status == 'pending' && !isRequester) ...[
            const SizedBox(height: AppDmTheme.bannerActionTopGap),
            Row(
              children: [
                SizedBox(
                  height: AppDmTheme.bannerButtonMinHeight,
                  child: OutlinedButton(
                    onPressed: () {
                      _store.reject(widget.conversationId);
                      showAppToast(context, message: '已拒绝私信请求');
                    },
                    child: const Text(
                      '拒绝',
                      style: TextStyle(
                        fontSize: AppDmTheme.bannerButtonFontSize,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDmTheme.bannerButtonGap),
                SizedBox(
                  height: AppDmTheme.bannerButtonMinHeight,
                  child: FilledButton(
                    onPressed: () {
                      _store.accept(widget.conversationId);
                      showAppToast(context, message: '已接受私信请求');
                    },
                    child: const Text(
                      '同意',
                      style: TextStyle(
                        fontSize: AppDmTheme.bannerButtonFontSize,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDmTheme.composerHorizontalPadding,
        AppDmTheme.composerTopPadding,
        AppDmTheme.composerHorizontalPadding,
        AppDmTheme.composerBottomPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: AppDmTheme.composerMinLines,
              maxLines: AppDmTheme.composerMaxLines,
              maxLength: AppDmTheme.composerMaxLength,
              style: const TextStyle(fontSize: AppDmTheme.composerFontSize),
              decoration: const InputDecoration(
                hintText: '输入私信（测试数据，不会真的发送）',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: AppDmTheme.composerSendGap),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: const Text(
              '发送',
              style: TextStyle(fontSize: AppDmTheme.composerSendFontSize),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _store.conversationOf(widget.conversationId);
    if (conversation == null) {
      return const AppScaffold(
        title: '测试会话',
        body: Center(child: Text('会话不存在，可能已被重置')),
      );
    }
    final peer = conversation['peer'] as Map?;
    final name = (peer?['user_display_id'] as String?) ?? '用户';
    final status = conversation['status'] as String? ?? 'accepted';
    final all = _store.messagesOf(widget.conversationId);
    final start = all.length > _visible ? all.length - _visible : 0;
    final shown = all.sublist(start).reversed.toList();
    final peerAsset = _peerAsset(peer);

    return AppScaffold(
      title: name,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        '还没有消息，打个招呼吧',
                        style: const TextStyle(
                          fontSize: AppDmTheme.emptyChatFontSize,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.all(
                        AppDmTheme.messageListPadding,
                      ),
                      itemCount: shown.length + (start > 0 ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == shown.length) {
                          return TextButton(
                            onPressed: () =>
                                setState(() => _visible += _pageSize),
                            child: const Text(
                              '加载更早消息',
                              style: TextStyle(
                                fontSize: AppDmTheme.loadOlderFontSize,
                              ),
                            ),
                          );
                        }
                        return _bubble(shown[index], peerAsset);
                      },
                    ),
            ),
            if (status != 'accepted') _banner(conversation),
            if (status == 'accepted') _composer(),
          ],
        ),
      ),
    );
  }
}
