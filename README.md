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
| 通用组件 | `app_<name>.dart` | `app_app_bar.dart`、`app_snackbar.dart` |
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
