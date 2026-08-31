import 'package:flutter/material.dart';

import '../../widgets/app_app_bar.dart';
import '../../widgets/app_empty_state.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: '消息',
      body: AppEmptyState(message: '消息功能即将上线', icon: Icons.chat_bubble_outline),
    );
  }
}
