import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// 底部操作项
class AppSheetAction {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const AppSheetAction({
    this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

/// 统一底部操作菜单
Future<void> showAppActionsSheet({
  required BuildContext context,
  required List<AppSheetAction> actions,
}) async {
  final colors = Theme.of(context).extension<AppColors>()!;
  final onSurface = Theme.of(context).colorScheme.onSurface;

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: false,
    builder: (ctx) => SafeArea(
      top: false,
      bottom: false,
      left: true,
      right: true,
      // 卡片贴合屏幕左右边缘，只保留顶部圆角；底部填充 5px 白色间距
      // 点击上方非卡片区域（遮罩）或左右滑动卡片均可退出
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity!.abs() > 120) {
            Navigator.of(ctx).pop();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: colors.common.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          padding: const EdgeInsets.only(bottom: 5),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(actions.length, (i) {
                  final action = actions[i];
                  return Column(
                    children: [
                      ListTile(
                        leading: action.icon != null
                            ? Icon(
                                action.icon,
                                color: action.destructive
                                    ? Colors.red
                                    : onSurface,
                                size: 22,
                              )
                            : null,
                        title: Text(
                          action.label,
                          textAlign: action.icon == null
                              ? TextAlign.center
                              : TextAlign.start,
                          style: TextStyle(
                            fontSize: 16,
                            color: action.destructive ? Colors.red : onSurface,
                          ),
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(ctx).pop();
                          action.onTap();
                        },
                      ),
                      if (i < actions.length - 1)
                        Divider(
                          height: 1,
                          indent: action.icon == null ? 0 : 56,
                          color: colors.common.divider,
                        ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 底部单选选择器
Future<T?> showAppSelectorSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T) labelBuilder,
  required T? selected,
}) async {
  final colors = Theme.of(context).extension<AppColors>()!;
  final onSurface = Theme.of(context).colorScheme.onSurface;

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            color: colors.common.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.common.trailingIcon,
                  ),
                ),
              ),
              Divider(height: 1, color: colors.common.divider),
              ...List.generate(options.length, (i) {
                final option = options[i];
                final isSelected = option == selected;
                return Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected
                            ? colors.common.green
                            : colors.common.trailingIcon,
                        size: 20,
                      ),
                      title: Text(
                        labelBuilder(option),
                        style: TextStyle(fontSize: 16, color: onSurface),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(ctx).pop(option);
                      },
                    ),
                    if (i < options.length - 1)
                      Divider(
                        height: 1,
                        indent: 56,
                        color: colors.common.divider,
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    ),
  );
}
