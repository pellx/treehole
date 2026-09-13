-- 在目标数据库中手动执行，单操作者；不要同时发布多个版本。
-- 先持久备份原行。临时备份仅在当前 MySQL 连接中存在，断开后需用持久备份回滚。
SET NAMES utf8mb4;
CREATE TEMPORARY TABLE IF NOT EXISTS release_112_backup LIKE versions;
CREATE TEMPORARY TABLE IF NOT EXISTS release_112_capture (id INT PRIMARY KEY);
START TRANSACTION;
INSERT INTO release_112_backup SELECT * FROM versions WHERE version_number='1.1.2' AND platform='android' AND NOT EXISTS (SELECT 1 FROM release_112_capture);
INSERT IGNORE INTO release_112_capture VALUES (1);
SET @release_title='注册可靠性与广场性能优化';
SET @release_log='新增：注册请求幂等与结果恢复
优化：注册完成自动返回并刷新账号状态、广场增量刷新与加载性能、昵称审核一致性
修复：弱网响应丢失导致注册状态不确定、网络卡顿时帖子重复显示、Android 更新包兜底链接';
SET @release_description='1.1.2：
一，注册与账号：
1. 注册提交支持请求幂等，弱网重试不会重复创建账号
2. 注册响应丢失后可查询并恢复原结果
3. 注册成功自动返回唤起注册的页面，并立即刷新为已注册状态
4. 修复注册中断后重新进入时状态无法正确恢复
5. 注册与改名统一执行昵称内容审核
二，广场与性能：
1. 信息流改用 idListv2，减少逐帖重复请求
2. 修复网络卡顿或并发加载时帖子重复显示
3. 刷新仅拉取真正的新帖，避免重复刷新已有内容
三，更新与兼容：
1. 增强 iOS 注册设备信息写入容错
2. 修复 Android 当前版本识别、ABI 选择和通用包回退';
SET @release_url='https://www.leisure.xin:33433/flutter_app_version/v1.1.2/';
UPDATE versions SET title=@release_title, log=@release_log, description=@release_description, download_url=@release_url WHERE version_number='1.1.2' AND platform='android';
INSERT INTO versions (version_number,platform,title,log,description,download_url,release_date)
SELECT '1.1.2','android',@release_title,@release_log,@release_description,@release_url,NOW()
WHERE NOT EXISTS (SELECT 1 FROM versions WHERE version_number='1.1.2' AND platform='android');
SELECT * FROM versions WHERE version_number='1.1.2' AND platform='android';
SELECT id,version_number FROM versions WHERE platform='android' ORDER BY id DESC LIMIT 1;
-- 确认只有一条 1.1.2 且 latest 为 1.1.2 后，手动执行 COMMIT;
-- 否则手动执行 ROLLBACK; 此文件不自动提交。
