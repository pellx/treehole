# 一对一私聊（第一期）

两端仓库各有一份相同文档：`treehole_backend_nestjs/design-private-chat.md`、`treehole_app_flutter/design-private-chat.md`。拉任意一端都能按本文理解并测试。

接口契约也写在 Flutter 的 `API.md`（「私聊 API」+ 附录 E `chat.message`）。

---

## 1. 这期做了什么

- 消息 Tab：会话列表 + 未读 + 下拉刷新 + 右上角按昵称发起
- 对话页：一对一纯文字，长按复制
- 在线推送：Socket.IO 事件 `chat.message`，推到该用户所有在线设备（房间 `user:{user_id}`），**不断开**连接
- 广场 / 搜索：点署名作者进私聊；评论署名单击同样，长按仍展开过长昵称
- 匿名帖没有作者，不能从广场发起；不能给自己发

**没做：** 图片、已读回执 UI、拉黑、底栏未读角标、系统推送（无 FCM/APNs）。对方离线时消息只入库，下次打开 App 再拉。

身份约定：内部用稳定的 `user_id`；对外按**当前昵称或曾用名**查找（`users.user_display_id` + `user_identifier_history`）。改名后会话不断，标题显示当前名。

---

## 2. 上线 / 联调前必做：建表

TypeORM `synchronize: false`，**不跑 SQL 接口会直接报错**。

文件：`database/migrations/20260831_create_chat_tables.sql`

```sql
-- 私聊：一对一会话 + 消息
CREATE TABLE IF NOT EXISTS conversations (
  id BIGINT NOT NULL AUTO_INCREMENT,
  user_low INT NOT NULL,
  user_high INT NOT NULL,
  last_message_id BIGINT NULL DEFAULT NULL,
  last_sender_user_id INT NULL DEFAULT NULL,
  last_preview VARCHAR(120) NULL DEFAULT NULL,
  last_message_at TIMESTAMP NULL DEFAULT NULL,
  low_read_message_id BIGINT NOT NULL DEFAULT 0,
  high_read_message_id BIGINT NOT NULL DEFAULT 0,
  low_unread INT NOT NULL DEFAULT 0,
  high_unread INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_conversations_pair (user_low, user_high),
  KEY idx_conversations_last_message_at (last_message_at),
  KEY idx_conversations_user_low (user_low),
  KEY idx_conversations_user_high (user_high)
);

CREATE TABLE IF NOT EXISTS messages (
  id BIGINT NOT NULL AUTO_INCREMENT,
  conversation_id BIGINT NOT NULL,
  sender_user_id INT NOT NULL,
  body VARCHAR(2000) NOT NULL,
  client_msg_id VARCHAR(64) NULL DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_messages_client (conversation_id, sender_user_id, client_msg_id),
  KEY idx_messages_conversation_id (conversation_id, id),
  CONSTRAINT fk_messages_conversation
    FOREIGN KEY (conversation_id) REFERENCES conversations (id)
    ON DELETE CASCADE
);
```

生产库（App 打的是 `https://tree.leisure.xin/node/...`）也必须执行，否则客户端消息 Tab 会失败。

检查：

```sql
SHOW TABLES LIKE 'conversations';
SHOW TABLES LIKE 'messages';
```

---

## 3. 怎么测（App）

准备 **两个已注册账号**（两台设备，或同一设备切号）。双方都要能拿到有效 session（启动 App 后会自动 `session/create`）。

### 3.1 消息 Tab

1. 登录账号 A，底栏点「消息」
2. 未登录时应看到「登录后查看私信」；登录后空列表文案为「还没有私信」
3. 点右上角编辑图标 → 输入账号 B 的**当前昵称** → 进入对话页

### 3.2 从广场发起

1. 账号 B 发一条**署名**帖（不要匿名）
2. 账号 A 在广场 / 搜索点标题旁的 `@昵称`，或点评论署名
3. 应进入与 B 的对话页；匿名帖点不到作者

### 3.3 收发 + 在线推送

1. A、B 都打开 App 并保持在前台（WS 已连接）
2. A 发「你好」→ B 的对话页应马上出现，不必手动刷新
3. B 回到消息 Tab，该会话应在最上面，预览为「你好」
4. A 再发几条后切走，B 列表应有未读数字；B 点进会话后未读清零
5. 长按气泡 → 「已复制」

### 3.4 边界

| 操作 | 预期 |
|---|---|
| 输入不存在的昵称 | Toast「找不到该用户」 |
| 输入自己的昵称 | Toast「不能给自己发私信」 |
| 未登录点作者 | 进入注册页；注册成功返回后可继续 |
| 切号后再进消息 Tab | 列表换成当前账号的会话 |
| 对方改名 | 会话还在，标题变成新昵称；用旧名查找仍能找到（曾用名占用） |

### 3.5 审核 / 限流

- 发送明显违规文本 → 失败，文案带「内容审核未通过」或映射后的审核提示
- 同一账号 60 秒内发超过 40 条 → `RATE_LIMITED` / 「发送太频繁」

---

## 4. 怎么测（curl，不打开 App）

Base：生产 `https://tree.leisure.xin/node`，本地默认 `http://127.0.0.1:7300/node`。

先用已有流程拿到两个账号的 `session_id` + `session_secret`（`POST /user/session/create`）。下面用 `$HOST`、`$SID_A`、`$SEC_A`、`$SID_B`、`$SEC_B`。

```bash
HOST=https://tree.leisure.xin/node   # 本地改成 http://127.0.0.1:7300/node

# 按昵称查找 B
curl -s -X POST "$HOST/chat/lookup" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":$SID_A,\"session_secret\":\"$SEC_A\",\"display_id\":\"B的昵称\"}"

# 获取或创建会话
curl -s -X POST "$HOST/chat/dm" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":$SID_A,\"session_secret\":\"$SEC_A\",\"peer_display_id\":\"B的昵称\"}"
# 记下返回的 id，下面用 $CID

# 发送
curl -s -X POST "$HOST/chat/send" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":$SID_A,\"session_secret\":\"$SEC_A\",\"conversation_id\":$CID,\"body\":\"你好\",\"client_msg_id\":\"test-1\"}"

# 同一 client_msg_id 再发一次应返回同一条（幂等）

# B 拉列表，unread_count 应 > 0
curl -s -X POST "$HOST/chat/conversations" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":$SID_B,\"session_secret\":\"$SEC_B\"}"

# 历史（时间正序）
curl -s -X POST "$HOST/chat/history" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":$SID_B,\"session_secret\":\"$SEC_B\",\"conversation_id\":$CID,\"limit\":30}"

# 已读
curl -s -X POST "$HOST/chat/read" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":$SID_B,\"session_secret\":\"$SEC_B\",\"conversation_id\":$CID,\"last_read_message_id\":消息id}"
```

无 session → `401 MISSING_SESSION` / `SESSION_INVALID`。给自己开会话 → `400 CHAT_SELF`。

实时：用已有 WS 客户端连 `path=/node/socket.io`，`auth: { session_id, session_secret }`，监听 `chat.message`。payload 含 `conversation`（**接收方视角**的 peer / unread）和 `message`。此事件**不会**断开连接（和 `binding.unbound` / `session.invalidated` 不同）。

---

## 5. 接口一览（全部要 session）

| 方法 | 路径 | 作用 |
|---|---|---|
| POST | `/chat/lookup` | `{ display_id }` → `{ user_id, user_display_id }` |
| POST | `/chat/dm` | `{ peer_user_id }` 或 `{ peer_display_id }` → 会话对象 |
| POST | `/chat/conversations` | 列表 + `unread_count` |
| POST | `/chat/send` | `{ conversation_id, body, client_msg_id? }` → 消息；并 WS 推双方 |
| POST | `/chat/history` | `{ conversation_id, before_id?, limit? }` 默认 30，最多 50 |
| POST | `/chat/read` | `{ conversation_id, last_read_message_id }` |

正文最长 2000；发送走与发帖相同的文本审核。

---

## 6. 代码落点

### 后端（本仓库）

| 路径 | 说明 |
|---|---|
| `src/chat/` | 新模块：表实体、DTO、Service、Controller |
| `src/app.module.ts` | 挂上 `ChatModule` |
| `src/realtime/realtime.service.ts` | 新增 `emitToUser`（不 disconnect） |
| `database/migrations/20260831_create_chat_tables.sql` | 建表 |

没有改 User / Posts / 短信。

### 客户端（Flutter 仓库）

| 路径 | 说明 |
|---|---|
| `lib/services/chat_api.dart` | 私聊 HTTP（**独立文件**，不改 `api.dart` 末尾） |
| `lib/services/chat_inbox.dart` | 列表 + 收 WS |
| `lib/models/chat.dart` | 会话 / 消息 |
| `lib/pages/messages/` | 列表、对话页、从昵称打开 |
| `lib/widgets/post_card.dart` | 署名作者可点 |
| `lib/services/realtime_service.dart` | 监听 `chat.message` |
| `lib/services/session_service.dart` | `session/validate` 成功时写入本地 `user_id` |
| `lib/services/device_credential_store.dart` | 增 `user_id` |
| `lib/widgets/app_app_bar.dart` | `AppScaffold.automaticallyImplyLeading`（消息 Tab 去掉返回箭头） |
| `lib/pages/main_shell.dart` | 切到消息 Tab 时刷新登录态 |

---

## 7. 协作：短信注册那侧请避开这些，并注意下面几点

私聊**故意没改**下列文件，方便你继续做手机号登录：

- `lib/pages/account/register_page.dart`
- `lib/pages/account/captcha_view.dart` / `captcha_service.dart`
- `lib/pages/account/switch_account_page.dart`（`startAtLogin: true` 令牌登录）
- `lib/pages/settings/settings_navigation.dart`（`bottomUpRoute` 仍是通用的）
- `lib/theme/app_dimens_register.dart`、`lib/theme/app_colors.dart` 的现有 key
- `lib/services/api.dart`（短信三个方法请只在**文件末尾追加**）
- 服务端短信代码

你计划的改动可以按这个范围做：

1. `register_page.dart`：`_check()` 里 `registered == true` 时 `pushReplacement` 到新页面；删 registered 阶段专属 UI（标题分支、`_buildRegistered`、登录/联系我们）。**不要按行号定位**（验证码还在改），搜 `_phase == 'registered'`。不要碰 captcha / naming / login。
2. login 阶段「找回用户」TODO 和新页「手机号找回」保持两条路径，不要合并。
3. `api.dart` 末尾追加 `smsSend` / `smsRegister` / `smsLogin`；错误码映射写在**新方法内部**，不要改 `_parseErrorMessage`。
4. dimens / `RegisterColors` 只追加新 key；加 `RegisterColors` 字段时同步 constructor、`registerLight`、`registerDark`。

**指纹 hash 不要用 `DeviceFingerprintService.generate()`（约第 27 行）。**  
那是 `SHA-256('treehole_device_fingerprint_v1:' + json)`，没有调用方。和后端对齐的是 `SessionService._computeFingerprintHash`（`session_service.dart` 里，`login` / `binding/create` / `session/create` 都用它）。`sms/login` 必须用这个，否则 `FINGERPRINT_MISMATCH`。它现在是私有方法，建议改成 public 或抽到 `device_fingerprint.dart`，不要用 `generate()`。

**`session_service.dart` 建议追加、不要改 `loginWithToken`：**  
`sms/login` 直接返回 session，不返回 `user_token` / `device_secret`。现有 `ensureSession()` 靠 token+secret 续签。需要类似 `applySmsSession(...)` 写 session 并连 WS。只在新页面 `saveSession*` 会和现有生命周期脱节。

**服务端 `smsLogin` 已知坑（这轮私聊没改）：** 轮换了 `device_secret` 却不返回；响应没有 `user_token`；指纹对不上不能建新设备。后续最小补丁：响应带上 `user_token` + 新 `device_secret`。`sms/register` 要的是 Turnstile，当前 App 注册走阿里云验证码 `registerV2`；已注册设备进新页这轮用 `sms/login` 即可。

私聊在 `session_service.dart` 里只加了一处：validate 成功时 `saveUserId`。你追加 `applySmsSession` 时不要删这行。

---

## 8. 排错

| 现象 | 先看 |
|---|---|
| 消息 Tab 一直失败 / 500 | 生产库是否执行了建表 SQL |
| 查找用户 404 | 昵称是否当前名或历史名；匿名帖没有作者 |
| 能发但不能实时收到 | 双方是否 `ensureSession` 后已连 WS；多实例未接 redis-adapter 时只有打到同一进程才推得到 |
| 气泡都挤在一侧 | 本地 `user_id` 未写入（看 `session/validate` 是否成功） |
| 和短信 PR 冲突 | 私聊不应出现在 `api.dart` / `register_page.dart`；若撞了 `session_service.dart`，只保留各自追加的方法 |

部署顺序：执行 SQL → 部署 Nest（含 `ChatModule`）→ 再发带消息页的 App。
