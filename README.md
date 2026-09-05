# treehole_flutter

树洞 Flutter 客户端项目。

## 项目根目录结构

```
.
├── lib/                   # Flutter 应用源码（详见下方）
├── android/               # Android 平台原生代码（Kotlin、Gradle、资源）
├── ios/                   # iOS 平台原生代码（Swift、Xcode 工程、签名配置）
├── web/                   # Web 平台入口（index.html、manifest、favicon）
├── linux/                 # Linux 桌面平台代码
├── macos/                 # macOS 桌面平台代码
├── windows/               # Windows 桌面平台代码
│
├── assets/                # 静态资源（图片、图标、表情素材）
├── server/                # 后端参考代码（captcha 策略、DTO、controller 等）
├── test/                  # 测试文件
├── .github/workflows/     # CI/CD（iOS 构建工作流）
│
├── pubspec.yaml           # Flutter 依赖与版本配置
├── analysis_options.yaml  # Dart 静态分析规则
├── API.md                 # 后端 API 接口文档
├── README.md              # 本文件
├── pon.ps1                # 开启代理脚本
├── poff.ps1               # 关闭代理脚本
└── .gitignore
```

## lib 目录结构

```
lib/
├── main.dart              # 应用入口，初始化 Hive 等基础服务
├── app.dart               # MaterialApp 配置（主题、路由、国际化）
├── app_navigator.dart     # 全局路由 / 导航管理
│
├── config/                # 全局配置常量
│   ├── local.dart         #   本地密钥 / 第三方 SDK 配置（不入库）
│   └── post_limits.dart   #   发帖相关限制（图片数量、附件大小等）
│
├── models/                # 数据模型（Post、Comment、SmsResult 等）
│
├── pages/                 # 页面层，按功能模块划分子目录
│   ├── main_shell.dart    #   底部导航壳页面
│   ├── account/           #   注册、登录、验证码、设备绑定、用户资料
│   ├── square/            #   广场（信息流首页）
│   ├── post/              #   发帖 / 帖子详情
│   ├── search/            #   搜索页
│   ├── messages/          #   消息通知
│   ├── favorites/         #   收藏
│   └── settings/          #   设置（用户、系统、隐私政策、版本等）
│
├── services/              # 业务服务层
│   ├── api.dart           #   HTTP API 客户端
│   ├── session_service.dart #  登录态 / session 管理
│   ├── realtime_service.dart # Socket.IO 实时推送
│   ├── storage.dart       #   Hive 本地存储
│   ├── device_credential_store.dart # 设备凭证安全存储
│   ├── device_fingerprint.dart # 设备指纹采集
│   ├── captcha_service.dart #  验证码（阿里云无痕验证）
│   ├── pow.dart           #   Proof-of-Work 计算
│   ├── avatar_storage.dart #   头像缓存
│   ├── binding_cache.dart  #   设备绑定状态缓存
│   ├── account_display.dart #  账号展示逻辑
│   └── timezone_service.dart # 时区服务
│
├── theme/                 # 主题与样式常量（颜色、尺寸、组件主题）
│
└── widgets/               # 全局可复用组件（PostCard、对话框、加载态等）
```

## lib 根文件详解

### `main.dart` — 启动入口

应用的 `main()` 函数，在 UI 渲染之前完成所有底层服务的初始化：

1. `WidgetsFlutterBinding.ensureInitialized()` — 让 Flutter 引擎就绪（异步操作前必须调用）
2. `Hive.initFlutter()` — 初始化本地数据库 Hive
3. 并行打开三个 Hive 数据箱：帖子缓存 `PostStorage`、设备绑定缓存 `BindingCache`、时区 `TimezoneService`
4. 调用 `runApp(TreeholeApp())` 启动 UI

> 职责：把东西准备好，然后才启动界面。

### `app.dart` — 应用根组件

定义 `TreeholeApp`（StatefulWidget），即整个应用的根 Widget，负责：

1. **配置 MaterialApp** — 标题（"树通"）、语言（中文）、亮/暗主题、页面切换动画
2. **管理主题切换** — 静态方法 `setThemeMode()` 可切换亮色/暗色/跟随系统
3. **监听应用生命周期** — App 从后台回前台时，检查 session 是否仍有效（防止后台期间被其他设备解绑）
4. **设定首页** — `home: MainShell()` 即底部导航栏主页面

> 职责：定义应用长什么样、怎么响应生命周期事件。

### `app_navigator.dart` — 全局导航桥

只有一行有效代码：创建 `appNavigatorKey`（`GlobalKey<NavigatorState>`）。

**为什么需要它？** Flutter 页面跳转通常需要 `BuildContext`，但有些跳转/弹窗是从服务层发起的（比如被踢下线、session 过期），服务层没有 `BuildContext`。通过把这个 key 传给 `MaterialApp`（`app.dart` 中 `navigatorKey: appNavigatorKey`），任何地方的代码都能通过 `appNavigatorKey.currentState` 拿到导航器，实现不依赖页面 context 也能跳转或弹窗。

> 职责：让服务层代码也能控制页面导航。

## models/ 详解

数据模型层，负责定义数据结构和 JSON 序列化/反序列化。类比 NestJS 里的 DTO + Entity。

### `post.dart` — 帖子

核心数据模型，对应后端 Post 实体。

- `Post` — 帖子完整数据（标题、内容、作者、图片、附件、评论 ID 列表）
- `PostImage` — 帖子图片（文件名）
- `PostAttachment` — 帖子附件（文件名 + 原始文件名）
- `displayAuthor` — 匿名时返回空串，用于 UI 展示

### `comment.dart` — 评论/回复

- `Comment` — 一条回复（所属帖子 ID、楼中楼目标 ID、作者、内容）
- 支持匿名，逻辑同 Post

### `post_meta.dart` — 帖子元数据（列表用）

- `PostMeta` — 帖子摘要（不含正文/图片），用于广场列表展示
- `IdListV2Result` — `/posts/idListv2` 接口的分页返回结构

### `post_draft.dart` — 发帖草稿

- `PostDraft` — 发帖页的本地草稿，包含标题、内容、匿名开关、已上传文件列表
- 提供 `toJson()` 用于暂存到 Hive

### `upload_result.dart` — 上传结果

- `UploadResult` — 图片/附件上传到服务端后的返回（类型、原始名、服务端文件名）
- `PostUploadType` — 枚举：`image` / `attachment`

### `sms_result.dart` — 短信接口结果

- `SmsSendResult` — 发送验证码的响应（是否发送、冷却秒数、模式：login/register/recover）
- `SmsLoginResult` — 短信登录的响应（session 凭证）

### `version_info.dart` — 版本信息

- `VersionInfo` — App 版本更新数据（版本号、平台、更新日志、下载地址）
- `currentVersion` — 当前客户端版本号常量

### `device_fingerprint.dart` — 设备指纹

采集设备硬件信息，用于设备绑定和安全校验。按平台分为：

- `AndroidFingerprint` — Android 设备信息（Build、Version、ABI、Hardware 四组）
- `IosFingerprint` — iOS 设备信息（Device、Storage、Utsname 三组）
- `DeviceFingerprint` — 顶层封装，通过工厂构造区分 Android / iOS / unknown
