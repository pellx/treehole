---
name: treehole-release
description: Release an explicitly supplied Treehole Flutter version to Android downloads and external TestFlight, sync Flutter and Nest repositories, and prepare manual versions SQL.
---

# 树通发布

调用示例：`$treehole-release 1.1.2`。必须由用户显式提供营销版本；缺少时询问，不能猜测。读取 `references/release-checklist.md` 后执行。

版本与构建号分开处理：首次 1.1.2 使用 +4；以后检查线上 APK、pubspec 与 App Store Connect 已上传构建号，选择更大的构建号，重复上传也不能撞号。目标已存在时停止覆盖，核对来源提交和 SHA-256。

运行 `scripts/preflight.ps1 -Version <version>`，解决报告的阻塞后，分析、测试、提交和推送。使用 `scripts/package_android.ps1 -Version <version> -ExpectedBuild <build>` 构建；先使用 `-DryRun` 查看命令和目标。脚本不上传、不触发 Action、不运行 SQL。

推送、APK 上传、网站修改、TestFlight Review 前展示具体仓库/提交/URL/构建并确认授权；用户已明确授权实施整个发布计划时无需重复询问。凭据、私钥、本地配置、备份及 APK 不进入仓库。需要账号登录或真机验收时明确说明并继续不依赖它们的工作。

从 CHANGELOG 与已发布基线生成用户可读版本说明，遵循 `references/version-sql-template.sql`。SQL 仅交给用户执行。未经实测不能声称注册 500 已修复或真机升级成功。

Apple 处理/审核未完成不等于失败；记录 build ID、组、审核状态。需要跨回合等待时使用产品的提醒/监控机制，状态变化时通知，禁止声称已经通过审核。

完成后报告 Git SHA、APK 校验和与 URL、Action URL、TestFlight 状态、SQL 路径以及仍未完成的验收。
