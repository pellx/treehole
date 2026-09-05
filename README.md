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
│   ├── api_results.dart   #   API 操作结果 DTO（注册、登录、session 等）
│   └── bound_device.dart  #   设备/账户绑定数据
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

### `api_results.dart` — API 操作结果

认证、用户、绑定等 API 调用的返回类型，从 `api.dart` 拆出：

- `RegisterResult` — 注册返回（user_token + device_secret）
- `SessionCreateResult` — session 创建返回（session_id + session_secret）
- `LoginResult` — 登录返回（轮换后的 device_secret）
- `BindingCreateResult` — 建绑返回（binding_id + device_id）
- `LastSwitchResult` — 切号锁状态（含 `isLocked` 判断）
- `SessionValidateResult` — session 校验结果
- `UserProfileResult` — 用户资料（display_id、改名/重置时间）
- `RenameResult` / `TokenResetResult` — 改名 / 重置令牌返回
- `PrimaryTransferResult` — 主设备迁移返回
- `BindingTransferResult` / `BindingUnbindResult` — 跨设备转移 / 解绑返回

### `bound_device.dart` — 绑定数据

- `BoundDeviceInfo` — 单条设备绑定（状态、指纹、主设备标记、解绑时间）
- `BoundDevicesResult` — 设备列表完整响应（含主设备迁移状态）
- `BoundAccountInfo` — 单条账户绑定（令牌、展示名、注册时间；含 `toCacheJson()` 遮罩）

## services/ 详解

业务服务层，负责网络请求、本地存储、实时通信、安全凭证等底层能力。类比 NestJS 里的 Service + Guard + Interceptor 的组合。

### `api.dart` — HTTP API 客户端

所有后端接口的调用入口，只保留 `ApiService` 方法 + `ThumbnailData` 传输类。DTO 数据类已拆到 `models/api_results.dart`、`models/bound_device.dart`。

**核心设计：**
- 共享一个 `http.Client` 实例（连接复用）
- 统一错误处理：`lastError` 静态变量保存最近一次错误信息
- `_parseErrorMessage()` — 兼容后端返回 `string` 或 `string[]`（NestJS ValidationPipe 两种格式）

**主要方法分类：**
- **帖子/评论** — `getPost`、`createPost`（v2 session 接口）、`createComment`（v2）、`getComment`、`downloadThumbnail`（含原始图片头解析 PNG/JPEG/GIF/WebP）
- **上传** — `uploadFile`，返回 `UploadResult`（`original` 本地名 + `filename` 服务端名）
- **账户** — `registerV2`、`login`、`smsSend`、`smsRegister`、`smsLogin`
- **Session** — `createSession`、`validateSession`、`logoutSession`、`getLastSwitch`
- **设备绑定** — `listBoundDevices`、`listBoundAccounts`、`requestPrimaryTransfer`、`requestBindingTransfer`、`renameBinding`、`deleteBinding`、`cancelDeleteBinding`
- **用户** — `getUserProfile`、`rename`、`resetUserToken`
- **安全** — `getPoWChallenge`、`verifyCaptcha`、`check`
- **版本** — `getLatestVersion`、`getAllVersions`

> 职责：一个文件包含所有后端 HTTP 通信。

### `session_service.dart` — Session 生命周期管理

单例 `SessionService.instance`，管理 session 的创建、验证、失效、切换全流程。相当于 NestJS 的 AuthGuard + PassportStrategy 的客户端版本。

**核心流程 `ensureSession()`：**
1. 验证当前 session（5 分钟缓存避免重复请求）
2. 检查绑定状态（`active` / `unbind_pending` 都算有效）
3. 无效则创建新 session
4. 创建失败则 failover 到其他账户

**WebSocket 事件处理：**
- `handleBindingUnboundFromWs()` — 被其他设备踢下线
- `handleSessionInvalidatedFromWs()` — session 被顶掉

**关键方法：**
- `logout()` — 断开 WS → 服务端注销 → 清除本地凭证
- `switchToAccount()` — 切号：尝试 createSession → bindWithExistingSecret → loginWithToken
- `computeFingerprintHash()` — SHA-256 硬件指纹（与后端 FingerprintService v2 一致）

> 职责：保证任何时候都有一个有效的 session，处理被踢/过期/切换。

### `storage.dart` — Hive 本地存储

`PostStorage` 类，管理 9 个 Hive Box，是应用的主要本地数据持久化层。类比 NestJS 里用 TypeORM 操作数据库，这里用 Hive 操作本地键值存储。

**9 个 Box：**
| Box 名 | 用途 |
|---------|------|
| `id_list` | 帖子 ID 列表（广场信息流） |
| `posts` | 帖子完整数据缓存 |
| `thumbnails` | 缩略图缓存（含宽高） |
| `comments` | 评论缓存（5 分钟刷新 TTL） |
| `custom_colors` | 自定义颜色 |
| `versions` | 版本历史 |
| `account` | 账户 UI 状态（昵称、注册标记、主题模式） |
| `search_history` | 搜索历史（最多 20 条） |
| `post_draft` | 发帖草稿 |

**其他功能：** 评论草稿、PNG 缩略图文件缓存（临时目录）、已获取标记（避免重复拉取）

> 职责：帖子、评论、缩略图、用户偏好等所有本地持久化。

### `realtime_service.dart` — Socket.IO 实时推送

通过 Socket.IO 连接后端 `/node/socket.io`，接收服务端主动推送的事件。类比 NestJS 的 WebSocket Gateway 的客户端侧。

**连接配置：**
- 认证：session id + secret
- 自动重连：最多 20 次，延迟 1s~10s 递增

**监听事件：**
- `binding.unbound` — 设备被解绑（含操作者信息、原因）
- `session.invalidated` — session 失效
- `test.tick` — 测试用心跳

**UI 联动：** 通过 `ValueNotifier` 暴露 `connectionLabel`、`lastTestTickLabel`、`testRunning`，页面可直接监听。

> 职责：实时接收被踢、session 过期等推送，驱动 UI 响应。

### `device_credential_store.dart` — 设备凭证安全存储

`FlutterSecureStorage` 封装，把敏感凭证存在系统级安全存储（Android Keystore / iOS Keychain），而非普通文件。类比 NestJS 里用加密环境变量存密钥。

**存储的凭证：**
- `device_id` / `device_secret` — 设备身份
- `fingerprint_hash` — 设备指纹哈希
- `session_id` / `session_secret` — 当前 session
- `user_external_token` — 用户令牌
- `known_user_tokens` — 已知用户令牌列表（JSON 数组，用于 failover）
- `account_sessions` / `account_session_meta` — 多账户 session 缓存与排序

**关键方法：**
- `sortTokensByLastSession()` — 按最近使用时间排序，failover 时优先尝试最近的账户
- `clearSession()` — 登出时清除 session
- `clearUserAccount()` — 被解绑时清除整个账户

> 职责：安全存储所有敏感凭证，支持多账户切换。

### `device_fingerprint.dart` — 设备指纹采集

使用 `device_info_plus` 插件采集设备硬件信息，用于设备绑定和安全校验。

**采集内容：**
- **Android** — Build（15 字段）、Version（7 字段）、ABI（3 列表）、Hardware（8 字段）
- **iOS** — Device（8 字段）、Storage（4 字段）、Utsname（5 字段）

**哈希生成：** `generate()` 用 SHA-256 + 固定盐值 `treehole_device_fingerprint_v1`，输出与后端 FingerprintService v2 一致。

> 职责：采集硬件信息 → 生成唯一设备指纹。

### `captcha_service.dart` — 阿里云验证码 2.0

WebView 方式嵌入阿里云无痕验证码（Captcha 2.0），用户完成滑块/拼图后返回 token。

**关键约束：**
- `region` / `prefix` 必须在 SDK 加载前设置
- `SceneId` 必须大写字母
- `captchaVerifyParam` 直接透传
- 每页只能 `init` 一次

**数据流：** HTML 页面 → JS SDK → `CaptchaMessage`（status / token / message）→ 回传给调用方

> 职责：注册/登录时的人机验证。

### `pow.dart` — Proof-of-Work 计算

SHA-256 hashcash 挑战，用于注册等高频操作前的防刷机制。

- `PoWChallenge` — 挑战数据（challenge_id、challenge、difficulty）
- `PoWService.solve()` — 在后台 Isolate 中暴力搜索 nonce，30 秒超时，最多 2 亿次迭代
- `_checkDifficulty()` — 检查哈希前 N 位是否为零

> 职责：客户端算力证明，防止接口滥用。

### `avatar_storage.dart` — 头像本地缓存

简单的文件存储，把用户头像保存为 `avatar.jpg` 在应用文档目录。用户页和侧边栏共用同一文件。

> 职责：头像文件的本地读写和清除。

### `binding_cache.dart` — 设备/账户绑定缓存

Hive Box `binding_cache`，缓存设备列表、账户列表、切号锁、主设备转移状态。避免每次进入用户页都重新请求。

**核心方法：**
- `prefetchAll()` — 并行拉取设备 + 账户 + 切号锁
- `refreshDevices()` / `refreshAccounts()` — 刷新并更新缓存
- `devicesEqual()` / `accountsEqual()` — 深比较，用于判断是否需要刷新 UI
- `getSwitchLockExpiresAt()` — 切号锁（内存 + Hive 懒加载）

**安全设计：** 账户缓存不含 `user_token`（仅展示字段），令牌只存到安全存储。

> 职责：绑定状态的本地缓存与增量刷新。

### `account_display.dart` — 账号展示通知

只有 9 行代码，定义一个 `accountDisplayEpoch`（`ValueNotifier<int>`）计数器。

当账户信息变更（切号、被踢、昵称/头像更新）时调用 `notifyAccountDisplayChanged()`，计数器 +1，所有监听了该 Notifier 的 Widget 自动刷新。

> 职责：一个简单的"广播器"，通知 UI 重载账户展示信息。

### `timezone_service.dart` — 时区服务

管理服务器时间的解析与显示时区转换。

**核心假设：**
- 服务器返回的无时区字符串 = 服务器本地时间（UTC+8 北京）
- 带时区（Z 或 +/-）的字符串按标准解析为 UTC
- 最终显示 = 转换到用户选定时区

**支持 14 个时区**，默认 `Asia/Shanghai`（UTC+8），选择持久化在 Hive `settings` Box。

**格式化：** 紧凑格式如 `26.1.5-14:30`（年.月.日-时:分）

> 职责：统一时间解析、转换、格式化，支持用户自选时区。
