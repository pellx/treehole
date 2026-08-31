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
      MessagesPage(key: _messagesKey),
      UserPage(key: _userKey),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onTap: _onTap,
        onPublishTap: _openCreatePost,
        labels: _labels,
      ),
    );
  }
}
