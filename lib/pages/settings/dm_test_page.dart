import 'package:flutter/material.dart';

import '../../services/app_tab_request.dart';
import '../../services/dm_mock_data.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_toast.dart';
import '../messages/dm_mock_chat_page.dart';

/// 消息模块测试控制台（设置 → 数据与调试 → 消息模块测试）。
///
/// 打开后会用一组内存假数据填充消息页，覆盖私信的 10 种状态；
/// 这里的按钮可以模拟「对方发消息 / 发送请求 / 接受 / 拒绝 / 发送失败」等事件，
/// 用来检查前端在各种状态下的显示与交互，完全不碰真实账号和后端。
class DmTestPage extends StatefulWidget {
  const DmTestPage({super.key});

  @override
  State<DmTestPage> createState() => _DmTestPageState();
}

class _DmTestPageState extends State<DmTestPage> {
  DmMockData get _store => DmMockData.instance;

  void _openMessages() {
    AppTabRequest.go(2);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _toast(String message) {
    showAppToast(context, message: message);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        return AppScaffold(
          title: '消息模块测试',
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _hint(colors),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用测试数据'),
                subtitle: Text(
                  _store.enabled ? '消息页当前显示的是假数据' : '关闭后消息页恢复真实会话',
                ),
                value: _store.enabled,
                onChanged: (value) {
                  if (value) {
                    _store.enable();
                    _toast('已启用测试数据，去消息页看看');
                  } else {
                    _store.disable();
                    _toast('已关闭测试数据');
                  }
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        if (!_store.enabled) _store.enable();
                        _openMessages();
                      },
                      icon: const Icon(Icons.forum_outlined),
                      label: Text(_store.enabled ? '去消息页查看' : '启用并去消息页'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      _store.reset();
                      _toast('已恢复初始测试数据');
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('重置'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _section('模拟事件', colors, [
                _action(
                  icon: Icons.mark_chat_unread_outlined,
                  title: '对方发来一条新消息',
                  subtitle: '给「阿哲」追加未读消息，会话行角标 +1',
                  onTap: () {
                    _store.incomingMessage();
                    _toast('已模拟：阿哲发来新消息');
                  },
                ),
                _action(
                  icon: Icons.person_add_alt,
                  title: '陌生人来请求私信',
                  subtitle: '新增一条 0 消息、待接受的请求会话',
                  onTap: () {
                    _store.spawnStrangerRequest();
                    _toast('已模拟：新的陌生人请求');
                  },
                ),
                _action(
                  icon: Icons.check_circle_outline,
                  title: '对方接受了我的请求',
                  subtitle: '把「沈七」从等待接受变成可以聊天',
                  onTap: () {
                    _store.peerAccepts(110);
                    _toast('已模拟：沈七接受了请求');
                  },
                ),
                _action(
                  icon: Icons.block_outlined,
                  title: '对方拒绝了我的请求',
                  subtitle: '把「沈七」变成已拒绝，观察 24 小时冷却文案',
                  onTap: () {
                    _store.peerRejects(110);
                    _toast('已模拟：沈七拒绝了请求');
                  },
                ),
                _action(
                  icon: Icons.error_outline,
                  title: '下一条消息发送失败',
                  subtitle: '打开后发一条消息，会出现红色感叹号，点它可重试',
                  trailing: _store.failNextSend ? '已开启' : null,
                  onTap: () {
                    _store.setFailNextSend(true);
                    _toast('已开启：下一条发送会失败');
                  },
                ),
                _action(
                  icon: Icons.done_all,
                  title: '全部标记为已读',
                  subtitle: '清掉所有未读角标与红点',
                  onTap: () {
                    _store.markAllRead();
                    _toast('已清空全部未读');
                  },
                ),
              ]),
              const SizedBox(height: 20),
              _section('场景清单', colors, [
                for (final scenario in _scenarios) _scenarioTile(scenario),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _hint(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '这是一组纯内存的假数据，不会发请求、不会污染真实会话，'
        '退出 App 后自动消失。用来检查前端在 10 种私信状态下的显示与交互。',
        style: TextStyle(color: colors.onSurface, height: 1.5),
      ),
    );
  }

  Widget _section(String title, ColorScheme colors, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _action({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? trailing,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: colors.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing == null
          ? const Icon(Icons.chevron_right)
          : Text(trailing, style: TextStyle(color: colors.primary)),
      onTap: onTap,
    );
  }

  Widget _scenarioTile(_Scenario scenario) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: colors.surface,
        child: Text(
          scenario.name.substring(0, 1),
          style: TextStyle(color: colors.primary),
        ),
      ),
      title: Text('${scenario.name} · ${scenario.title}'),
      subtitle: Text(scenario.detail),
      onTap: () {
        if (!_store.enabled) {
          _store.enable();
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DmMockChatPage(conversationId: scenario.id),
          ),
        );
      },
    );
  }
}

class _Scenario {
  final int id;
  final String name;
  final String title;
  final String detail;
  const _Scenario(this.id, this.name, this.title, this.detail);
}

const List<_Scenario> _scenarios = [
  _Scenario(101, '林夕', '待接受（对方发起）', '会话行有「请求」标签与同意/拒绝按钮'),
  _Scenario(102, '阿 ken', '陌生请求，0 条消息', '点进去只有提示条，没有输入框'),
  _Scenario(103, '苏晚', '已接受但没聊过', '空会话文案「还没有消息，打个招呼吧」'),
  _Scenario(104, '阿哲', '有历史，部分未读', '12 条历史、3 条未读，刚来的新消息'),
  _Scenario(105, '豆豆', '置顶 + 免打扰 + 未读', '置顶底色、免打扰图标、红点角标'),
  _Scenario(106, '橘子…', '超长昵称 + 99+ 未读', '昵称与摘要省略号、99+ 角标'),
  _Scenario(107, '老白', '长文本压力', '2000 字、换行、表情、连续多发'),
  _Scenario(108, '陈默', '我发起被拒绝', '「对方已拒绝你的私信请求」'),
  _Scenario(109, '木木', '我拒绝了对方', '「你已拒绝该私信请求」'),
  _Scenario(110, '沈七', '我发起等待接受', '等待提示，可用上方按钮模拟对方接受/拒绝'),
];
