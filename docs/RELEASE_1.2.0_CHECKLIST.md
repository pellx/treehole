# 1.2.0 发布检查单

最后更新：2026-10-20。范围：本客户端仓库 `main` 分支与 1.2.0 发版所需的服务端/运维动作。

## 一，仓库侧已完成

| 项目 | 状态 | 位置 / 提交 |
| --- | --- | --- |
| 版本号升级到 `1.2.0+5` | 完成 | `pubspec.yaml`、`lib/models/version_info.dart`（`4cda76d`） |
| 1.2.0 更新日志 | 完成 | `CHANGELOG.md`（`3734173`） |
| versions 表 SQL | 已生成，待人工执行 | `releases/1.2.0/apply.sql`、`rollback.sql`（`2f4a137`） |
| 9 条数据库迁移与执行顺序 | 完成 | `deploy/MIGRATIONS_1.2.0.md`（`55b7d88`） |
| 新接口文档 | 完成，含 6 处「待确认」 | `API.md`（`26bb29a`、`ab31f5a`、`b8521a6`） |
| 断线不清空未读角标 | 完成 | `58a5e31`、`deff2ba` |
| 消息缓存异常自恢复 | 完成 | `99119a3` |
| 作者菜单文案改为「私信」 | 完成 | `bf1b019` |
| 静态检查 | 通过 | `dart analyze lib test`：0 error / 0 warning / 0 info |
| 自动化测试 | 通过 | `flutter test`：77 个用例全部通过 |
| 离线发版预检 | 通过 | `preflight.ps1 -Version 1.2.0 -Offline` 返回 0 |
| 工作区状态 | 干净，`main` 与 `origin/main` 一致 | — |

## 二，发版前必须人工完成（按顺序）

1. **先部署后端**：本版本客户端调用的私信、系统消息、举报、头像、发帖 v2 接口都依赖后端新代码与迁移。
2. **执行 9 条迁移**：按 `deploy/MIGRATIONS_1.2.0.md` 的顺序逐条执行并校验；DDL 不可回滚，先做持久备份。
3. **补数据库授权**：迁移不自动授权，用有 GRANT 权限的账号执行 `releases/1.2.0/grants.sql`，再用 `SHOW GRANTS FOR 'submit-post'@'localhost';` 复核；漏授权会报 `command denied`。（2026-10-20 已核对生产库：9 张新表齐备且授权完整，本次无需执行）
4. **补后端环境变量**：`MODERATION_ENABLED=true`、`ALIBABA_CLOUD_ACCESS_KEY_ID` / `ALIBABA_CLOUD_ACCESS_KEY_SECRET`、`IMG_BASE_URL`；生产环境不要设置 `TEST_MODEL=true`。
5. **准备目录与依赖**：`/var/www/img/user-icon`、`/var/www/img/pre-upload/avatar-review` 可写；安装 libvips；反向代理放开 5MB 请求体与 90 秒超时。
6. **重启后端**：`npm run build` 后 `pm2 restart treehole-nest`。
7. **打包并上传 APK**：四个 ABI 包按 `build*10000 + ABI 偏移` 生成 versionCode（本版本 50000 / 51000 / 52000 / 53000），上传到 `/var/www/img/flutter_app_version/v1.2.0/`。
8. **写 versions 表**：在 MySQL 中执行 `releases/1.2.0/apply.sql`，确认 `versions` 里 1.2.0 只有一条且为最新后再 `COMMIT`。
9. **打 tag**：`v1.2.0` 并在验证后推送，保留 `v1.2.0-android` 的既有约定。
10. **iOS 上传**：`gh workflow run ios.yml --ref main -f version=1.2.0`，确认 TestFlight 外部测试组可见。
11. **确认构建号**：App Store Connect 中 build 5 未被占用。

## 三，发版前必须验证

- 真机双账号：私信收发、已读游标、置顶 / 免打扰 / 拉黑、前台本地通知、系统消息与公告、举报 3 人后隐藏、头像裁剪后上传与审核结果展示。
- 弱网与断线：断线重连后未读角标不被清零；消息失败可重试且不重复。
- 升级路径：覆盖安装 1.1.2 → 1.2.0，确认证书与签名一致、可正常升级。
- 兼容窗口：1.1.2 客户端上传图片不携带 session，新后端 `SessionGuard` 会返回 401；后端先上线会短暂影响旧客户端上传，建议把客户端发布贴近后端上线，或接受该窗口。

## 四，已知风险

- Android release 构建仍指向 debug 签名（`android/app/build.gradle.kts:36`），更新包必须与历史安装的证书一致；打包机 keystore 不在本仓库内。
- 内容隐藏不可逆，且没有申诉与人工恢复入口。
- 启动时若本地存在隐藏内容，会触发一次全量扫描与缓存清理（`lib/services/storage.dart`）。
- `API.md` 仍有 6 处标注「待确认」的字段或状态码，联调时以后端实际响应为准。
