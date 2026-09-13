# 项目发布约定

- Flutter root 是当前 Git 仓库：`pellx/treehole`，分支 main；标签 v<version>。
- SSH：`ssh -p 400 pell@www.leisure.xin`。后端 `/var/www/treehole-nest`，仓库 `pellx/treehole_backend_nestjs`，分支 master。只提交源码及审核过的维护脚本，不运行数据库脚本，不重启服务。
- 网站 `/var/www/treehole` 没有 remote；修改 download/download.html 和 js/download-detect.js，保留已有变更，先做这两个文件的本地基线提交，再做发布提交。回滚只恢复该发布差异。
- APK 根目录 `/var/www/img/flutter_app_version`，公网 `https://www.leisure.xin:33433/flutter_app_version/`。
- v<version>/treehole-v<version>-<arm64-v8a|armeabi-v7a|x86_64|all>.apk。禁止 `.apk.apk`，每个链接必须有文件。未知网页架构应保留选择页或通用包，不把 WebAssembly 支持当作 arm64 证据。
- 应用 ID com.example.treehole，iOS bundle com.pellx.treehole。Android 沿用证书 SHA256 `01360b21890ca7191fabf6ab6ddf74e122568b4d7d5ab07287011baf4027da95`；未授权迁移时禁止换包名或签名。
- pubspec 与 VersionInfo.currentVersion 必须一致。Android versionCode=pubspec build*10000+ABI偏移（通用0、armeabi1000、arm642000、x86_643000）；1.1.2+4 为40000/41000/42000/43000。build必须全局递增，以便新版通用包也能覆盖旧分架构包。iOS build仍为4；上传前检查版本/构建号未被使用。
- 使用 gh 登录并检查 repo、secrets 名称、workflow；不得输出 secret 或带凭据 remote。后端旧泄露 PAT 撤销后改为专用可写 Deploy Key，未撤销前不得使用其推送。
- Flutter analyze/test 和后端 tsc 必须通过。无后端测试时明确记录缺少测试，不能冒称通过覆盖。
- 真机检查：1.1.1 覆盖安装保留账户；注册最后一步返回原页面并刷新账号；断网恢复只产生一个账号。没有设备时报告未验收，不自行跳过上线门槛。
- 从干净提交构建三 ABI 与通用包。上传临时兄弟目录并校验 SHA256 后 rename 为 v<version>，已存在目标禁止覆盖。保留旧 APK。
- 确认公网四链接 200、大小和校验和正确后切网页链接，通用包体积按实际产物更新。
- versions 表：id 自增，version_number varchar(20)，platform varchar(20)，title varchar(200)，log/description text，download_url varchar(500)，release_date datetime。latest 按 id DESC，不按版本大小；不要靠 UPDATE 旧 id 宣称 latest 已切换。
- 仅生成 android SQL，下载字段为版本目录。执行前由用户持久保存旧行；重复行必须先人工处理。事务只能防止部分执行，未设唯一索引时不能保证并发幂等，因此仅单操作者执行。
- iOS：gh workflow run ios.yml --ref main -f version=<version>；确认 run.headSha 匹配发布提交，再 watch。重复执行前查询上传状态，不能盲目重传同构建。
- 上传成功只是 Apple 接收。等待处理，核对 版本(build)，加入 bJJ2GvUR 链接对应的既有外部组、填写 What to Test、开启自动通知并提交 Beta App Review。不提交正式商店审核。
- 签名描述文件名不是到期日。实际解析 profile 和证书。Action 校验 Xcode>=26；每次发布再确认 Apple 当期要求。
- 回滚：恢复网站发布提交差异；按保存的行恢复 SQL。移除 TestFlight 新构建需显式授权。恢复旧下载入口不等于已安装用户可降级，不能保证 1.1.2 数据能被 1.1.1 读取。
