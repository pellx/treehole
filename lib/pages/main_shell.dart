import 'dart:async';
import '../services/realtime_service.dart';
import '../services/dm_inbox.dart';
import '../services/dm_notifications.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_bottom_nav.dart';
import '../pages/square/square_page.dart';
import '../pages/favorites/favorites_page.dart';
import '../pages/messages/messages_page.dart';
import '../pages/account/user_page.dart';
import '../pages/post/post_create_page.dart';
import '../pages/settings/settings_navigation.dart';

/// 应用主外壳：底部导航栏 + 各 Tab 内容
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  StreamSubscription? _dmSubscription;
  @override
  void initState() {
    super.initState();
    DmNotifications.onOpenMessages = () {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() => _currentIndex = 2);
      DmInbox.refresh();
    };
    unawaited(DmNotifications.initialize().catchError((_) {}));
    RealtimeService.instance.connectionLabel.addListener(_connectionChanged);
    _dmSubscription = RealtimeService.instance.dmEvents.listen((event) {
      DmInbox.refresh();
      if (event.notify &&
          event.conversationId != null &&
          !(DmInbox.visibleConversationId == event.conversationId &&
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed)) {
        unawaited(DmNotifications.show(event.sessionId, event.conversationId!));
        if (mounted &&
            _currentIndex != 2 &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          showAppToast(context, message: '收到一条新私信');
        }
      }
    });
    DmInbox.refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_remindNotificationPermission());
    });
  }

  Future<void> _remindNotificationPermission() async {
    if (!DmNotifications.supportsNotifications) return;
    try {
      if (!await DmNotifications.consumeStartupReminder() || !mounted) return;
      final enabled = await DmNotifications.permissionEnabled();
      if (!mounted || enabled == true) return;
      final confirmed = await showAppConfirmDialog(
        context,
        title: '开启消息通知',
        message: '开启消息通知，及时收到新私信提醒。之后也可在消息页点击铃铛调整。',
        cancelText: '暂不开启',
        confirmText: '开启通知',
      );
      if (!mounted || confirmed != true) return;
      await DmNotifications.requestPermission();
    } catch (_) {
      if (mounted) {
        showAppToast(context, message: '暂时无法请求通知权限，可在消息页点击铃铛开启');
      }
    }
  }

  void _connectionChanged() {
    if (RealtimeService.instance.connectionLabel.value == '未连接') {
      DmInbox.unread.value = 0;
      DmInbox.hasUnread.value = false;
      unawaited(DmNotifications.clear());
    }
  }

  @override
  void dispose() {
    _dmSubscription?.cancel();
    RealtimeService.instance.connectionLabel.removeListener(_connectionChanged);
    DmNotifications.onOpenMessages = null;
    super.dispose();
  }

  int _currentIndex = 0;
  final _homeKey = GlobalKey<SquarePageState>();
  final _favoritesKey = GlobalKey();
  final _messagesKey = GlobalKey();
  final _userKey = GlobalKey();

  static const _labels = ['广场', '收藏', '消息', '我的'];

  Future<void> _openCreatePost() async {
    HapticFeedback.lightImpact();
    final result = await Navigator.of(
      context,
    ).push<bool>(topDownRoute(const PostCreatePage()));
    if (result == true && mounted) {
      // 发布成功后切回主页默认分类并刷新
      setState(() => _currentIndex = 0);
      _homeKey.currentState?.resetToDefault();
    }
  }

  void _onTap(int index) {
    DmInbox.refresh();
    if (index != _currentIndex) {
      HapticFeedback.lightImpact();
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      SquarePage(key: _homeKey),
      FavoritesPage(key: _favoritesKey),
      MessagesPage(key: _messagesKey, active: _currentIndex == 2),
      UserPage(key: _userKey),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: AnimatedBuilder(
        animation: Listenable.merge([DmInbox.unread, DmInbox.hasUnread]),
        builder: (context, _) => AppBottomNav(
          unreadCount: DmInbox.unread.value,
          hasUnread: DmInbox.hasUnread.value,
          currentIndex: _currentIndex,
          onTap: _onTap,
          onPublishTap: _openCreatePost,
          labels: _labels,
        ),
      ),
    );
  }
}
