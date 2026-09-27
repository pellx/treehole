import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/user_avatar.dart';

/// 用户信息详情页
class UserProfilePage extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final String token;

  const UserProfilePage({
    super.key,
    this.avatarUrl,
    required this.name,
    required this.token,
  });

  void _copyToken(BuildContext context) {
    if (token.isEmpty) return;
    Clipboard.setData(ClipboardData(text: token));
    showAppToast(
      context,
      message: '已复制用户令牌',
      duration: const Duration(seconds: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const head = 4;
    const tail = 4;
    final display = token.isEmpty
        ? '—'
        : (token.length > head + tail
              ? '${token.substring(0, head)}...${token.substring(token.length - tail)}'
              : token);

    return AppScaffold(
      title: '个人资料',
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          Center(
            child: UserAvatar(
              url: avatarUrl,
              radius: 60,
              backgroundColor: colors.common.idTint.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              name.isEmpty ? '未设置昵称' : name,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
          ),
          const SizedBox(height: 40),
          _infoTile(
            context,
            colors,
            onSurface,
            label: '昵称',
            value: name.isEmpty ? '未设置昵称' : name,
          ),
          const SizedBox(height: 12),
          _infoTile(
            context,
            colors,
            onSurface,
            label: '用户令牌',
            value: display,
            onTap: () => _copyToken(context),
            trailingIcon: Icons.copy_outlined,
          ),
        ],
      ),
    );
  }

  Widget _infoTile(
    BuildContext context,
    AppColors colors,
    Color onSurface, {
    required String label,
    required String value,
    VoidCallback? onTap,
    IconData? trailingIcon,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: colors.common.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: onSurface.withValues(alpha: 0.6),
              ),
            ),
            const Spacer(),
            Text(value, style: TextStyle(fontSize: 15, color: onSurface)),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, size: 18, color: colors.common.green),
            ],
          ],
        ),
      ),
    );
  }
}
