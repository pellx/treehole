import 'package:flutter/material.dart';
import '../services/timezone_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dm_theme.dart';
import '../theme/app_messages_theme.dart';
import 'user_avatar.dart';

/// 会话行：头像、昵称、最近消息，右侧时间和未读标记。
/// 未接受的私信请求显示「请求」标记与同意/拒绝按钮。
///
/// 所有尺寸都在 [AppDmTheme] 中调整，这里只负责取值与布局。
class DmConversationTile extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback? onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final bool isFirst;

  const DmConversationTile({
    super.key,
    required this.conversation,
    this.onTap,
    this.onAccept,
    this.onReject,
    this.isFirst = false,
  });

  String _time(String? raw) {
    final date = TimezoneService.parseServerDateTime(raw);
    if (date == null) return '';
    final now = DateTime.now().toUtc();
    final elapsed = now.difference(date);
    if (elapsed.isNegative || elapsed.inMinutes < 1) return '刚刚';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}分钟前';
    if (elapsed.inDays < 1) return '${elapsed.inHours}小时前';
    if (elapsed.inDays < 7) return '${elapsed.inDays}天前';
    final local = TimezoneService.convert(date);
    final current = TimezoneService.convert(now);
    return local.year == current.year
        ? '${local.month}月${local.day}日'
        : '${local.year}/${local.month}/${local.day}';
  }

  Widget _requestButton(
    BuildContext context,
    String label,
    VoidCallback? onPressed,
    bool primary,
  ) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, AppDmTheme.requestButtonMinHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDmTheme.requestButtonHorizontalPadding,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: primary
            ? Theme.of(context).colorScheme.primary
            : AppMessagesTheme.secondaryLight,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: AppDmTheme.requestButtonFontSize),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final dark = theme.brightness == Brightness.dark;
    final secondary = dark
        ? AppMessagesTheme.secondaryDark
        : AppMessagesTheme.secondaryLight;
    final peer = conversation['peer'] as Map?;
    final displayName = (peer?['user_display_id'] as String?)?.trim();
    final name = displayName == null || displayName.isEmpty
        ? '用户 #${conversation['peer_user_id']}'
        : displayName;
    final lastMessage = conversation['last_message'] as Map?;
    final content = (lastMessage?['content'] as String?)
        ?.replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final status = conversation['status'] as String? ?? 'accepted';
    final pending = status == 'pending';
    final rejected = status == 'rejected';
    final requester = conversation['is_requester'] == true;
    final stateText = pending
        ? (requester ? '已发送私信请求，等待对方接受' : '请求与你私信')
        : rejected
        ? (requester ? '对方已拒绝你的私信请求' : '你已拒绝该私信请求')
        : null;
    final preview = stateText ?? content ?? '';
    final time = lastMessage == null
        ? '无历史消息'
        : _time(lastMessage['created_at'] as String?);
    final count = conversation['unread_count'] as int? ?? 0;
    final muted = conversation['muted'] == true;
    final pinned = conversation['pinned'] == true;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: pinned
              ? theme.colorScheme.primary.withValues(
                  alpha: AppDmTheme.pinnedBackgroundAlpha,
                )
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: isFirst ? 0 : AppDmTheme.conversationMinHeight,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppDmTheme.conversationHorizontalPadding,
                  isFirst ? 0 : AppDmTheme.conversationVerticalPadding,
                  AppDmTheme.conversationHorizontalPadding,
                  AppDmTheme.conversationVerticalPadding,
                ),
                child: Row(
                  crossAxisAlignment: isFirst
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    UserAvatar(
                      url: peer?['avatar_url'] as String?,
                      radius: AppDmTheme.avatarSize / 2,
                      backgroundColor: theme.colorScheme.surface,
                    ),
                    const SizedBox(width: AppDmTheme.avatarGap),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (pinned) ...[
                                Icon(
                                  Icons.push_pin,
                                  size: AppDmTheme.pinIconSize,
                                  color: secondary,
                                ),
                                const SizedBox(width: AppDmTheme.pinIconGap),
                              ],
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppDmTheme.titleFontSize,
                                    fontWeight: FontWeight.w500,
                                    color: colors.common.onSurface,
                                  ),
                                ),
                              ),
                              if (pending) ...[
                                const SizedBox(
                                  width: AppDmTheme.requestTagGap,
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal:
                                        AppDmTheme.requestTagHorizontalPadding,
                                    vertical:
                                        AppDmTheme.requestTagVerticalPadding,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: AppDmTheme.requestTagBackgroundAlpha,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppDmTheme.requestTagRadius,
                                    ),
                                  ),
                                  child: Text(
                                    '请求',
                                    style: TextStyle(
                                      fontSize: AppDmTheme.requestTagFontSize,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                              if (time.isNotEmpty) ...[
                                const SizedBox(width: AppDmTheme.timeGap),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: AppDmTheme.timeMaxWidth,
                                  ),
                                  child: Text(
                                    time,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: AppDmTheme.timeFontSize,
                                      color: secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: AppDmTheme.textGap),
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: AppDmTheme.previewMaxWidth,
                                    ),
                                    child: Text(
                                      preview,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: AppDmTheme.previewFontSize,
                                        color: secondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (pending && !requester && onAccept != null) ...[
                                const SizedBox(
                                  width: AppDmTheme.requestButtonGap,
                                ),
                                _requestButton(context, '拒绝', onReject, false),
                                _requestButton(context, '同意', onAccept, true),
                              ],
                              if (muted) ...[
                                const SizedBox(width: AppDmTheme.muteIconGap),
                                Icon(
                                  Icons.notifications_off_outlined,
                                  size: AppDmTheme.muteIconSize,
                                  color: secondary,
                                ),
                              ],
                              if (count > 0) ...[
                                const SizedBox(width: AppDmTheme.unreadGap),
                                Semantics(
                                  label: muted ? '免打扰，有未读消息' : '$count 条未读消息',
                                  child: Badge(
                                    smallSize: AppDmTheme.unreadDotSize,
                                    largeSize: AppDmTheme.unreadBadgeSize,
                                    backgroundColor:
                                        AppMessagesTheme.unreadColor,
                                    textColor: Colors.white,
                                    textStyle: TextStyle(
                                      fontFamily:
                                          theme.textTheme.bodySmall?.fontFamily,
                                      fontSize: AppDmTheme.unreadBadgeFontSize,
                                    ),
                                    label: muted
                                        ? null
                                        : Text(count > 99 ? '99+' : '$count'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: AppMessagesTheme.conversationDividerIndent,
          ),
          child: Divider(
            height: AppDmTheme.dividerHeight,
            thickness: AppDmTheme.dividerThickness,
            color: dark
                ? AppMessagesTheme.dividerDark
                : AppMessagesTheme.dividerLight,
          ),
        ),
      ],
    );
  }
}
