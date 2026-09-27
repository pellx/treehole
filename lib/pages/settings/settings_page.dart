import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_dimens_accent.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_toast.dart';
import 'notification_settings_page.dart';
import 'privacy_policy_page.dart';
import 'settings_navigation.dart';
import 'system_settings_page.dart';
import 'user_settings_page.dart';

/// 设置列表页
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _debugMode = false;

  Future<void> _confirmClearData() async {
    final confirmed = await showAppConfirmDialog(
      context,
      message:
          '确定要清空本地数据吗？此操作不会删除服务器上的账户信息，但会清除本地缓存、头像等数据。',
      cancelText: '取消',
      confirmText: '确认',
    );
    if (confirmed == true && mounted) {
      showAppToast(
        context,
        message: '本地数据清理功能即将上线',
        duration: const Duration(seconds: 2),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return AppScaffold(
      title: '设置',
      body: ListView(
        padding: const EdgeInsets.all(AccentDimens.pagePadding),
        children: [
          _groupTitle(context, '用户'),
          _navTile(
            context,
            icon: Icons.person_outline,
            label: '用户设置',
            onTap: () => Navigator.of(
              context,
            ).push(topDownRoute(const UserSettingsPage())),
          ),
          _itemDivider(colors),
          _navTile(
            context,
            icon: Icons.notifications_outlined,
            label: '消息提醒设置',
            onTap: () => Navigator.of(
              context,
            ).push(topDownRoute(const NotificationSettingsPage())),
          ),
          _itemDivider(colors),
          const SizedBox(height: 16),
          _groupTitle(context, '系统与隐私'),
          _navTile(
            context,
            icon: Icons.settings_outlined,
            label: '系统设置',
            onTap: () => Navigator.of(
              context,
            ).push(topDownRoute(const SystemSettingsPage())),
          ),
          _itemDivider(colors),
          _navTile(
            context,
            icon: Icons.security_outlined,
            label: '安全隐私策略',
            onTap: () => Navigator.of(
              context,
            ).push(topDownRoute(const PrivacyPolicyPage())),
          ),
          _itemDivider(colors),
          const SizedBox(height: 16),
          _groupTitle(context, '数据与调试'),
          _navTile(
            context,
            icon: Icons.delete_outline,
            label: '清空数据',
            onTap: _confirmClearData,
          ),
          _itemDivider(colors),
          _toggleTile(
            context,
            icon: Icons.bug_report_outlined,
            label: '调试模式',
            value: _debugMode,
            onChanged: (v) => setState(() => _debugMode = v),
          ),
          _itemDivider(colors),
        ],
      ),
    );
  }

  Widget _groupTitle(BuildContext context, String label) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _navTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: SizedBox(
        height: AppDimens.settingsItemHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: colors.common.trailingIcon),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppDimens.settingsItemFontSize,
                  color: onSurface,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(
                  right: AppDimens.settingsArrowRightMargin,
                ),
                child: Icon(
                  Icons.chevron_right,
                  size: AppDimens.settingsArrowSize,
                  color: colors.common.arrowIcon,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: SizedBox(
        height: AppDimens.settingsItemHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: colors.common.trailingIcon),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppDimens.settingsItemFontSize,
                  color: onSurface,
                ),
              ),
              const Spacer(),
              Switch(
                value: value,
                activeTrackColor: colors.common.switchActive,
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? colors.common.surface
                      : onSurface.withValues(alpha: 0.8);
                }),
                trackColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? colors.common.switchActive
                      : colors.common.divider;
                }),
                trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemDivider(AppColors colors) =>
      Divider(height: 1, thickness: 0.5, color: colors.common.divider);
}
