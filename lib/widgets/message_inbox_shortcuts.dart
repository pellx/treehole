import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_messages_theme.dart';

/// 顶部三个系统消息入口：回复、公告、审核。
class MessageInboxShortcuts extends StatelessWidget {
  final Map<String, dynamic> counts;
  final bool showUnread;
  final void Function(String category, String title)? onOpen;

  const MessageInboxShortcuts({
    super.key,
    required this.counts,
    required this.showUnread,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppMessagesTheme.shortcutHorizontalPadding,
        AppMessagesTheme.shortcutTopPadding,
        AppMessagesTheme.shortcutHorizontalPadding,
        AppMessagesTheme.shortcutBottomPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final category in [
            (
              'reply',
              '回复',
              '帖子回复',
              Icons.chat_bubble_rounded,
              AppMessagesTheme.replyIconColor,
            ),
            (
              'announcement',
              '公告',
              '公告',
              Icons.campaign_rounded,
              AppMessagesTheme.announcementIconColor,
            ),
            (
              'moderation',
              '审核',
              '审核与举报',
              Icons.verified_user_rounded,
              AppMessagesTheme.moderationIconColor,
            ),
          ])
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onOpen == null
                    ? null
                    : () => onOpen!(category.$1, category.$3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppMessagesTheme.shortcutItemVerticalPadding,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Badge(
                        isLabelVisible:
                            showUnread &&
                            (counts[category.$1] as int? ?? 0) > 0,
                        backgroundColor: AppMessagesTheme.unreadColor,
                        textColor: Colors.white,
                        largeSize: AppMessagesTheme.unreadBadgeSize,
                        textStyle: TextStyle(
                          fontSize: AppMessagesTheme.unreadBadgeFontSize,
                          fontFamily: Theme.of(
                            context,
                          ).textTheme.bodySmall?.fontFamily,
                        ),
                        label: Text(
                          (counts[category.$1] as int? ?? 0) > 99
                              ? '99+'
                              : '${counts[category.$1] ?? 0}',
                        ),
                        child: Container(
                          width: AppMessagesTheme.shortcutSize,
                          height: AppMessagesTheme.shortcutSize,
                          decoration: BoxDecoration(
                            color: dark
                                ? AppMessagesTheme.shortcutBackgroundDark
                                : AppMessagesTheme.shortcutBackgroundLight,
                            borderRadius: BorderRadius.circular(
                              AppMessagesTheme.shortcutRadius,
                            ),
                          ),
                          child: Icon(
                            category.$4,
                            size: AppMessagesTheme.shortcutIconSize,
                            color: category.$5,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppMessagesTheme.shortcutLabelGap),
                      Text(
                        category.$2,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppMessagesTheme.shortcutLabelFontSize,
                          color: colors.common.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
