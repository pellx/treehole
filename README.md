# treehole_flutter

树洞（匿名论坛）Flutter 客户端。后端为 NestJS，API 文档见 `API.md`。

## 技术栈

| 层 | 选型 | 说明 |
|---|------|------|
| UI | Flutter 3.x / Dart | 纯 Flutter 单代码库（Android + iOS） |
| 状态管理 | 无第三方库 | `StatefulWidget` + `setState` 为主；跨组件通信用 `ValueNotifier` |
| 本地存储 | Hive | 键值数据库，多 Box 分域 |
| 安全存储 | FlutterSecureStorage | Android Keystore / iOS Keychain |
| HTTP | `package:http` | 共享 `http.Client` 实例做连接复用 |
| 实时通信 | Socket.IO (`socket_io_client`) | 接收服务端推送事件 |
| 验证码 | 阿里云无痕验证 2.0 | WebView 嵌入 JS SDK |
| 防刷 | SHA-256 PoW | 客户端算力证明 |

## 目录结构

```
lib/
├── main.dart              # 入口：初始化 Hive → 并行启动服务 → runApp
├── app.dart               # MaterialApp 根组件：主题、生命周期、路由
├── app_navigator.dart     # GlobalKey<NavigatorState>，供服务层触发导航
│
├── config/                # 常量配置
│   ├── local.dart         #   密钥 / SDK 配置（gitignore，不入仓库）
│   └── post_limits.dart   #   发帖限制（图片数、附件大小等）
│
├── models/                # 数据模型（纯数据 + JSON 序列化）
├── services/              # 业务服务（网络、存储、安全、实时通信）
├── pages/                 # 页面，按功能模块划分子目录
│   ├── main_shell.dart    #   底部导航壳（IndexedStack 保活 4 个 tab）
│   ├── account/           #   注册、登录、验证码、设备绑定、用户资料
│   ├── square/            #   广场（信息流首页）
│   ├── post/              #   发帖 / 帖子详情
│   ├── search/            #   搜索
│   ├── messages/          #   消息通知
│   ├── favorites/         #   收藏
│   └── settings/          #   设置（主题、隐私、版本等）
├── theme/                 # 主题与样式常量
└── widgets/               # 全局可复用组件
```

## 分层规则

```
pages/ → services/ → models/
  ↓          ↓
widgets/   config/
  ↓
theme/
```

- **models/** 只定义数据结构和 `fromJson` / `toJson`，不含业务逻辑。可 import `services/timezone_service.dart`（纯工具类，用于日期解析）。
- **services/** 负责网络请求、本地存储、安全凭证。全部使用静态方法或单例（`ServiceClass.instance`），无依赖注入。
- **pages/** 通过 `setState` 管理本地 UI 状态，调用 services 获取数据。
- **widgets/** 只通过构造函数接收数据，不直接调用 services。
- **theme/** 提供颜色和尺寸常量，被 pages 和 widgets 消费。

## 命名规范

### 文件

| 类型 | 规则 | 示例 |
|------|------|------|
| 通用组件 | `app_<name>.dart` | `app_app_bar.dart`、`app_toast.dart` |
| 领域组件 | `<domain>.dart` | `post_card.dart`、`device_card.dart` |
| 页面 | `<feature>_page.dart` | `square_page.dart`、`user_page.dart` |
| 模型 | `<entity>.dart` | `post.dart`、`bound_device.dart` |
| 服务 | `<name>_service.dart` 或 `<name>.dart` | `session_service.dart`、`api.dart` |
| 主题 | `app_<feature>_theme.dart` 或 `app_dimens*.dart` | `app_bottom_nav_theme.dart` |

### 类与变量

- 类名 `PascalCase`：`PostCard`、`SessionService`、`LoginResult`
- 变量 `camelCase`，私有加 `_` 前缀：`_editing`、`_nameController`
- 常量类用私有构造：`class PostLimits { const PostLimits._(); }` + `static const` 字段
- JSON key 保持后端 `snake_case`，Dart 字段用 `camelCase`，在 `fromJson` 中转换
- API 结果类统一后缀 `Result`：`RegisterResult`、`LoginResult`、`BoundDevicesResult`
- Widget 数据类后缀 `Data`：`AccountCardData`、`DeviceCardData`

## 弹窗、提示与加载状态规范

信息提示统一为以下两类：

- **中部大弹窗**：重要说明、需要用户确认的操作，例如清除数据、解绑设备、退出登录。普通确认优先复用 `showAppConfirmDialog`（`lib/widgets/app_confirm_dialog.dart`）；确需自定义内容时沿用现有中部 Dialog 样式。
- **页面下半部小 Toast**：刷新、复制、保存、上传等普通反馈，例如“已刷新该帖子”。统一调用 `showAppToast`（`lib/widgets/app_toast.dart`）。头像上传进度、审核结果、成功和失败信息都使用这一类。

**加载信息不得混入页面文档流。** 加载、上传、审核等临时状态应通过浮层提示显示，不在页面的 Row、Column、ListView 等布局中新增提示文字、进度组件或占位间距，不让原有内容移动、增高或闪动。禁止恢复头像下方的“上传并审核中”等小字。

不要新增第三种信息提示样式，不使用系统 `ScaffoldMessenger.showSnackBar`。旧的 `showAppSnackBar` 和 `app_snackbar.dart` 已移除。底部操作菜单、图片预览和评论输入浮层属于交互面板，继续使用各自组件，不作为普通信息提示入口。

### 重要内容：中部确认弹窗

```dart
import 'package:treehole/widgets/app_confirm_dialog.dart';

final confirmed = await showAppConfirmDialog(
  context,
  title: '清除数据',
  message: '确认清除本机数据？',
  cancelText: '取消',
  confirmText: '确认清除',
);
if (!context.mounted || confirmed != true) return;
// 执行已确认的操作。
```

返回 `true` 表示确认，`false` 表示取消，`null` 表示关闭。此组件使用 App 主题及现有弹窗尺寸配置。

### 普通反馈：下半部小提示

```dart
import 'package:treehole/widgets/app_toast.dart';

showAppToast(context, message: '已刷新该帖子');

showAppToast(
  context,
  message: '头像已通过审核并更新',
  duration: const Duration(seconds: 3),
);
```

- 默认显示 1500 毫秒；可通过 `duration` 调整。
- 使用 OverlayEntry 浮层，不占用页面布局；IgnorePointer 保证提示本身不拦截点击。
- 同一 Overlay 同时只显示一条小提示，新提示替换旧提示。
- 返回一个可重复调用的关闭函数；旧提示的关闭函数不会误关新提示。
- 异步操作后显示提示前，必须检查页面或 context 是否仍然 mounted。

### 上传、审核等耗时操作

开始时显示小 Toast，结束时主动关闭，再显示结果。以下示例放在页面 State 中：

```dart
VoidCallback? _dismissProgress;
bool _uploading = false;

Future<void> runAvatarUpload(Future<void> Function() upload) async {
  if (_uploading) return;
  _uploading = true;
  final dismiss = showAppToast(
    context,
    message: '正在上传并审核…',
    duration: const Duration(seconds: 90),
  );
  _dismissProgress = dismiss;
  var message = '头像已通过审核并更新';
  try {
    await upload(); // 请求应有超时；业务失败也必须传回失败结果。
  } catch (_) {
    message = '头像上传失败，请稍后重试';
  } finally {
    dismiss();
    if (_dismissProgress == dismiss) _dismissProgress = null;
    _uploading = false;
  }
  if (!mounted) return;
  showAppToast(context, message: message);
}

@override
void dispose() {
  _dismissProgress?.call();
  super.dispose();
}
```

Toast 不阻止重复操作，业务层仍需使用忙碌标记避免重复提交。切换账号时也应关闭旧进度提示，并防止旧请求结果覆盖新账号。实际头像流程见 `lib/pages/account/user_page.dart`。

修改小提示行为后，可运行 `flutter test test/app_toast_test.dart`，验证下半部位置、页面布局不变、提示替换和关闭行为。
## 核心模式

### 模型类（Model）

```dart
class SomeResult {
  final String name;
  final DateTime? createdAt;

  const SomeResult({required this.name, this.createdAt});

  factory SomeResult.fromJson(Map<String, dynamic> json) {
    return SomeResult(
      name: json['name'] as String? ?? '',
      createdAt: TimezoneService.parseServerDateTime(json['created_at']),
    );
  }
}
```

- 不可变：所有字段 `final`，构造 `const`
- 防御性解析：nullable cast + `??` 默认值
- 日期字段统一用 `TimezoneService.parseServerDateTime()` 解析（**不要用** `DateTime.tryParse`）
- `fromJson` 是 `factory`，不是普通构造

### 服务类（Service）

```dart
class SomeService {
  const SomeService._();  // 私有构造，禁止实例化

  static Future<SomeResult?> doSomething() async {
    // ...HTTP 请求...
    if (!_isHttpSuccess(res.statusCode)) {
      ApiService.lastError = '错误描述';
      return null;
    }
    return SomeResult.fromJson(jsonDecode(res.body));
  }
}
```

- 全部静态方法或单例 `.instance`
- 错误处理：返回 `null`，错误信息写入 `ApiService.lastError`
- 中文错误消息直接在 service 层设置

### 页面（Page）

```dart
class SomePage extends StatefulWidget { ... }

class _SomePageState extends State<SomePage> {
  bool _loading = true;
  String? _error;
  List<Item> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final data = await SomeService.fetch();
    if (data == null) {
      setState(() { _loading = false; _error = ApiService.lastError; });
    } else {
      setState(() { _loading = false; _items = data; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // loading → AppLoadingCenter
    // error   → AppErrorState(onRetry: _load)
    // empty   → AppEmptyState
    // data    → 正常内容
  }
}
```

- 页面状态四态：loading / error / empty / data
- `initState` 触发首次加载
- 错误/重试通过回调闭环

### 主题消费

```dart
// 颜色：从 ThemeExtension 取
final colors = Theme.of(context).extension<AppColors>()!;
final cardColor = colors.postCard.cardBg;

// 尺寸：直接从静态类取
final padding = AppDimens.cardPadding;
```

### 跨组件通信

不用 Provider/Riverpod/Bloc，用 Flutter 原生机制：

```dart
// 广播型：计数器 +1，监听方自动刷新
// services/account_display.dart
final ValueNotifier<int> accountDisplayEpoch = ValueNotifier<int>(0);
void notifyAccountDisplayChanged() => accountDisplayEpoch.value++;

// 消费方
ValueListenableBuilder<int>(
  valueListenable: accountDisplayEpoch,
  builder: (_, __, ___) => AccountWidget(),
)
```

### 导航

```dart
// 页面间跳转
Navigator.of(context).push(topDownRoute(TargetPage()));
Navigator.of(context).push(bottomUpRoute(TargetPage()));

// 服务层跳转（无 BuildContext）
appNavigatorKey.currentState?.push(topDownRoute(TargetPage()));
```

- `topDownRoute` — 从顶部滑入
- `bottomUpRoute` — 从底部滑入
- 定义在 `lib/pages/settings/settings_navigation.dart`

### 初始化顺序

```dart
// main.dart
WidgetsFlutterBinding.ensureInitialized();
Hive.initFlutter();
await Future.wait([
  PostStorage.init(),
  BindingCache.init(),
  TimezoneService.init(),
]);
runApp(TreeholeApp(key: appKey));
```

所有服务初始化在 `runApp` 之前完成，无延迟初始化。

## 关键设计决策

### 为什么不用状态管理库？

项目规模适中，`setState` + `ValueNotifier` 已足够。避免引入 Provider/Riverpod 的学习成本和样板代码。跨组件通信场景少，`ValueNotifier` 足够覆盖。

### ApiService 为什么是单文件？

所有 HTTP 调用集中在 `ApiService`，便于统一错误处理、连接复用、mock 开关。DTO 数据类已拆到 `models/`，`api.dart` 只保留方法和传输辅助类（`ThumbnailData`）。

### 时间处理

- 服务端返回无时区字符串 → 按 UTC+8 解析为 UTC `DateTime`
- 展示时通过 `TimezoneService.convert()` 转到用户选定时区
- 所有 DTO 的 `fromJson` 在解析阶段完成转换，展示层直接读 `DateTime` 字段
- 格式化用 `TimezoneService.formatDateTime()`，紧凑格式 `26.1.5-14:30`

### 安全存储分层

| 数据类型 | 存储位置 | 封装 |
|---------|---------|------|
| 设备凭证（device_id/secret、指纹哈希） | FlutterSecureStorage | `DeviceCredentialStore` |
| Session（session_id/secret） | FlutterSecureStorage | `DeviceCredentialStore` |
| 用户令牌 | FlutterSecureStorage | `DeviceCredentialStore` |
| 帖子缓存、评论、搜索历史 | Hive | `PostStorage` |
| 绑定状态缓存 | Hive | `BindingCache` |
| 主题偏好 | Hive | `PostStorage` |

### 设备绑定模型

- 一台设备可绑定多个账户，一个账户也可绑定到多台设备
- 主设备（`isPrimary`）有特权，解绑需 2 天冷却期
- 切号有锁（`LastSwitchResult.isLocked`），防频繁切换
- 被踢下线通过 Socket.IO `binding.unbound` 事件实时通知

### 触觉反馈

交互时统一使用触觉反馈：
- 选择/确认：`HapticFeedback.lightImpact()`
- 破坏性操作：`HapticFeedback.mediumImpact()`

## 测试

```bash
flutter test          # 运行所有测试
dart analyze          # 静态分析（CI 必须通过）
```


## 举报与自动隐藏

帖子菜单可举报；回复长按提供复制、举报、收藏（占位）。同一内容由三个不同登录账号举报后自动隐藏，重复举报不计数。App 消费隐藏标记清理缓存。数据库迁移与部署步骤见 [REPORTS_DEPLOY.md](deploy/REPORTS_DEPLOY.md)。

## 消息缓存与私信审核

消息列表和已加载历史按账号加密缓存，联网时增量同步。私信发送须通过审核，连续三条明确拒绝后关闭该账号发送能力；审核服务异常不计违规。数据库、审核配置与启用步骤见 [MESSAGE_CACHE_MODERATION_DEPLOY.md](deploy/MESSAGE_CACHE_MODERATION_DEPLOY.md)。

### 统一内容安全

违规历史和账号封禁统一由后端内容安全模块管理。App 图片上传携带会话请求头；审核失败与账号封禁沿用底部小提示。处罚与数据库更名迁移见 [内容安全部署说明](deploy/CONTENT_SAFETY_DEPLOY.md)。本说明替代之前私信三次永久禁发规则。

消息页左侧铃铛直接打开 Android/iOS 系统通知设置，空心/实心对勾状态取自操作系统权限。`app_settings: 7.0.0` 兼容当前 iOS CocoaPods 工程。

铃铛样式在 [lib/theme/app_messages_theme.dart](lib/theme/app_messages_theme.dart) 中统一调整：

- notificationBellOffsetX / notificationBellOffsetY：水平和垂直偏移，正数向右 / 向下，负数向左 / 向上。图标与点击区域一起移动，请保持按钮在顶栏内。
- light / dark 中的 notificationBellOffColor、notificationBellOnColor、notificationCheckColor：浅色 / 深色主题下未开启、已开启、对勾的颜色。
- notificationBellSize / notificationCheckSize：铃铛和对勾大小，单位为逻辑像素。

补齐消息写入锁表与权限的手动 SQL 见 [MESSAGE_PUBLISH_LOCK_FIX.md](deploy/MESSAGE_PUBLISH_LOCK_FIX.md)。

首次启动后，未开启系统通知时显示一次“开启消息通知”确认弹窗；确认后请求系统授权。显示前在 Hive 的 dm_notification_preferences 中保存 startup_prompt_seen 标记，因此取消、关闭或拒绝授权后，后续启动也不再提醒；已有权限或以前已请求过授权的用户跳过提示。标记按本机安装保存，与账号无关，卸载或清除应用数据后会重置。

消息页排版、会话摘要与后端启用步骤见 [MESSAGE_LIST_LAYOUT_DEPLOY.md](deploy/MESSAGE_LIST_LAYOUT_DEPLOY.md)。布局尺寸与颜色继续集中在 lib/theme/app_messages_theme.dart；常调的纵向参数包括 headerHeight、headerTitleOffsetY、clearUnreadOffsetY、moreActionsOffsetY、shortcutTopPadding、shortcutItemVerticalPadding、shortcutLabelGap、shortcutBottomPadding、conversationVerticalPadding、conversationTextGap 和 conversationMinHeight。
