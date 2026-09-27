# 消息页顶栏与一键清理未读

## 界面

消息页顶栏只显示“消息”、一键清理未读和拓展按钮；不显示返回按钮。拓展按钮使用已有回复操作底部附加栏，提供发起私信、刷新消息、通知权限。首次进入、从私信/系统消息返回及手动刷新都不显示“正在获取消息”的底部加载提示；请求失败仍保留错误提示。

## 接口

POST /node/messages/dm/read-all，沿用 SessionGuard 请求头。后端在一个事务中：

1. 将该账号所有私信会话的 last_read_seq 推进到各会话当前最后序号，保持免打扰、拉黑、置顶字段不变。
2. 为该账号可见且尚未读的系统消息插入已读标记，包含公告、审核与举报、帖子回复。已读标记使用 INSERT IGNORE 防止重复。
3. 提交后通知本账号其他在线设备刷新未读状态。事务读取之后新产生的消息仍为未读。

不新增数据库表或字段。运行账号须保留既有 user_message_preferences 和 system_message_reads 的读写权限。消息列表会在成功后刷新并显示更新；失败时不在前端提前清除未读。

## 服务器操作：由你执行

助手只同步后端源码并运行 npm run build / 相关测试，不执行 SQL、不重启服务。此次没有迁移。确认已有消息表及授权后，按现有操作方式重启后端：

    cd /var/www/treehole-nest
    npm run build
    sudo -H -u www-data env PM2_HOME=/var/www/.pm2 pm2 restart treehole-nest

新版 App 也需重新构建安装，才能看到整理后的顶栏和一键清理按钮。源码备份：/home/pell/messages-header-before-20260928.tar.gz。
