import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../models/chat.dart';
import '../../services/api.dart';
import '../../services/chat_api.dart';
import '../../services/chat_inbox.dart';
import '../../services/timezone_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/moderation_feedback.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_loading_indicator.dart';
import '../../widgets/app_snackbar.dart';

class ChatThreadPage extends StatefulWidget {
  final ChatConversation conversation;

  const ChatThreadPage({super.key, required this.conversation});

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  static const _uuid = Uuid();

  late ChatConversation _conv;
  final _messages = <ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _sending = false;
  String? _error;

  int? get _selfId => ChatInbox.instance.selfUserId;

  @override
  void initState() {
    super.initState();
    _conv = widget.conversation;
    ChatInbox.instance.addMessageListener(_onRealtime);
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    ChatInbox.instance.removeMessageListener(_onRealtime);
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onRealtime(ChatRealtimePayload payload) {
    if (payload.conversation.id != _conv.id) return;
    _conv = payload.conversation.copyWith(unreadCount: 0);
    final exists = _messages.any((m) => m.id == payload.message.id);
    if (!exists) {
      _messages.add(payload.message);
    }
    if (mounted) setState(() {});
    _markRead();
    _jumpToBottom();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final list = await ChatApi.history(conversationId: _conv.id);
    if (!mounted) return;
    if (list == null) {
      setState(() {
        _loading = false;
        _error = ChatInbox.friendlyError(ApiService.lastError);
      });
      return;
    }
    _messages
      ..clear()
      ..addAll(list);
    _hasMore = list.length >= 30;
    setState(() => _loading = false);
    _markRead();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    _loadingMore = true;
    final older = await ChatApi.history(
      conversationId: _conv.id,
      beforeId: _messages.first.id,
    );
    if (!mounted) return;
    _loadingMore = false;
    if (older == null) return;
    if (older.isEmpty) {
      _hasMore = false;
      setState(() {});
      return;
    }
    _messages.insertAll(0, older);
    _hasMore = older.length >= 30;
    setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 40) {
      _loadMore();
    }
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _markRead() async {
    if (_messages.isEmpty) return;
    final lastId = _messages.last.id;
    await ChatApi.markRead(
      conversationId: _conv.id,
      lastReadMessageId: lastId,
    );
    ChatInbox.instance.markLocalRead(_conv.id);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final msg = await ChatApi.send(
      conversationId: _conv.id,
      body: text,
      clientMsgId: _uuid.v4(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (msg == null) {
      showAppSnackBar(
        context,
        message: getModerationMessage(
          ChatInbox.friendlyError(ApiService.lastError),
        ),
      );
      return;
    }
    _controller.clear();
    if (!_messages.any((m) => m.id == msg.id)) {
      _messages.add(msg);
    }
    _conv = _conv.copyWith(
      lastPreview: text.replaceAll(RegExp(r'\s+'), ' '),
      lastMessageAt: msg.createdAt,
      lastSenderUserId: msg.senderUserId,
      unreadCount: 0,
    );
    ChatInbox.instance.upsertConversation(_conv);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return AppScaffold(
      title: _conv.peerDisplayId,
      body: Column(
        children: [
          Expanded(child: _buildList(colors)),
          _buildInput(colors),
        ],
      ),
    );
  }

  Widget _buildList(AppColors colors) {
    if (_loading) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: TextButton(onPressed: _loadInitial, child: Text(_error!)),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          '还没有消息，打个招呼吧',
          style: TextStyle(
            color: colors.common.onSurface.withValues(alpha: 0.45),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: _messages.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (_loadingMore && index == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: AppLoadingIndicator(size: 22)),
          );
        }
        final msg = _messages[index - (_loadingMore ? 1 : 0)];
        final mine = _selfId != null && msg.senderUserId == _selfId;
        return _Bubble(message: msg, mine: mine, colors: colors);
      },
    );
  }

  Widget _buildInput(AppColors colors) {
    final pc = colors.postCard;
    return SafeArea(
      top: false,
      child: Container(
        color: pc.commentInputBarBg,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: AppDimens.commentInputHeight,
                  maxHeight: AppDimens.commentInputMaxHeight,
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                    fontSize: AppDimens.commentInputFontSize,
                    color: colors.common.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: '发消息…',
                    hintStyle: TextStyle(
                      color: colors.common.onSurface.withValues(alpha: 0.35),
                    ),
                    filled: true,
                    fillColor: pc.commentInputFieldBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.commentInputPaddingH,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimens.commentInputRadius,
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: AppDimens.commentInputHeight,
              child: FilledButton(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.postCreate.submitBg,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('发送'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final AppColors colors;

  const _Bubble({
    required this.message,
    required this.mine,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = mine
        ? colors.postCreate.submitBg
        : colors.postCard.commentBg;
    final textColor = mine ? Colors.white : colors.common.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.74,
              ),
              child: GestureDetector(
                onLongPress: () {
                  HapticFeedback.lightImpact();
                  Clipboard.setData(ClipboardData(text: message.body));
                  showAppSnackBar(context, message: '已复制');
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(mine ? 14 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 14),
                    ),
                  ),
                  child: Text(
                    message.body,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              TimezoneService.format(message.createdAt, showDate: false),
              style: TextStyle(
                fontSize: 10,
                color: colors.common.onSurface.withValues(alpha: 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
