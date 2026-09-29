# 消息列表排版与摘要部署（2026-09-29）

## 更新内容

App 消息页按参考图调整为顶部三个横向入口（帖子回复、公告、审核与举报），下方会话列表显示圆形头像、公开昵称、最近消息摘要、时间与未读标记。保留置顶、免打扰、清理未读、拓展菜单和左侧通知铃铛。铃铛配色保留用户手动设置，新增布局参数集中在 lib/theme/app_messages_theme.dart。

后端列表和 conversations/state 响应新增 last_message，包含最近已保存消息的前 120 个字符及 created_at；摘要参与 sync_hash，因此旧缓存会在状态同步时更新。按会话快照的 last_seq 查询现有 dm_messages，沿用原有参与者访问条件。空会话返回 null，不读取历史消息列表。

## 由你执行的部署

无需新表、字段、SQL 迁移或新依赖。助手不重启服务。

在 /var/www/treehole-nest 的 master 分支按现有方式构建并重启，使新增响应字段生效：

~~~bash
cd /var/www/treehole-nest
sudo -H -u www-data npm run build
sudo -H -u www-data env PM2_HOME=/var/www/.pm2 pm2 restart treehole-nest
~~~

安装新版 App。旧后端尚未重启时，App 仍能使用旧会话响应，摘要位置暂时显示已有消息条数；空会话显示“暂无消息”。

## 验收

- 三个系统入口保持原有分类打开行为。
- 会话行显示当前头像、公开昵称、最新已审核消息及时间；长昵称和摘要单行截断。
- 免打扰会话只显示未读红点，无数字；普通未读显示数量，超过 99 显示 99+。
- 置顶仍排在前方，保留浅色底和图钉；不改变已有缓存、通知权限提醒和发送审核逻辑。
