import 'package:flutter/material.dart';

import '../../models/chat.dart';
import '../../services/api.dart';
import '../../services/chat_api.dart';
import '../../services/chat_inbox.dart';
import '../../services/storage.dart';
import '../../widgets/app_snackbar.dart';
import '../account/register_page.dart';
import '../settings/settings_navigation.dart';
import 'chat_thread_page.dart';

/// 从昵称打开一对一会话（广场署名作者 / 消息页搜索）。
Future<void> openPrivateChat(BuildContext context, String displayId) async {
  final name = displayId.trim();
  if (name.isEmpty) return;

  if (!PostStorage.isRegistered()) {
    await Navigator.of(context).push(bottomUpRoute(const RegisterPage()));
    if (!context.mounted) return;
    if (!PostStorage.isRegistered()) return;
  }

  final ready = await ChatInbox.instance.ensureReady();
  if (!context.mounted) return;
  if (!ready) {
    showAppSnackBar(context, message: '请先登录后再私聊');
    return;
  }

  final conv = await ChatApi.openDm(peerDisplayId: name);
  if (!context.mounted) return;
  if (conv == null) {
    showAppSnackBar(
      context,
      message: ChatInbox.friendlyError(ApiService.lastError),
    );
    return;
  }
  ChatInbox.instance.upsertConversation(conv);
  await Navigator.of(context).push(topDownRoute(ChatThreadPage(conversation: conv)));
}

Future<void> openConversation(
  BuildContext context,
  ChatConversation conversation,
) {
  ChatInbox.instance.markLocalRead(conversation.id);
  return Navigator.of(context).push(
    topDownRoute(ChatThreadPage(conversation: conversation)),
  );
}
