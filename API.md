# treehole-nest

Base URL: `http://<host>:7300/node`（`GLOBAL_PREFIX` 默认 `node`，端口默认 `7300`）

除文件上传外，请求/响应均为 `Content-Type: application/json`。  
受保护接口（标注 🔒）需在 body 或 header 携带 session：`session_id` / `session_secret`（或 `x-session-id` / `x-session-secret`）。

---

## 最近更新

### 2026-08

- **新增手机号验证码登录/注册/换绑**
  - 新增接口：`POST /user/sms/send`、`/user/sms/register`、`/user/sms/login`、`/user/sms/bind`
  - 使用阿里云「号码认证服务 - 短信认证」（Dypnsapi）下发和校验验证码
  - 注册一步完成建号 + 建绑；登录直接签发 session
- **iOS fingerprint_hash 冲突解决**
  - Android 保持 `fingerprint_hash` 全局唯一
  - iOS 允许同一指纹在不同用户下重复，登录时按 `(user_id, fingerprint_hash)` 定位设备
  - 数据库需取消 `fingerprints.uk_fingerprints_hash` 全局唯一索引
- **文档补充**
  - 新增附录 F（阿里云验证码 2.0）、附录 G（LLM 二次审核）、附录 H（阿里云短信认证服务）
- **测试清理**
  - 删除原有 4 个无法运行的 `*.spec.ts` 文件（依赖缺失 / 含硬编码 AK）

---

## 目录

- [用户系统 API](#用户系统-api)
  - [1. GET /user/pow-challenge](#1-get-userpow-challenge)
  - [2. POST /user/check](#2-post-usercheck)
  - [3. POST /user/register](#3-post-userregister)
  - [3b. POST /user/registerV2](#3b-post-userregisterv2)
  - [4. POST /user/login](#4-post-userlogin)
  - [4b. POST /user/sms/send](#4b-post-usersmssend)
  - [4c. POST /user/sms/register](#4c-post-usersmsregister)
  - [4d. POST /user/sms/login](#4d-post-usersmslogin)
  - [4e. POST /user/sms/bind](#4e-post-usersmsbind)
  - [5. POST /user/session/create](#5-post-usersessioncreate)
  - [6. POST /user/session/validate](#6-post-usersessionvalidate)
  - [7. POST /user/profile](#7-post-userprofile)
  - [8. POST /user/rename](#8-post-userrename)
  - [9. POST /user/token/reset](#9-post-usertokenreset)
  - [10. POST /user/devices2user](#10-post-userdevices2user)
  - [11. POST /user/user2device](#11-post-useruser2device)
  - [12. POST /user/binding/create](#12-post-userbindingcreate)
  - [13. POST /user/binding/occupied](#13-post-userbindingoccupied)
  - [14. POST /user/binding/last-switch](#14-post-userbindinglast-switch)
  - [15. POST /user/binding/transfer-request](#15-post-userbindingtransfer-request)
  - [16. POST /user/binding/rename](#16-post-userbindingrename)
  - [17. POST /user/binding/delete](#17-post-userbindingdelete)
  - [18. POST /user/binding/delete-cancel](#18-post-userbindingdelete-cancel)
  - [19. POST /user/binding/primary-transfer](#19-post-userbindingprimary-transfer)
  - [20. POST /user/binding/primary-transfer-cancel](#20-post-userbindingprimary-transfer-cancel)
- [贴文 API](#贴文-api)
  - [21. POST /posts](#21-post-posts)
  - [22. POST /posts/comment](#22-post-postscomment)
  - [23. GET /posts/idList](#23-get-postsidlist)
  - [23b. GET /posts/idListv2](#23b-get-postsidlistv2)
  - [24. POST /posts/idListUpdate](#24-post-postsidlistupdate)
  - [25. GET /posts/idListByAuthor/:author](#25-get-postsidlistbyauthorauthor)
  - [26. GET /posts/:id](#26-get-postsid)
  - [27. GET /posts/comment/:id](#27-get-postscommentid)
- [文件 API](#文件-api)
  - [28. POST /file-processor/upload](#28-post-file-processorupload)
  - [29. GET /file-processor/convert/:variant/\*path](#29-get-file-processorconvertvariantpath)
- [版本 API](#版本-api)
  - [30. GET /versions/latest](#30-get-versionslatest)
  - [31. GET /versions](#31-get-versions)
- [其它](#其它)
  - [32. GET /](#32-get-)
- [绑定状态说明](#绑定状态说明)
- [login / binding/create / session/create 对比](#login--bindingcreate--sessioncreate-对比)
- [附录 A: 设备指纹结构](#附录-a-设备指纹结构)
- [附录 B: fingerprint_hash 计算方法](#附录-b-fingerprint_hash-计算方法)
- [附录 C: 注册 / 登录流程](#附录-c-注册--登录流程)
- [附录 D: Session 使用](#附录-d-session-使用)
- [附录 E: Realtime / Socket.IO](#附录-e-realtime--socketio)
- [附录 F: 阿里云验证码 2.0](#附录-f-阿里云验证码-20)
- [附录 G: LLM 二次内容审核](#附录-g-llm-二次内容审核)
- [附录 H: 阿里云短信认证服务](#附录-h-阿里云短信认证服务)
- [环境变量](#环境变量)
- [数据库迁移](#数据库迁移)
- [开发](#开发)

---

## 用户系统 API

### 1. GET /user/pow-challenge

获取 PoW 挑战（TTL 约 3 分钟）。校验时不消费；**仅注册成功后**使该挑战失效。注册失败（昵称冲突等）可在有效期内用同一 `challenge_id` + `nonce` 重试。

Turnstile 同理：首次 `siteverify` 成功后服务端缓存约 5 分钟，注册失败可复用同一 token；**仅注册成功后**清除缓存（Cloudflare 侧 token 本身仍是一次性，靠服务端缓存实现重试）。

**响应** `200`

```json
{
  "challenge_id": "a1b2...",
  "challenge": "e5f6...",
  "difficulty": 18
}
```

| 字段 | 说明 |
|---|---|
| `challenge_id` | 唯一标识，后续注册时回传 |
| `challenge` | 随机串 |
| `difficulty` | 要求前导零位数 |

客户端计算：遍历 nonce 直至 `SHA-256(challenge + nonce)` 前 `difficulty` 位为零。

---

### 2. POST /user/check

查询设备指纹是否已注册。仅查询，无需 Turnstile / PoW。

**请求**

```json
{
  "device_finger_print": { "platform": "android", "android": {...} }
}
```

结构见 [附录 A](#附录-a-设备指纹结构)。

**响应** `200`

```json
{ "registered": false }
```

---

### 3. POST /user/register

创建用户。需 Turnstile + PoW。指纹冲突时返回 400。  
昵称不得与其他用户的**当前名**或 **`user_identifier_history` 历史名**冲突（`NAME_TAKEN`）。

**请求**

```json
{
  "user_display_id": "昵称（1-100字符）",
  "device_finger_print": { "platform": "android", "android": {...} },
  "verification_turnstile": "Cloudflare Turnstile token",
  "verification_pow": {
    "challenge_id": "来自 pow-challenge",
    "nonce": 123456
  }
}
```

**响应** `201`

```json
{
  "user_token": "16位hex",
  "device_secret": "64位hex"
}
```

| 字段 | 说明 |
|---|---|
| `user_token` | 用户凭证 |
| `device_secret` | 设备凭证 |

**错误**

| 状态码 | message |
|---|---|
| 400 | `该设备环境已注册` |
| 400 | `NAME_TAKEN` |
| 400 | `NAME_EMPTY` |
| 400 | `Turnstile 验证失败` |
| 400 | `PoW 验证失败` |

注册成功后会写入：

- `users` — 用户记录（`user_token`、`user_display_id`、`primary_device_id` = 本机设备）
- `devices` — 设备记录（`device_secret_hash`、`fingerprint_hash`）
- `fingerprints` — 完整指纹字段 + `fingerprint_hash`
- `user_identifier_history` — 初始名字记录
- `user_token_history` — 注册签发的 `user_token`

**不会**写入 `user_device_binding`。须再调 `/user/login` 或 `/user/binding/create` 建绑，再调 `/user/session/create` 拿 session。

成功后将 `user_token` 和 `device_secret` 写入 Keystore/Keychain。

---

### 3b. POST /user/registerV2

创建用户（阿里云验证码 2.0「无痕验证」版）。需 **Captcha + PoW**。指纹冲突时返回 400。
与 v1 `register` 并存：v2 走 `verification_captcha`，v1 仍走 `verification_turnstile`，互不影响。

**请求**

```json
{
  "user_display_id": "昵称（1-100字符）",
  "device_finger_print": { "platform": "android", "android": {...} },
  "verification_captcha_ticket": "captcha/verify 签发的凭证（推荐，与 verification_captcha 二选一）",
  "verification_captcha": "阿里云验证码 captchaVerifyParam（客户端原样透传；无凭证时的兼容方式）",
  "verification_pow": {
    "challenge_id": "来自 pow-challenge",
    "nonce": 123456
  }
}
```

**响应** `201`（同 v1）

```json
{
  "user_token": "16位hex",
  "device_secret": "64位hex"
}
```

**错误**

| 状态码 | message |
|---|---|
| 400 | `该设备环境已注册` |
| 400 | `NAME_TAKEN` |
| 400 | `NAME_EMPTY` |
| 400 | `验证码已使用或过期，请重新验证`（F008：token 一次性，重试须重新取 token） |
| 400 | `访问过于频繁，请稍后重试`（F010） |
| 400 | `验证码校验失败，请重试` |
| 400 | `验证码服务异常，请重试` |
| 400 | `验证码服务未配置`（服务端缺 `CAPTCHA_SCENE_ID` / AK） |
| 400 | `PoW 验证失败` |

与 v1 的差异：`captchaVerifyParam` 为**一次性**（复用/过期返回 F008、约 20 分钟过期）。

**推荐流程（凭证模式）**：客户端在「通过测试」页完成验证后立即调 [3c. POST /user/captcha/verify](#3c-post-usercaptchaverify) 即时校验，拿 `captcha_ticket` 凭证再提交本接口。凭证 10 分钟有效，**注册失败可复用**（如改名重试），**仅注册成功后销毁**；过期返回 `验证码已使用或过期，请重新验证`，客户端须重新完成验证。直传 `verification_captcha` 为旧客户端兼容路径，失败后须重新取 token。

成功后的落库与 v1 相同（users / devices / fingerprints / 两个 history，**不写** `user_device_binding`，须再 `/user/login` 或 `/user/binding/create` 建绑）。

---

### 3c. POST /user/captcha/verify

即时校验阿里云验证码（供「通过测试」页在用户完成交互后立即调用），通过后签发 Redis 凭证供 `registerV2` 使用。使风控结论（F001 等）当场可见，注册时刻无需再调阿里云。

**请求**

```json
{
  "captcha_verify_param": "验证码脚本回调的 captchaVerifyParam，原样透传"
}
```

**响应** `200`

```json
{
  "captcha_ticket": "uuid（10 分钟有效）"
}
```

**错误** `400`：即附录 F 的 verifyCode 映射文案（如 `风险校验未通过，请稍后再试(F001)`）、`验证码服务异常，请重试`。

**行为**

- 凭证键 `captcha:ticket:<uuid>`，TTL 600 秒；
- `registerV2` 校验凭证存在即放行，**仅注册成功后销毁**——注册失败（昵称占用等）改名可直接重试；
- 旧客户端仍可直传 `verification_captcha`（服务端即时调阿里云校验）。

---


---

### 4. POST /user/login

建绑本机并**轮换** `device_secret`；**不**签发 session。  
适用：本机尚无 secret、secret 丢失、或主动轮换凭证。

不需要提交旧 `device_secret`。成功后旧 secret 立即失效，客户端须用响应中的新值覆盖 Keystore。

**请求** `200`

```json
{
  "user_token": "已有账户的 user_token",
  "fingerprint_hash": "当前设备指纹 SHA-256 hex"
}
```

**响应**

```json
{
  "device_secret": "新的64位hex（须保存）",
  "binding_id": 12,
  "device_id": 5
}
```

**校验链路**

1. `user_token` → 查用户
2. `fingerprint_hash` → 定位本机设备
3. 检查 `session:device_owner`：异用户占用中 → `DEVICE_SESSION_LOCKED`
4. 确保 user↔device 活绑定（无则新建；曾 `unbound` 则复活）
5. 生成新 `device_secret`，`bcrypt(secret + pepper)` 覆盖 `devices.device_secret_hash`

**冷却开关**（环境变量 `TEST_MODEL`）：

| `TEST_MODEL` | 行为 |
|---|---|
| `true` | **取消** 2 天冷却，可立即再 login / binding/create |
| `false` | **启用** 冷却：上次解绑生效（`unbound_at`）在 2 天内则 `REBIND_COOLDOWN` |

未设为 `true` 时按有冷却处理。

**错误**

| 状态码 | message | 说明 |
|---|---|---|
| 401 | `USER_NOT_FOUND` | |
| 401 | `FINGERPRINT_MISMATCH` | |
| 401 | `DEVICE_NOT_FOUND` | |
| 400 | `DEVICE_SESSION_LOCKED` | 本机 2 天切号锁被异用户占用 |
| 400 | `REBIND_COOLDOWN` | 解绑后再绑定冷却（受 `TEST_MODEL` 控制） |
| 400 | `TRANSFER_REQUIRED` | 用户已在其他设备有活绑定，须先在原设备发起转移申请 |
| 400 | `TRANSFER_INVALID` | 转移申请无效 |
| 400 | `用户绑定设备数已达上限` / `设备绑定用户数已达上限` | |

若本机**已有**该用户的活绑定，`login` 只轮换 secret，**不需要**转移申请。建绑后须再调 `session/create` 拿 session。

---

### 4b. POST /user/sms/send

发送短信验证码到指定手机号。调用阿里云「号码认证服务 - 短信认证」接口 `SendSmsVerifyCode`，由阿里云负责验证码生成、存储和生命周期管理。

同一手机号 60 秒内不可重复发送，24 小时内最多 25 条；同一 IP 1 分钟内最多 5 条。阿里云侧也有自身的频率控制和防刷策略。

**请求**

```json
{
  "phone": "13800138000",
  "scene": "register"
}
```

`scene` 可选：`register` | `login` | `bind`。

**响应** `200`

```json
{
  "sent": true,
  "cooldown_seconds": 60
}
```

若处于冷却期：`sent: false`，`cooldown_seconds` 为剩余秒数。

**错误**

| 状态码 | message | 说明 |
|---|---|---|
| 400 | `SMS_DAILY_LIMIT_EXCEEDED` | 该手机号 24 小时内发送次数已达上限 |
| 400 | `SMS_IP_RATE_LIMIT_EXCEEDED` | 当前 IP 发送过于频繁 |
| 400 | `SMS_SEND_FAILED` | 短信服务商调用失败 |

---

### 4c. POST /user/sms/register

手机号验证码注册（新账号）。一步完成建号 + 建绑，返回 `user_token` + `device_secret`；后续仍需调 `/user/session/create` 拿 session。

**请求**

```json
{
  "phone": "13800138000",
  "code": "123456",
  "user_display_id": "昵称",
  "device_finger_print": { "platform": "ios", "ios": {...} },
  "verification_captcha": "阿里云验证码 2.0 captchaVerifyParam",
  "verification_pow": {
    "challenge_id": "...",
    "nonce": 123456
  }
}
```

**响应** `201`

```json
{
  "user_token": "16位hex",
  "device_secret": "64位hex"
}
```

**特性**

- 与 `/user/registerV2` 一致：阿里云验证码 2.0 + PoW 防刷（captcha param 一次性，无需 consume）。
- 事务内同时写入 `users`、`devices`、`fingerprints`、`user_device_binding`（active）及两个 history 表。
- iOS 设备允许 `fingerprint_hash` 重复（不同用户各自独立建绑）。
- Android 设备命中已注册指纹时不再拒绝：复用既有设备建新号并轮换 `device_secret`（「已注册设备引导页 → 注册新账号」只会出现在设备已注册的状态下）。

**错误**

| 状态码 | message |
|---|---|
| 400 | `SMS_CODE_INVALID` / `SMS_CODE_EXPIRED` / `SMS_CODE_ATTEMPTS_EXCEEDED` |
| 400 | `PHONE_TAKEN` |
| 400 | `NAME_TAKEN` |
| 400 | `验证码验证失败`（含 F00x）/ `PoW 验证失败` |

---

### 4d. POST /user/sms/login

手机号验证码登录（已存在账号）。直接签发 session，无需再走 `/user/login` + `/user/session/create`。

**请求**

```json
{
  "phone": "13800138000",
  "code": "123456",
  "fingerprint_hash": "当前设备指纹 SHA-256 hex"
}
```

**响应** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex",
  "user_token": "16位hex"
}
```

`user_token` 供客户端登记本机账户令牌（切号 / 解绑 failover 机制依赖）。

**校验链路**

1. 校验短信验证码
2. 通过 `phone` 找到用户；未找到时进入找回路径（见下）
3. 在该用户的绑定范围内匹配 `fingerprint_hash` 定位设备（兼容 iOS 重复指纹）
4. 检查 `session:device_owner` 切号锁
5. 若尚无绑定则自动建绑
6. 轮换 `device_secret`，签发 session

**找回路径（未注册手机号）**

`phone` 未注册时，按 `fingerprint_hash` 定位本机活绑定（active / unbind_pending）的账户：
若其中**恰好只有一个**从未绑定过手机号的账户，则视为找回该账户——把该手机号绑定为账户手机号
（短信验证码已通过、且全库无其他用户占用该号码），并继续正常登录流程。
候选为 0 个（无匹配设备）或多个（无法消歧）时仍返回 `USER_NOT_FOUND`；
已绑定手机号的账户必须用绑定手机号找回。

**错误**

| 状态码 | message | 说明 |
|---|---|---|
| 400 | `SMS_CODE_INVALID` / `SMS_CODE_EXPIRED` / `SMS_CODE_ATTEMPTS_EXCEEDED` | |
| 401 | `USER_NOT_FOUND` | 手机号未注册，且不满足找回路径条件 |
| 401 | `FINGERPRINT_MISMATCH` | 该用户下无匹配指纹设备 |
| 400 | `DEVICE_SESSION_LOCKED` | 本机切号锁被异用户占用 |
| 400 | `REBIND_COOLDOWN` / `TRANSFER_REQUIRED` / `TRANSFER_INVALID` | 建绑受限 |

---

### 4e. POST /user/sms/bind

🔒 当前 session 用户绑定/换绑手机号。

**请求**

```json
{
  "session_id": 1,
  "session_secret": "...",
  "phone": "13800138000",
  "code": "123456"
}
```

**响应** `200`

```json
{
  "phone": "13800138000"
}
```

**错误**

| 状态码 | message |
|---|---|
| 400 | `SMS_CODE_INVALID` / `SMS_CODE_EXPIRED` / `SMS_CODE_ATTEMPTS_EXCEEDED` |
| 400 | `PHONE_TAKEN` | 该手机号已被其他用户绑定 |

---

### 5. POST /user/session/create

用已有绑定申请 session（**不**自动创建绑定；切号也走此接口）。

**请求** `201`

```json
{
  "user_token": "注册返回的 user_token",
  "device_secret": "当前有效的 device_secret",
  "fingerprint_hash": "当前设备指纹 SHA-256 hex"
}
```

**响应**

```json
{
  "session_id": 1,
  "session_secret": "64位hex"
}
```

**校验链路**

1. `user_token` → 查用户
2. `fingerprint_hash` → 定位本机设备
3. 校验 `device_secret`
4. 查 **该 user + 该 device** 的活绑定
5. 检查 `session:device_owner`：异用户 → `DEVICE_SESSION_LOCKED`
6. 签发 session；**删除本机旧 session**（`session:by_device` 指向的凭证）。若踢掉的是**另一用户**（切号）→ 写入 `device_owner` TTL 2 天，并清理遗留 `session:by_user` 索引
7. 同用户续签或本机首次建 session：**不写 / 不刷新** `device_owner`

**错误**

| 状态码 | message |
|---|---|
| 401 | `USER_NOT_FOUND` |
| 401 | `DEVICE_NOT_BOUND` |
| 401 | `DEVICE_SECRET_INVALID` |
| 401 | `FINGERPRINT_MISMATCH` |
| 400 | `DEVICE_SESSION_LOCKED` |
| 400 | `RATE_LIMITED` |

---

### 6. POST /user/session/validate

校验 session 有效性。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex"
}
```

**响应**

```json
{ "valid": true, "user_id": 7 }
```

服务端从 Redis 取 `session:{id}`，比对 `SHA-256(secret)` 与存储的 hash。Session 数据须同时含 `user_id` 与 `device_id`，否则视为无效。`SessionGuard` 会把二者挂到 request（受保护接口用）。

**错误**

| 状态码 | message |
|---|---|
| 401 | `SESSION_INVALID` |

---

### 7. POST /user/profile

查询当前用户资料（需有效 session）。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex"
}
```

**响应**

```json
{
  "user_display_id": "昵称",
  "display_id_changed_at": "2026-07-01T12:00:00.000Z",
  "token_reset_at": "2026-05-01T12:00:00.000Z",
  "primary_device_id": 5,
  "primary_device_pending_id": null,
  "primary_transfer_requested_at": null,
  "primary_transfer_execute_at": null
}
```

| 字段 | 说明 |
|---|---|
| `user_display_id` | 当前显示名 |
| `display_id_changed_at` | 上次改名时间；从未改过为 `null` |
| `token_reset_at` | 上次令牌重置时间；从未重置过则回退为注册时间 `created_at` |
| `primary_device_id` | 主设备 id（注册时第一台设备）；不可解绑；旧用户可能为 `null` |
| `primary_device_pending_id` | 迁移中的目标主设备；无申请为 `null` |
| `primary_transfer_requested_at` / `primary_transfer_execute_at` | 迁移申请 / 预计生效时间（申请 + 2 天） |

---

### 8. POST /user/rename

改名。需有效 session。冷却期 **14 天**；名字不得被其他用户使用过（含 `user_identifier_history`）。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex",
  "new_name": "新昵称（1-100字符）"
}
```

**响应**

```json
{
  "user_display_id": "新昵称",
  "display_id_changed_at": "2026-07-18T04:00:00.000Z"
}
```

成功后写入：

- `users.user_display_id` + `user_display_id_changed_at`
- `user_identifier_history`（`type=display_id`）

**错误**

| 状态码 | message |
|---|---|
| 400 | `NAME_EMPTY` |
| 400 | `NAME_UNCHANGED` |
| 400 | `RENAME_TOO_FREQUENT` |
| 400 | `NAME_TAKEN` |
| 401 | `MISSING_SESSION` / `SESSION_INVALID` / `USER_NOT_FOUND` |

`RENAME_TOO_FREQUENT` 时响应体附带：

```json
{
  "statusCode": 400,
  "message": "RENAME_TOO_FREQUENT",
  "display_id_changed_at": "2026-07-04T12:00:00.000Z",
  "next_rename_at": "2026-07-18T12:00:00.000Z"
}
```

| 字段 | 说明 |
|---|---|
| `display_id_changed_at` | 上次改名时间 |
| `next_rename_at` | 下次可改名时间（= `display_id_changed_at` + 14 天） |

---

### 9. POST /user/token/reset

重置用户令牌。需有效 session，**无冷却限制**。返回新 `user_token`；旧 token 立即失效。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex"
}
```

**响应**

```json
{
  "user_token": "16位hex",
  "token_reset_at": "2026-07-18T04:00:00.000Z"
}
```

成功后：

- 将新 `user_token` 写入 `user_token_history`（每次签发都记入；旧 token 若尚未入表也会补记）
- 更新 `users.user_token` 为新值（新 token 不得与当前或其他历史 token 重复）
- 更新 `users.user_token_reset_at`

客户端须立即用新 token 覆盖 Keystore 中的旧值。持有旧 token 的其他设备仍可用旧值查询 `/user/binding/occupied`，但不能再用旧值 login。

**错误**

| 状态码 | message |
|---|---|
| 401 | `MISSING_SESSION` / `SESSION_INVALID` / `USER_NOT_FOUND` |

---

### 10. POST /user/devices2user

查询**当前账户**绑定的所有设备（设备管理页）。需有效 session（取 `user_id`）。

含 `active` 与 `unbind_pending`。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex"
}
```

**响应**

```json
{
  "primary_device_id": 5,
  "primary_device_pending_id": null,
  "primary_transfer_requested_at": null,
  "primary_transfer_execute_at": null,
  "devices": [
    {
      "id": 12,
      "device_id": 5,
      "status": "active",
      "is_primary": true,
      "is_primary_pending": false,
      "unbind_requested_at": null,
      "device_display_name": "我的手机",
      "device_name": "Pixel 8 Pro",
      "fingerprint": "sha256hex…",
      "brand": "Google",
      "model": "Pixel 8 Pro",
      "os": "Android 14",
      "memory": "8 GB"
    }
  ]
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `primary_device_id` | number \| null | 当前主设备 id |
| `primary_device_pending_id` | number \| null | 迁移目标主设备；无申请为 `null` |
| `primary_transfer_*` | string \| null | 迁移申请 / 预计生效时间 |
| `id` | number | **绑定记录 id**（改名 / 解绑 / 主设备迁移用这个） |
| `device_id` | number | 设备 id |
| `status` | string | `active` / `unbind_pending` |
| `is_primary` | boolean | 是否当前主设备（不可解绑） |
| `is_primary_pending` | boolean | 是否迁移中的目标主设备 |
| `unbind_requested_at` | string \| null | 申请解绑时间（ISO8601）；未申请为 `null` |
| `device_display_name` | string \| null | 用户自定义显示名 |
| `device_name` | string \| null | 设备原始名 / 型号兜底 |
| `fingerprint` | string \| null | 指纹 hash |
| `brand` / `model` / `os` / `memory` | string \| null | 卡片展示用 |

展示名建议：`device_display_name ?? device_name ?? '未知设备'`。无绑定时：`{ "primary_device_id": …, "devices": [] }`。

**错误**

| 状态码 | message |
|---|---|
| 401 | `MISSING_SESSION` / `SESSION_INVALID` |

---

### 11. POST /user/user2device

查询**当前设备**绑定的所有账户（用户切换页）。需有效 session（取 `device_id`）。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex"
}
```

**响应**

```json
{
  "users": [
    {
      "id": 12,
      "device_id": 5,
      "status": "unbind_pending",
      "unbind_requested_at": "2026-07-18T12:00:00.000Z",
      "user_token": "16位hex",
      "user_display_id": "昵称"
    }
  ]
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | number | 绑定记录 id |
| `device_id` | number | 当前设备 id |
| `status` | string | `active` / `unbind_pending` |
| `unbind_requested_at` | string \| null | 申请解绑时间 |
| `user_token` | string | 切账户时用于 `/user/login`、`binding/create` 或 `session/create` |
| `user_display_id` | string \| null | 显示名 |

无绑定时：`{ "users": [] }`。Session 缺少 `device_id` 时返回 `SESSION_INVALID`。

---

### 12. POST /user/binding/create

建绑本机并**校验现有** `device_secret`；**不**轮换 secret、**不**签发 session。  
适用：本机已有有效 secret（多账户共用），再绑另一用户且不想踢掉现有 secret。

建绑规则与 `login` 相同（`ensureLiveBinding`、transfer、再绑冷却、`device_owner` 校验）。

**请求** `200`

```json
{
  "user_token": "已有账户的 user_token",
  "fingerprint_hash": "当前设备指纹 SHA-256 hex",
  "device_secret": "当前有效的 device_secret"
}
```

**响应**

```json
{
  "binding_id": 12,
  "device_id": 5
}
```

**错误**

| 状态码 | message | 说明 |
|---|---|---|
| 401 | `USER_NOT_FOUND` | |
| 401 | `FINGERPRINT_MISMATCH` | |
| 401 | `DEVICE_NOT_FOUND` | |
| 401 | `DEVICE_SECRET_INVALID` | |
| 400 | `DEVICE_SESSION_LOCKED` | |
| 400 | `REBIND_COOLDOWN` | |
| 400 | `TRANSFER_REQUIRED` | |
| 400 | `TRANSFER_INVALID` | |
| 400 | `用户绑定设备数已达上限` / `设备绑定用户数已达上限` | |

---

### 13. POST /user/binding/occupied

按 `user_token` 查询该用户的 **MySQL 活绑定设备数**（`active` / `unbind_pending`）。  
可用**当前 token** 或 **`user_token_history` 中的旧 token** 定位用户。  
旧 token **不能**用于 `login` / `binding/create` / `session/create`。

**请求** `200`

```json
{
  "user_token": "16位hex"
}
```

**响应**

```json
{
  "device_count": 2
}
```

| 字段 | 说明 |
|---|---|
| `device_count` | 活绑定设备数；`0` 表示未绑定任何设备 |

**错误**

| 状态码 | message |
|---|---|
| 401 | `USER_NOT_FOUND` |

---

### 14. POST /user/binding/last-switch

查询**本机**上次切号时间（读 `session:device_owner`）。需有效 session（用 session 定位 `device_id`）。

同路径别名：`POST /user/session/last-switch`（请求/响应相同）。

无切号锁（从未切号，或锁已过期）时 `switched_at` / `owner_user_id` / `expires_at` 均为 `null`。  
旧格式锁（仅存 user_id、无时间戳）时 `switched_at` 可能为 `null`，但仍返回 `owner_user_id` 与 `expires_at`。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "..."
}
```

**响应**

```json
{
  "switched_at": "2026-07-18T10:00:00.000Z",
  "owner_user_id": 3,
  "expires_at": "2026-07-20T10:00:00.000Z"
}
```

| 字段 | 说明 |
|---|---|
| `switched_at` | 上次切号成功时间 ISO8601；无则 `null` |
| `owner_user_id` | 锁占用的用户；无锁则 `null` |
| `expires_at` | 锁预计过期时间；无锁则 `null` |

**错误**

| 状态码 | message |
|---|---|
| 401 | `MISSING_SESSION` / `SESSION_INVALID` |

---

### 15. POST /user/binding/transfer-request

在**已绑定本机**上发起跨设备绑定转移申请。申请写入 Redis，**15 分钟**有效；期内须在新设备调用 `/user/login` 或 `/user/binding/create` 完成绑定，成功后申请作废（一次性）。

**何时需要**：该用户在其他设备仍有活绑定，且要在**新设备**上首次建立/复活绑定。  
**何时不需要**：新设备上已有该用户活绑定；或用户当前没有任何活绑定。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex"
}
```

Session 须对应本机活绑定（`user_id` + `device_id`）。

**响应**

```json
{
  "from_device_id": 5,
  "expires_in": 900,
  "expires_at": "2026-07-19T06:02:00.000Z"
}
```

| 字段 | 说明 |
|---|---|
| `from_device_id` | 发起申请的本机设备 id |
| `expires_in` | 有效秒数（900 = 15 分钟） |
| `expires_at` | 过期时间 ISO8601 |

**错误**

| 状态码 | message |
|---|---|
| 401 | `DEVICE_NOT_BOUND` / `MISSING_SESSION` / `SESSION_INVALID` |

**推荐流程**

```
旧设备（已绑定）:
  POST /user/binding/transfer-request  → 15 分钟窗口

新设备:
  POST /user/login { user_token, fingerprint_hash }
  → 消耗申请并建立绑定 + 下发新 device_secret
  （或 binding/create 校验旧 secret、不轮换）
  POST /user/session/create → session
```

---

### 16. POST /user/binding/rename

修改绑定设备显示名（写入 `user_device_binding.device_display_name`）。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex",
  "id": 12,
  "new_name": "我的手机"
}
```

| 字段 | 说明 |
|---|---|
| `id` | `devices2user` 返回的绑定 id |
| `new_name` | 新名称，1–100 字符（trim 后不能为空） |

**响应**

```json
{
  "id": 12,
  "device_id": 5,
  "device_display_name": "我的手机"
}
```

成功后建议立刻更新本地列表的 `device_display_name`。

**错误**

| 状态码 | message |
|---|---|
| 400 | `NAME_EMPTY` / `NAME_TOO_LONG` / `NAME_UNCHANGED` |
| 401 | `DEVICE_NOT_BOUND` / `MISSING_SESSION` / `SESSION_INVALID` |

---

### 17. POST /user/binding/delete

| 场景 | 行为 |
|---|---|
| 解绑**主设备**（`device_id` = `users.primary_device_id`） | **禁止**，`PRIMARY_DEVICE_PROTECTED` |
| 解绑**当前登录本机**（非主设备） | **2 小时**等待：`unbind_pending`，到期后 `unbound` |
| 解绑**其他非主设备** | **立刻** `unbound` |

本机等待期内仍可申请 session、仍出现在列表；可用 `delete-cancel` 取消。其他设备立刻解绑后不可 cancel。  
主设备在注册时写入（创建用户时的第一台 `device_id`），不可解绑。

**解绑生效后的踢下线**（立刻 `unbound`，或本机延迟到期正式解绑时）：

- 若目标设备当前 Redis session 属于被解绑用户 → 删除该 session（下次请求 `SESSION_INVALID`）
- 始终清除该设备的 `session:device_owner` 切号锁 → 被踢设备可立即用其他账户登录
- 若该设备当前有 Socket.IO 长连接 → 推送 `binding.unbound` 并断开连接（见 [附录 E](#附录-e-realtime--socketio)）
- pending 等待期内不踢、不清锁、不推送

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex",
  "id": 12
}
```

**响应（本机，延迟）**

```json
{
  "id": 12,
  "device_id": 5,
  "status": "unbind_pending",
  "delayed": true,
  "unbind_requested_at": "2026-07-18T12:00:00.000Z",
  "unbind_execute_at": "2026-07-18T14:00:00.000Z"
}
```

**响应（其他设备，立刻）**

```json
{
  "id": 12,
  "device_id": 8,
  "status": "unbound",
  "delayed": false,
  "unbind_requested_at": "2026-07-18T12:00:00.000Z",
  "unbind_execute_at": "2026-07-18T12:00:00.000Z"
}
```

| 字段 | 说明 |
|---|---|
| `delayed` | `true` 本机等待中；`false` 已立刻解绑 |
| `unbind_requested_at` | 申请 / 解绑时间 |
| `unbind_execute_at` | 本机为预计正式解绑时间（申请 + 2 小时）；立刻解绑时等于申请时间 |

本机延迟解绑会写入 Redis 计时，约每分钟扫描到期项。

**错误**

| 状态码 | message | 说明 |
|---|---|---|
| 400 | `PRIMARY_DEVICE_PROTECTED` | 主设备不可解绑 |
| 400 | `UNBIND_ALREADY_PENDING` | 本机已在解绑等待中 |
| 401 | `DEVICE_NOT_BOUND` | 绑定不存在或不属于当前用户 |
| 401 | `SESSION_INVALID` | session 缺少 `device_id` |

---

### 18. POST /user/binding/delete-cancel

取消**本机**解绑等待（`unbind_pending` → `active`）。立刻解绑的其他设备无需 / 无法 cancel。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "64位hex",
  "id": 12
}
```

**响应**

```json
{
  "id": 12,
  "device_id": 5,
  "status": "active"
}
```

**错误**

| 状态码 | message | 说明 |
|---|---|---|
| 400 | `UNBIND_NOT_PENDING` | 当前没有可取消的解绑申请 |

---

### 19. POST /user/binding/primary-transfer

申请将**主设备**迁移到另一台已绑定设备。申请后 **2 天**生效；期间可 `primary-transfer-cancel`。  
已有主设备时，须在**当前主设备**的 session 上发起。`id` 为目标设备的绑定记录 id。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "...",
  "id": 15
}
```

**响应**

```json
{
  "primary_device_id": 5,
  "primary_device_pending_id": 8,
  "primary_transfer_requested_at": "2026-07-20T00:00:00.000Z",
  "primary_transfer_execute_at": "2026-07-22T00:00:00.000Z"
}
```

**错误**

| 状态码 | message | 说明 |
|---|---|---|
| 400 | `PRIMARY_TRANSFER_ALREADY_PENDING` | 已有未完成的迁移 |
| 400 | `PRIMARY_TRANSFER_REQUIRES_PRIMARY_DEVICE` | 须在主设备上发起 |
| 400 | `ALREADY_PRIMARY_DEVICE` | 目标已是主设备 |
| 401 | `DEVICE_NOT_BOUND` | 目标绑定无效 |
| 401 | `SESSION_INVALID` | |

申请状态仅存 **Redis**（`binding:primary_transfer:{userId}` + 队列），不落 MySQL。到期后若目标仍为活绑定，则更新 `users.primary_device_id`；若目标已解绑则清除申请。

---

### 20. POST /user/binding/primary-transfer-cancel

取消未生效的主设备迁移。已有主设备时须在主设备 session 上取消。

**请求** `200`

```json
{
  "session_id": 1,
  "session_secret": "..."
}
```

**响应**

```json
{
  "primary_device_id": 5,
  "cancelled": true
}
```

**错误**

| 状态码 | message |
|---|---|
| 400 | `PRIMARY_TRANSFER_NOT_PENDING` |
| 400 | `PRIMARY_TRANSFER_REQUIRES_PRIMARY_DEVICE` |

---

## 贴文 API

发帖前须先用 [28. POST /file-processor/upload](#28-post-file-processorupload) 预上传文件，再把返回的 `filename` 填入 `uploaded`。  
创建贴文/回复时：服务端用 session 用户写入 `user_id`，并把 `author` 落库为当前 `user_display_id`（请求体里的 `author` 会被忽略）。  
查询时：**不返回** `user_id`；`author` 规则：

| 条件 | 返回的 `author` |
|---|---|
| `is_anonymous = true` | `null` |
| 有 `user_id` | 该用户**当前** `user_display_id` |
| 无 `user_id`（旧数据） | 落库时的 `author` |

### 21. POST /posts

🔒 创建贴文（含可选图片/附件）。标题+正文会做文本审核。

**请求** `201`（路由未显式设状态码时以实际为准；业务成功返回贴文对象）

```json
{
  "title": "标题",
  "content": "正文可选",
  "is_anonymous": false,
  "category": "问答",
  "uploaded": [
    { "type": "image", "filename": "预上传返回的filename.jpg" },
    { "type": "attachment", "filename": "xxx.txt", "original": "原始名.txt" }
  ],
  "session_id": 1,
  "session_secret": "64位hex"
}
```

| 字段 | 说明 |
|---|---|
| `title` | 必填，最长 255 |
| `content` | 可选 |
| `is_anonymous` | 可选，默认 `false`；为 `true` 时对外 `author` 为 `null` |
| `category` | 可选，`问答` \| `资料` \| `兴趣` \| `梗图`；缺省时先存「默认」，再由 AI 异步分类更新（见下） |

**AI 自动分类**（缺省 `category` 时）：

- 发帖成功后异步调用大模型（默认硅基流动 `Qwen/Qwen2.5-VL-7B-Instruct`，OpenAI 兼容接口）判断品类：纯文本按标题+正文语义；**有图片时发视觉模型识图**（最多 `AI_CLASSIFY_MAX_IMAGES` 张，默认 4）
- 模型返回 JSON `{"category": "..."}`，服务端校验必须落在 `问答/资料/兴趣/梗图/默认` 五值之一，**非法或调用报错一律保持「默认」**
- 分类为异步：发帖响应不等待模型，返回时 `category` 为「默认」，随后自动更新到 MySQL 与 ES 索引（前端可刷新列表看到最终品类）
- 显式传了 `category` 的帖子**不触发** AI 分类，尊重用户选择
- 未配置 `SILICONFLOW_API_KEY` 时跳过 AI 分类，等价于全部「默认」
| `uploaded` | 可选，最多 13 项；图片合计 ≤12 张且总大小 ≤8MB；单附件 ≤3.5MB |
| `uploaded[].type` | `image` \| `attachment` |
| `uploaded[].filename` | 预上传返回的服务端文件名 |
| `uploaded[].original` | 附件建议传原始文件名 |

**响应（公开字段）**

```json
{
  "id": 100,
  "title": "标题",
  "content": "正文",
  "author": "昵称",
  "is_anonymous": false,
  "category": "问答",
  "reply_times": 0,
  "created_at": "...",
  "update_at": "...",
  "images": [],
  "attachments": []
}
```

**错误（节选）**

| 状态码 | 说明 |
|---|---|
| 400 | 文件不存在 / 超限 / 内容审核未通过 |
| 401 | `MISSING_SESSION` / `SESSION_INVALID` |
| 500 | 发布失败 |

---

### 22. POST /posts/comment

🔒 创建回复/评论。

**请求**

```json
{
  "postId": 100,
  "content": "回复内容",
  "is_anonymous": false,
  "session_id": 1,
  "session_secret": "64位hex"
}
```

**响应**

```json
{
  "id": 55,
  "post_id": 100,
  "to_id": null,
  "reply_times": 0,
  "author": "昵称",
  "is_anonymous": false,
  "content": "回复内容",
  "created_at": "..."
}
```

成功后所属贴文的 `reply_times` +1，并刷新 `update_at`。

---

### 23. GET /posts/idList

按条件列出贴文 **id**（仅 id 数组）。带 `search` 时走 Elasticsearch 全文检索。

**Query**

| 参数 | 说明 |
|---|---|
| `search` | 可选，全文检索关键词 |
| `author` | 可选，精确匹配落库 `author` 字符串 |
| `category` | 可选，品类精确匹配（`问答` \| `资料` \| `兴趣` \| `梗图`）；**`默认` 视为不限品类，返回全部**；空字符串视为未传 |
| `dateStart` / `dateEnd` | 可选，ISO 日期，按创建时间区间；**需同时传两个才生效**，只传一个忽略 |
| `offset` | 可选，分页偏移，默认 0 |
| `limit` | 可选，每页条数，上限 200；不传返回全部（无分页） |

不带 `offset` / `limit` 时返回全部 id，向后兼容。所有参数为 **AND** 组合。

**响应**

```json
[120, 119, 118]
```

无结果时为 `[]`。

**`search` 行为（Elasticsearch）**

- 索引名 `posts`；ES 节点地址硬编码在 `src/search/search.module.ts`（`http://localhost:9200`），暂无环境变量
- 检索字段：`title` / `content` / `author`，使用 `multi_match` 查询 + `fuzziness: AUTO`（容忍拼写错误）
- 发帖成功提交后自动写入 ES 索引；历史存量数据需 `syncES` 全量重建（路由 `GET /posts/syncES` 仅 `TEST_MODEL=true` 时开放，否则 404）。重建步骤：带 `TEST_MODEL=true` 重启应用 → `curl 'http://localhost:7300/node/posts/syncES'`（返回 `{message:"同步完成",total,hasErrors}`）→ 恢复正常重启。注意 syncES 只 upsert、不删除，DB 已删帖子的旧文档会残留在 ES（不影响结果，可选清理）
- 与其他条件为 **AND** 关系：先用 ES 得到候选 id 集合，再在 MySQL 叠加 `author` / 时间区间过滤；ES 无命中直接返回 `[]`
- `category` 带 `search` 时在 **ES 层**用 `term` 精确匹配 `category.keyword`（避免拉全量 id 再过滤）；不带 `search` 时在 MySQL 走 `idx_posts_category` 索引等值过滤；`category=默认` 两处均**不加过滤**（视为不限品类）
- 分页（`offset` / `limit`）在 MySQL 侧对最终 id 集合叠加 `skip` / `take`；排序仍为 `created_at` 倒序（MySQL 排序，**非** ES 相关度排序）
- 不带 `search` 时走纯 MySQL 查询

---

### 23b. GET /posts/idListv2

按条件列出贴文**元数据列表**（含分页信息）。查询参数与 [23. GET /posts/idList](#23-get-postsidlist) 完全一致（`search` / `author` / `category` / `dateStart` / `dateEnd` / `offset` / `limit`），组合逻辑相同（AND、`category=默认` 不限品类、ES/MySQL 双路径）。区别仅在返回结构：**v1 返回纯 id 数组，v2 返回对象列表 + total**。

**响应**

```json
{
  "total": 342,
  "offset": 0,
  "limit": 20,
  "items": [
    {
      "id": 100,
      "title": "标题",
      "author": "昵称或null（匿名）",
      "category": "问答",
      "reply_times": 2,
      "created_at": "2026-08-16T08:00:00.000Z",
      "update_at": "2026-08-16T08:00:00.000Z"
    }
  ]
}
```

- `total`：**分页前的完整命中数**（前端分页/展示总量用）
- `offset` / `limit`：回显请求值；未传 `limit` 时为 `null`（返回全部）
- 排序固定 `created_at` 倒序（与 v1 一致）；前端可用 `created_at` / `update_at` 自行排序
- **不返回 `user_id`**（隐私：匿名帖不泄露发帖人身份）

---

### 24. POST /posts/idListUpdate

批量查询贴文的 `update_at`（用于客户端增量刷新）。

**请求**：JSON 数组

```json
[100, 101, 102]
```

**响应**

```json
{
  "100": "2026-07-20T10:00:00.000Z",
  "101": "2026-07-19T08:00:00.000Z"
}
```

空数组 → `{}`。

---

### 25. GET /posts/idListByAuthor/:author

按落库 `author` 字符串查贴文列表（含 `id` / `title` / `update_at` / `category`）。

**响应**

```json
[
  { "id": 100, "title": "标题", "update_at": "...", "category": "默认" }
]
```

---

### 26. GET /posts/:id

获取单帖详情（含图片、附件；`comments` 为评论 id 列表）。

**响应示例**

```json
{
  "id": 100,
  "title": "标题",
  "content": "正文",
  "author": "当前显示名或null",
  "is_anonymous": false,
  "category": "默认",
  "reply_times": 2,
  "created_at": "...",
  "update_at": "...",
  "images": [
    { "id": 1, "post_id": 100, "file_name": "xxx.jpg", "created_at": "..." }
  ],
  "attachments": [
    {
      "id": 1,
      "post_id": 100,
      "file_name": "xxx.txt",
      "source_name": "原始名.txt",
      "created_at": "..."
    }
  ],
  "comments": [55, 56]
}
```

不返回贴文/图片/附件上的 `user_id`。

---

### 27. GET /posts/comment/:id

获取单条评论（作者规则同贴文）。

**响应**

```json
{
  "id": 55,
  "post_id": 100,
  "to_id": null,
  "reply_times": 0,
  "author": "当前显示名或null",
  "is_anonymous": false,
  "content": "内容",
  "created_at": "..."
}
```

---

## 文件 API

### 28. POST /file-processor/upload

🔒 **multipart/form-data** 预上传。字段名 `file`；另附 `session_id`、`session_secret`，可选 `type`=`image`|`attachment`。

限制：总大小硬上限 **8MB**；`type=image` 建议 ≤8MB，`attachment` ≤3.5MB。图片会做内容审核。允许扩展名包括常见图片与文本/代码等（见服务端白名单）。

**响应**

```json
{
  "status": "success",
  "message": "文件xxx预存入完成",
  "originalName": "原名.jpg",
  "filename": "服务端生成文件名.jpg"
}
```

发帖时把 `filename` 填入 `uploaded[].filename`。

---

### 29. GET /file-processor/convert/:variant/\*path

将 `/var/www/img/` 下原图裁剪缩放并转为 WebP（带缓存）。当前仅支持 `variant=2webp`。

**示例**

```text
GET /node/file-processor/convert/2webp/photo/1.png
```

成功直接返回 **WebP 文件字节**（非 JSON）。原图不存在 → 404；不支持的 variant → 400。

---

## 版本 API

### 30. GET /versions/latest

获取最新版本记录。可选 query：`platform`。

**响应**（单条实体，字段为 camelCase）

```json
{
  "id": 1,
  "versionNumber": "1.2.0",
  "platform": "android",
  "title": "更新标题",
  "log": "更新日志",
  "description": "描述",
  "downloadUrl": "https://...",
  "releaseDate": "..."
}
```

---

### 31. GET /versions

获取版本列表（新→旧）。可选 query：`platform`。

**响应**：上表对象的数组。

---

## 其它

### 32. GET /

健康检查 / 占位。

**响应**：`Hello World!`（文本）

---

## 绑定状态说明

绑定**只**在 `/user/login` 或 `/user/binding/create` 时创建或复活；**只**在 `/user/binding/delete`（及到期正式解绑）时删除。`/user/register` 不建绑。

| status | 含义 |
|---|---|
| `active` | 正常绑定 |
| `unbind_pending` | **当前登录本机**解绑等待中（**2 小时**）；期间仍可申请 session |
| `unbound` | 已解绑；不出现在列表；`TEST_MODEL=false` 时 2 天内不可通过 login / binding/create 再绑定同一对 |

主设备：`users.primary_device_id`（注册时第一台设备），**不可解绑**；可通过 `binding/primary-transfer` 申请迁移（2 天后生效，期间可取消）。

限额：每用户最多 5 台设备，每设备最多 3 个用户（`active` + `unbind_pending` 计入）。

| 规则 | 是否受 `TEST_MODEL` 影响 |
|---|---|
| 主设备不可解绑 | **否** |
| **本机** `binding/delete` → 等待 **2 小时**再 `unbound` | **否** |
| **其他非主设备** `binding/delete` → 立刻 `unbound` | 不适用 |
| `unbound` 后再 login / binding/create 的再绑定冷却（2 天） | **是**：`true` 关闭 / `false` 开启 |
| 切号后 `session:device_owner` 锁（2 天） | **否** |

在 `.env` 中配置再绑定冷却，例如测试：`TEST_MODEL=true`；正式：`TEST_MODEL=false`。修改后需重启服务。

---

## login / binding/create / session/create 对比

| | `POST /user/login` | `POST /user/binding/create` | `POST /user/session/create` |
|---|---|---|---|
| 用途 | 建绑 + 轮换 secret | 建绑 + 校验旧 secret | 拿 session / 切号 |
| 请求 | `user_token` + `fingerprint_hash` | + `device_secret` | `user_token` + `device_secret` + `fingerprint_hash` |
| 建绑 | 是 | 是 | 否（须已绑定） |
| 轮换 secret | **是** | **否** | 否 |
| 签发 session | 否 | 否 | **是** |
| `device_owner` 异用户锁 | 拒绝 | 拒绝 | 拒绝；切号成功则写入 2 天锁 |

注意：`login` 会改写该设备的 `device_secret_hash`，本机其他账户若仍用旧 secret 调 `session/create` / `binding/create` 会失败，需改用最新 secret 或再 `login`。

---

## 附录 A: 设备指纹结构

### 顶层

```typescript
{
  platform: "android" | "ios",
  android?: AndroidFingerprint,   // platform=android 时必填
  ios?: IosFingerprint            // 暂不支持
}
```

### AndroidFingerprint

| 分组 | 字段 | 类型 |
|---|---|---|
| `build` | `board` `bootloader` `brand` `device` `display` `fingerprint` `hardware` `host` `id` `manufacturer` `model` `product` `name` `tags` `type` | `string` |
| `version` | `baseOS?` `codename` `incremental` `release` `securityPatch?` | `string` |
| | `previewSdkInt?` `sdkInt` | `number` |
| `abi` | `supported32BitAbis` `supported64BitAbis` `supportedAbis` | `string[]` |
| `hardware` | `isPhysicalDevice` `isLowRamDevice` | `boolean` |
| | `freeDiskSize` `totalDiskSize` `physicalRamSize` `availableRamSize` | `number` |
| | `serialNumber` `systemFeatures` | `string` / `string[]` |

所有字段由客户端通过 `device_info_plus` 采集后原样提交，不要自行计算 hash。

### 示例

```json
{
  "platform": "android",
  "android": {
    "build": {
      "board": "kalama",
      "brand": "google",
      "device": "husky",
      "model": "Pixel 8 Pro",
      "manufacturer": "Google",
      "product": "husky",
      "fingerprint": "google/husky/husky:14/...",
      "hardware": "qcom",
      "host": "abfarm",
      "id": "AP2A.240605.024",
      "name": "husky",
      "type": "user",
      "tags": "release-keys",
      "bootloader": "gki",
      "display": "AP2A.240605.024"
    },
    "version": {
      "baseOS": "android",
      "codename": "REL",
      "incremental": "1234567",
      "release": "14",
      "sdkInt": 34,
      "securityPatch": "2024-06-05"
    },
    "abi": {
      "supported32BitAbis": [],
      "supported64BitAbis": ["arm64-v8a"],
      "supportedAbis": ["arm64-v8a"]
    },
    "hardware": {
      "isPhysicalDevice": true,
      "isLowRamDevice": false,
      "freeDiskSize": 100000000000,
      "totalDiskSize": 128000000000,
      "physicalRamSize": 12000000000,
      "availableRamSize": 5000000000,
      "serialNumber": "unknown",
      "systemFeatures": ["android.hardware.camera"]
    }
  }
}
```

---

## 附录 B: fingerprint_hash 计算方法

服务端计算，客户端不需要实现。

### 算法

```
fingerprint_hash = SHA-256(values.join('|'))
```

### 参与字段（Android）

```
build_board
build_bootloader
build_brand
build_device
build_hardware
build_host
build_manufacturer
build_model
build_product
build_tags
build_type
abi_supported_abis           → 数组 sort 后用 ',' join
abi_supported_32bit          → 数组 sort 后用 ',' join
abi_supported_64bit          → 数组 sort 后用 ',' join
hw_is_physical_device
hw_is_low_ram_device
hw_physical_ram_size
hw_total_disk_size
hw_serial_number             → 为 null / "unknown" / 空字符串时跳过
hw_system_features           → 数组 sort 后用 ',' join
```

### 伪代码

```
input = [
  build_board, build_bootloader, build_brand, build_device,
  build_hardware, build_host, build_manufacturer, build_model,
  build_product, build_tags, build_type,
  abi_supported_abis.sort().join(','),
  abi_supported_32bit.sort().join(','),
  abi_supported_64bit.sort().join(','),
  hw_is_physical_device,
  hw_is_low_ram_device,
  hw_physical_ram_size,
  hw_total_disk_size,
  // hw_serial_number 仅当非空且非 "unknown" 时加入
  hw_system_features.sort().join(','),
]

return SHA-256(input.join('|'))
```

所有值转为字符串（`null` / `undefined` → `""`），用 `|` 拼接，最终对拼接结果取 SHA-256。

### 参与字段（iOS，暂不支持注册）

```
ios_model, ios_model_name, ios_system_name, ios_localized_model,
ios_is_physical_device, ios_is_ios_app_on_mac, ios_identifier_for_vendor,
ios_physical_ram_size, ios_total_disk_size,
ios_sysname, ios_machine, ios_nodename
```

---

## 附录 C: 注册 / 登录流程

**新设备首次注册**

```
1. GET  /user/pow-challenge     → challenge_id, challenge
2. 计算 PoW nonce + 获取 Turnstile token
3. POST /user/check             → { registered: false }
4. POST /user/register          → user_token, device_secret（此时尚无绑定）
5. 保存 user_token, device_secret 到 Keystore/Keychain
6. POST /user/login { user_token, fingerprint_hash }
   → 创建绑定 + 新 device_secret（不签发 session）
7. 用 login 返回的 device_secret 覆盖本地旧值
8. POST /user/session/create    → session_id, session_secret
```

绑定生命周期：**仅** `/user/login` 或 `/user/binding/create` 创建（或复活）；**仅** `/user/binding/delete` 删除（主设备禁止 / 本机 2 小时 / 他机立刻）。

**已有账户登录到新设备（跨设备绑定）**

```
1. 旧设备 POST /user/binding/transfer-request  → 15 分钟窗口
2. 新设备 POST /user/login
   body: { user_token, fingerprint_hash }
   → 新 device_secret + binding
3. POST /user/session/create → session
```

超时未建绑 → `TRANSFER_REQUIRED`。本机已有该用户绑定则跳过步骤 1。  
新设备若已有有效 `device_secret`，可用 `binding/create` 代替 `login`（不轮换 secret）。

**本机已绑定账户再次 login（轮换 secret）**

```
1. POST /user/login { user_token, fingerprint_hash }
2. 保存新 device_secret
3. 需要 session 时再 POST /user/session/create
```

`TEST_MODEL=false` 且该 user↔device 在 2 天内刚 `unbound`、且无其他活绑定时，可能 `REBIND_COOLDOWN`。

**本机已有 secret，再绑另一账户（不轮换）**

```
1. （若跨设备）transfer-request
2. POST /user/binding/create { user_token, fingerprint_hash, device_secret }
3. POST /user/session/create（受 device_owner 切号锁约束）
```

**日常启动（已有绑定 + 本地已有 device_secret）**

```
1. POST /user/session/create    → session_id, session_secret
2. 后续请求带上 session_id + session_secret
```

若本地 secret 已因他人 `login` 轮换而失效 → 改走 `/user/login` 拿新 secret。

**手机号验证码注册 / 登录（推荐 iOS / 简化流程）**

```
注册：
1. POST /user/sms/send { phone, scene: 'register' }
2. 输入短信验证码
3. POST /user/sms/register { phone, code, user_display_id, device_finger_print, verification_captcha, pow }
   → user_token + device_secret（已同时建绑）
4. POST /user/session/create → session

登录：
1. POST /user/sms/send { phone, scene: 'login' }
2. 输入短信验证码
3. POST /user/sms/login { phone, code, fingerprint_hash }
   → session_id + session_secret + user_token
```

iOS 下同一指纹可注册多个用户；登录时通过 `(user_id, fingerprint_hash)` 定位该用户的设备。

**设备管理**

```
devices2user
  → binding/rename（立刻改 device_display_name）
  → binding/delete（主设备禁止；本机 2 小时；其他非主设备立刻 unbound）
  → binding/delete-cancel（仅取消本机 pending）
```

**用户切换（同一设备换账户）**

```
user2device → 取目标账户 user_token
  → 若本机尚无该账户绑定：login 或 binding/create（受 device_owner 约束）
  → POST /user/session/create（切号成功则写 2 天锁；锁期内不可再切异用户）
```

---

## 附录 D: Session 使用

受保护接口（发帖、上传、profile、绑定等）通过 `SessionGuard` 校验，请求 body 需附带（或 header `x-session-id` / `x-session-secret`）：

```json
{
  "session_id": 1,
  "session_secret": "...",
  "...": "其他业务字段"
}
```

Session 有效期 **3 天**，存 Redis：

| Key | Value |
|---|---|
| `session:{session_id}` | JSON：`{ session_secret_hash, user_id, device_id }` |
| `session:by_device:{device_id}` | 本机当前 `session_id`（同 TTL；新签发踢旧） |
| `session:device_owner:{device_id}` | JSON：`{ user_id, switched_at }`，TTL **2 天**（仅切号成功时写入；同用户续签不刷新） |

同一设备新签发 session 时会删除本机旧 `session:{id}`（一设备一有效 session）；同一用户可在多台设备同时有 session。  
同一用户/设备 24 小时内最多申请 **8** 次 session（防刷；仅 `session/create` 计入）。

映射约定：

- `devices2user` → 账户 → 设备列表（设备绑定页）
- `user2device` → 设备 → 账户列表（用户切换页）

通用 session 错误：`MISSING_SESSION` / `SESSION_INVALID`。

---

## 附录 E: Realtime / Socket.IO

与 HTTP **同端口**，用 Socket.IO 长连接接收服务端推送（解绑、本机旧 session 被顶掉）。对外若已 HTTPS 反代，客户端用 `https://` 即可走 WSS；Nest 本身仍明文监听，TLS 在反代终结。

### 连接

| 项 | 值 |
|---|---|
| URL | 与 API 同源：`https://<host>` 或直连 `http://<host>:7300` |
| path | `/node/socket.io`（与 `GLOBAL_PREFIX=node` 对齐） |
| 鉴权 | 握手 `auth`（推荐）或 query：`session_id` + `session_secret` |

```js
io('https://<host>', {
  path: '/node/socket.io',
  auth: { session_id: 1, session_secret: '...' },
});
```

成功后服务端校验 session（同 `session/validate`），连接加入房间 `device:{device_id}`（并 `user:{user_id}`）。鉴权失败则立即断开。

客户端应在 `session/create` 成功后 connect；主动登出或 session 失效后 disconnect。断线自动重连仅在仍持有有效 session 时开启。

### 服务端 → 客户端事件

#### `binding.unbound`

解绑踢 Redis session 之后推送（他机立刻解绑，或本机 2 小时到期）。payload：

```json
{
  "event": "binding.unbound",
  "user_id": 1,
  "device_id": 8,
  "binding_id": 12,
  "reason": "remote_unbind",
  "at": "2026-07-20T01:00:00.000Z",
  "actor_device_id": 5,
  "actor_device_display_name": "家里的手机",
  "actor_device_name": "Pixel 8 Pro",
  "actor_ip": "203.0.113.10",
  "actor_brand": "Google",
  "actor_model": "Pixel 8 Pro"
}
```

| 字段 | 含义 |
|---|---|
| `actor_device_id` | 发起解绑的设备 |
| `actor_device_display_name` | 该设备在本账户下的备注名 |
| `actor_device_name` | 设备名（无则回退型号） |
| `actor_ip` | 发起解绑时的请求 IP（反代后一般为真实客户端 IP） |
| `actor_brand` / `actor_model` | 来自该设备指纹 |

| `reason` | 含义 |
|---|---|
| `remote_unbind` | 他机立刻解绑 |
| `local_unbind_due` | 本机解绑等待期到期 |

推送后服务端会断开该设备上属于同一 `user_id` 的连接。

#### `session.invalidated`

本机再次 `session/create`（同用户续签或切号）顶掉旧 session 时推送：

```json
{
  "event": "session.invalidated",
  "user_id": 1,
  "device_id": 8,
  "reason": "replaced",
  "at": "2026-07-20T01:00:00.000Z"
}
```

| `reason` | 含义 |
|---|---|
| `replaced` | 本机新签发 session，旧凭证作废 |

推送后断开该设备上属于**旧** `user_id` 的连接。客户端清掉旧 session；若刚拿到新 session，用新凭证重新 connect。

### 客户端处理

1. 收到 `binding.unbound` → 清该账户本地 session，退回登录 / 账户列表。
2. 收到 `session.invalidated` → 清**旧** session；本机若已切到新账户，用**新**凭证重连 WS。
3. **不要只靠 WS**：离线时解绑/顶号只删 Redis；下次受保护 HTTP 仍会 `SESSION_INVALID`，须同样退出。
4. 离线设备无连接时推送为 no-op；靠 Redis 已删 session 兜底。

### 联调最小步骤

1. 设备：`session/create` → 连 WS。
2. 他机解绑该绑定 → 应收到 `binding.unbound` 并断连。
3. 同设备再 `session/create` → 旧连接应收到 `session.invalidated` 并断连；用新 session 再 connect。

### 连通性测试（`test.tick`）

连接鉴权成功后，向服务端 emit `test.start`，即可每秒收到递增数字；emit `test.stop` 或断连时停止。

```js
socket.on('connect', () => {
  socket.emit('test.start');
});

socket.on('test.tick', (payload) => {
  console.log(payload.n); // 1, 2, 3, ...
});

// 停止：socket.emit('test.stop');
```

payload 示例：

```json
{
  "event": "test.tick",
  "n": 3,
  "at": "2026-07-20T02:00:02.000Z"
}
```

### 多实例

当前按单进程内存房间实现。若以后 PM2 cluster / 多机，需加 `@socket.io/redis-adapter`；业务侧已集中在 `RealtimeService`，便于替换。

---

## 附录 F: 阿里云验证码 2.0

### 1. 功能与触发时机

阿里云验证码 2.0（无痕验证 / 智能验证）用于 `POST /user/registerV2`，替代 v1 的 Cloudflare Turnstile。

- 客户端接入阿里云验证码 2.0 SDK 获取 `captchaVerifyParam`。
- 注册时把该参数原样放在 `verification_captcha` 字段提交。
- 服务端通过 `CaptchaStrategy` 向阿里云 `VerifyIntelligentCaptcha` 接口二次校验。
- 校验通过后再校验 PoW，最后执行与 v1 相同的建号逻辑。

### 2. 环境变量

| 变量 | 必填 | 说明 |
|---|---|---|
| `ALIBABA_CLOUD_ACCESS_KEY_ID` | 是 | 阿里云 RAM 子账号 AccessKey ID |
| `ALIBABA_CLOUD_ACCESS_KEY_SECRET` | 是 | 阿里云 RAM 子账号 AccessKey Secret |
| `CAPTCHA_SCENE_ID` | 是 | 验证码 2.0 控制台创建的场景 ID |
| `CAPTCHA_ENDPOINT` | 否 | 默认 `captcha.cn-shanghai.aliyuncs.com` |

### 3. 阿里云控制台配置

1. 进入 [阿里云验证码 2.0 控制台](https://captcha.console.aliyun.com/)。
2. 创建场景：
   - 场景类型选择「无痕验证」或「智能验证」。
   - 记录场景 ID，填入 `CAPTCHA_SCENE_ID`。
3. 按客户端平台（Web / iOS / Android）接入官方 SDK，调用 `getToken()` 或等价方法拿到 `captchaVerifyParam`。
4. 在 RAM 控制台给子账号授权：至少包含 `captcha:VerifyIntelligentCaptcha` 权限。

### 4. 关键文件

| 路径 | 说明 |
|---|---|
| `src/user/verification/captcha.strategy.ts` | 核心策略类 |
| `src/user/verification/verification.service.ts` | 按 `method` 路由到具体策略 |
| `src/user/user.service.login.ts` | `registerV2` 业务入口 |
| `src/user/user.controller.ts` | `POST /user/registerV2` 路由 |
| `src/user/dto/register-v2.dto.ts` | DTO |

### 5. 特殊行为

- `captchaVerifyParam` **必须原样透传**，禁止修改。
- token **一次性**：复用或过期返回 `F008`；服务端**不缓存**，注册失败后客户端必须重新获取。
- 服务端**不调用 consume**：token 由阿里云侧一次性消费，注册成功只需 consume PoW。
- 缺配置时返回 `400 验证码服务未配置`；调用异常时返回 `400 验证码服务异常，请重试`，不会绕过验证。

| 阿里云 verifyCode | 返回给客户端 |
|---|---|
| `F008` | `验证码已使用或过期，请重新验证` |
| `F010` | `访问过于频繁，请稍后重试` |
| `F012` | `场景配置错误，请稍后重试` |
| 其他 | `验证码校验失败，请重试` |

---

## 附录 G: LLM 二次内容审核

### 1. 功能与触发时机

在阿里云内容审核（绿网）之后，增加一层 LLM 二次审核，用于发现规则引擎可能漏掉的违规内容。

触发接口：

- `POST /posts`：审核帖子标题 + 正文。
- `POST /file-processor/upload`（`type=image`）：审核上传图片。

`ModerationService` 内部固定顺序：

```text
阿里云审核 → 若未通过直接拦截
        ↓ 通过
LLM 二次审核 → 若未通过拦截
        ↓ 通过
放行（合并低置信度标签）
```

> 当前 `POST /posts/comment`（回复）**未**调用内容审核。

### 2. 环境变量

| 变量 | 必填 | 默认值 | 说明 |
|---|---|---|---|
| `SILICONFLOW_API_KEY` | 条件 | — | 若未单独配 `LLM_MODERATION_API_KEY`，则复用此 key |
| `LLM_MODERATION_ENABLED` | 否 | `true`（依赖 key 存在） | 显式 `false` 关闭 |
| `LLM_MODERATION_API_KEY` | 否 | 复用 `SILICONFLOW_API_KEY` | 审核专用 key |
| `LLM_MODERATION_BASE_URL` | 否 | `https://api.siliconflow.cn/v1` | 服务端点 |
| `LLM_MODERATION_TEXT_MODEL` | 否 | `Qwen/Qwen2.5-7B-Instruct` | 文本审核模型 |
| `LLM_MODERATION_IMAGE_MODEL` | 否 | `Qwen/Qwen3-VL-8B-Instruct` | 图片审核模型（需视觉能力） |
| `LLM_MODERATION_TIMEOUT_MS` | 否 | `15000` | 单次调用超时（毫秒） |

### 3. 服务侧配置

1. 在 [SiliconFlow 控制台](https://cloud.siliconflow.cn/) 创建 API Key，或切换到任意 OpenAI 兼容服务端点。
2. 所选模型需支持 `response_format: { type: 'json_object' }`。
3. 图片模型需为视觉模型。
4. 阿里云绿网侧仍需正常配置，因为 `ModerationService` 先走阿里云再走 LLM。

### 4. 关键文件

| 路径 | 说明 |
|---|---|
| `src/moderation/llm-moderation.service.ts` | LLM 审核核心服务 |
| `src/moderation/moderation.service.ts` | 组合阿里云 + LLM 审核 |
| `src/moderation/moderation.config.ts` | 阿里云审核阈值与拦截标签配置 |
| `src/moderation/moderation.types.ts` | 结果类型定义 |
| `src/posts/posts.service.ts` | 发帖文本审核调用点 |
| `src/file-processor/file-processor.service.ts` | 图片上传审核调用点 |

### 5. 提示词与返回格式

**文本审核**

系统提示词要求模型只输出 JSON：

```json
{"passed": true/false, "reason": "原因（中文）", "labels": ["违规标签"]}
```

**图片审核**

用户消息包含文字指令 + `image_url`，输出格式同文本。

**调用参数**

```json
{
  "model": "...",
  "messages": [...],
  "temperature": 0,
  "max_tokens": 256,
  "response_format": { "type": "json_object" }
}
```

### 6. 特殊行为与兜底

- **异常默认放行**：网络、超时、解析失败、服务不可用均视为 `passed: true`，不会阻塞业务。
- **未启用时放行**：缺少 API key 或 `LLM_MODERATION_ENABLED=false` 直接返回 `{ passed: true }`。
- **空内容放行**：空字符串文本不调用模型。
- **超大图跳过**：图片超过 2MB 时跳过 LLM 审核（控制成本）。
- **标签合并**：若阿里云与 LLM 都放行但存在低置信度标签，`ModerationService.combineResults()` 合并去重，仍放行但保留记录。
- **LLM 拦截信息**：`labels` 置信度固定为 `100`，`reason` 使用模型返回的中文原因。

---

## 附录 H: 阿里云短信认证服务

手机号登录/注册/换绑使用阿里云「号码认证服务 - 短信认证」（产品 `Dypnsapi`，接口 `SendSmsVerifyCode` / `CheckSmsVerifyCode`），而非独立短信服务（`Dysmsapi` / `SendSms`）。

### 1. 与短信服务（Dysmsapi）的区别

| 维度 | 短信认证服务（Dypnsapi） | 短信服务（Dysmsapi） |
|---|---|---|
| 产品入口 | [号码认证服务控制台](https://dypns.console.aliyun.com/) | [短信服务控制台](https://dysms.console.aliyun.com/) |
| 下发接口 | `SendSmsVerifyCode` | `SendSms` |
| 验证码生成 | 阿里云自动生成 | 业务侧生成 |
| 验证码存储/校验 | 阿里云负责 | 业务侧存储到 Redis 后自行校验 |
| 签名/模板 | 可使用系统赠送签名/模板，无需审核 | 必须自行申请签名和模板并审核 |
| 适用场景 | 手机号验证、登录 | 营销/通知/自定义模板短信 |

### 2. 环境变量

| 变量 | 必填 | 说明 |
|---|---|---|
| `ALIBABA_CLOUD_ACCESS_KEY_ID` | 是 | 阿里云 RAM 子账号 AccessKey ID |
| `ALIBABA_CLOUD_ACCESS_KEY_SECRET` | 是 | 阿里云 RAM 子账号 AccessKey Secret |
| `SMS_SIGN_NAME` | 是 | 短信签名；也可使用号码认证服务赠送签名 |
| `SMS_TEMPLATE_CODE` | 是 | 通用模板 CODE；未配置场景模板时回退使用 |
| `SMS_TEMPLATE_CODE_REGISTER` | 否 | 注册场景模板 CODE |
| `SMS_TEMPLATE_CODE_LOGIN` | 否 | 登录场景模板 CODE |
| `SMS_TEMPLATE_CODE_BIND` | 否 | 换绑场景模板 CODE |
| `SMS_ENDPOINT` | 否 | 默认 `dypnsapi.aliyuncs.com` |
| `SMS_VALID_TIME_S` | 否 | 验证码有效期（秒），默认 600 |
| `SMS_CODE_LENGTH` | 否 | 验证码位数，默认 6 |

### 3. 阿里云控制台配置

1. 进入 [号码认证服务控制台](https://dypns.console.aliyun.com/)。
2. 开通「短信认证」能力。
3. 在「短信认证参数配置」页面查看：
   - **赠送签名**：系统预置，可直接使用。
   - **赠送模板**：系统提供 5 个固定模板，CODE 分别为 `100001`（登录/注册）、`100002`（修改绑定手机号）、`100003`（重置密码）、`100004`（绑定新手机号）、`100005`（验证绑定手机号）。
4. 把赠送签名名称填入 `SMS_SIGN_NAME`，把对应模板 CODE 填入 `SMS_TEMPLATE_CODE_*`。
5. 为 RAM 子账号授权 `AliyunDypnsFullAccess`。

> 系统赠送签名必须搭配系统赠送模板使用；自定义签名/模板需要单独申请资质并审核。
>
> **占位符规范（实测确认）**：`templateParam` 中验证码以 `##code##` 占位
> （SDK 文档原文："The verification code is replaced with ##code##"），发送时由
> 阿里云替换为生成的验证码。注意不是 `${code}`——后者会被变量内容校验拒绝
>（报「模版变量code内容非法」）。赠送模板 100001 含 code/min 两个变量，
> 必须成对提供，缺任一会报「模板内容与模板参数是否匹配」/「xx内容非法」。

### 4. 关键文件

| 路径 | 说明 |
|---|---|
| `src/user/sms/aliyun-sms.sender.ts` | 阿里云短信认证发送/校验实现 |
| `src/user/sms/mock-sms.sender.ts` | 本地 Mock 实现（开发/测试） |
| `src/user/sms/sms.service.ts` | 业务层频率限制 + 错误码映射 |
| `src/user/user.module.ts` | `SMS_SENDER` 注入配置 |

### 5. 模板变量

调用 `SendSmsVerifyCode` 时，`templateParam` 固定传：

```json
{"code":"##code##"}
```

阿里云会自动把 `##code##` 替换为真实验证码。业务侧不再自己生成验证码。

### 6. 校验说明

`CheckSmsVerifyCode` 返回 `model.verifyResult`：

- `PASS`：校验通过。
- `UNKNOWN`：校验失败（验证码错误、过期、次数超限等）。

业务侧统一映射为 `SMS_CODE_INVALID` / `SMS_CODE_EXPIRED` / `SMS_CODE_ATTEMPTS_EXCEEDED`。

### 7. 开发/测试

若不想对接阿里云或暂无套餐包，可把 `src/user/user.module.ts` 中的 `SMS_SENDER` 改为 `MockSmsAuthSender`：

```ts
{
  provide: SMS_SENDER,
  useClass: MockSmsAuthSender,
}
```

验证码会打印在日志中，并存储在 Redis `sms:code:mock:{phone}:{scene}` 里。

---

## 环境变量

| 变量 | 说明 |
|---|---|
| `PORT` | 服务端口，默认 7300 |
| `GLOBAL_PREFIX` | 路由前缀，默认 `node` |
| `TEST_MODEL` | 仅控制「`unbound` 后再 login / binding/create」冷却：`true` 关闭 / `false` 开启。**不影响主设备保护、本机解绑 2 小时等待、切号锁** |
| `DB_HOST/PORT/NAME/USERNAME/PASSWORD` | MySQL 连接 |
| `REDIS_HOST/PORT/PASSWORD` | Redis 连接 |
| `TURNSTILE_SECRET_KEY` | Cloudflare Turnstile（v1 `register` 用） |
| `ALIBABA_CLOUD_ACCESS_KEY_ID` / `ALIBABA_CLOUD_ACCESS_KEY_SECRET` | 阿里云 AK/SK（内容审核与验证码 2.0 共用；RAM 子账号需授予对应权限） |
| `CAPTCHA_SCENE_ID` | 阿里云验证码 2.0 场景 ID（控制台「无痕验证」场景；`registerV2` 必填） |
| `CAPTCHA_ENDPOINT` | 可选，默认 `captcha.cn-shanghai.aliyuncs.com`（中国内地） |
| `SMS_SIGN_NAME` | 阿里云短信签名（手机号登录/注册/换绑用） |
| `SMS_TEMPLATE_CODE` | 通用短信模板 CODE；未配置场景模板时回退使用 |
| `SMS_TEMPLATE_CODE_REGISTER` | 可选，注册场景模板 CODE |
| `SMS_TEMPLATE_CODE_LOGIN` | 可选，登录场景模板 CODE |
| `SMS_TEMPLATE_CODE_BIND` | 可选，换绑场景模板 CODE |
| `SMS_ENDPOINT` | 可选，默认 `dypnsapi.aliyuncs.com` |
| `SMS_VALID_TIME_S` | 验证码有效期（秒），默认 600 |
| `SMS_CODE_LENGTH` | 验证码位数，默认 6 |
| `DEVICE_SECRET_HASH_KEY` | bcrypt pepper，用于 `device_secret` 加盐哈希 |
| `SILICONFLOW_API_KEY` | 硅基流动 API key（发帖 AI 自动分类用）；**不配置则跳过 AI 分类**，发帖默认「默认」 |
| `SILICONFLOW_BASE_URL` | 可选，默认 `https://api.siliconflow.cn/v1` |
| `SILICONFLOW_MODEL` | 可选，默认 `Qwen/Qwen2.5-VL-7B-Instruct`（支持识图，~0.15 元/百万 token 输入） |
| `AI_CLASSIFY_MAX_IMAGES` | 可选，发视觉模型的图片数上限，默认 4（控制成本） |
| `LLM_MODERATION_ENABLED` | 是否启用 LLM 二次审核，默认 `true`（依赖 key 存在才启用）；显式 `false` 关闭 |
| `LLM_MODERATION_API_KEY` | LLM 审核 API key，默认复用 `SILICONFLOW_API_KEY` |
| `LLM_MODERATION_BASE_URL` | 可选，默认 `https://api.siliconflow.cn/v1` |
| `LLM_MODERATION_TEXT_MODEL` | 文本审核模型，默认 `Qwen/Qwen2.5-7B-Instruct` |
| `LLM_MODERATION_IMAGE_MODEL` | 图片审核模型，默认 `Qwen/Qwen3-VL-8B-Instruct` |
| `LLM_MODERATION_TIMEOUT_MS` | LLM 审核超时（毫秒），默认 `15000` |
| `LOG_DIR` | 日志文件目录，默认 `/var/www/logs` |
| `LOG_FILE` | 日志文件名，默认 `treehole-nest.log` |

`.env` 示例（测试）：

```env
TEST_MODEL=true
```

正式环境请设 `TEST_MODEL=false`（或不设为 `true`）。

Elasticsearch 节点地址暂**硬编码**在 `src/search/search.module.ts`（`http://localhost:9200`），未提供环境变量；本地需自行启动 ES 供全文搜索使用（见 [23. GET /posts/idList](#23-get-postsidlist)）。

---

## 数据库迁移

开发过程中 schema 有变更，需手动执行 `database/migrations/` 下脚本，例如：

```sql
-- 曾签发的全部 user_token（注册/重置时写入，全局唯一）
-- 见 database/migrations/20260719_create_user_token_history.sql
-- 需 GRANT SELECT, INSERT ON <DB>.user_token_history TO '<db_user>'@'localhost';
CREATE TABLE user_token_history (
  id INT NOT NULL AUTO_INCREMENT,
  user_id INT NOT NULL,
  user_token VARCHAR(128) NOT NULL,
  archived_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_user_token_history_token (user_token),
  KEY idx_user_token_history_user_id (user_id)
);

-- user_token 重置时间
-- 见 database/migrations/20260718_add_user_token_reset_at.sql

-- 绑定自定义显示名
ALTER TABLE user_device_binding
  ADD COLUMN device_display_name VARCHAR(100) NULL DEFAULT NULL
  AFTER status;

-- 主设备（注册第一台设备，不可解绑）
-- 见 database/migrations/20260720_add_user_primary_device_id.sql
ALTER TABLE users
  ADD COLUMN primary_device_id INT NULL DEFAULT NULL
  AFTER user_token_reset_at;

-- 主设备迁移申请：仅 Redis，无需建表。
-- 若曾加过 pending 列可删除：
-- ALTER TABLE users DROP COLUMN primary_device_pending_id, DROP COLUMN primary_transfer_requested_at;

-- 贴文 / 评论 / 媒体：发送用户（旧数据可为 NULL）
-- 见 database/migrations/20260720_add_posts_user_id.sql

-- 贴文 / 评论：匿名标记
-- 见 database/migrations/20260720_add_posts_is_anonymous.sql

-- 贴文：分类（问答 / 资料 / 兴趣 / 梗图；历史数据全部为「默认」）
-- 见 database/migrations/20260816_add_posts_category.sql
ALTER TABLE posts
  ADD COLUMN category VARCHAR(20) NOT NULL DEFAULT '默认' AFTER is_anonymous,
  ADD INDEX idx_posts_category (category);

-- 迁移后需以 TEST_MODEL=true 重启并调用 GET /posts/syncES 全量重建 ES 索引，
-- 否则历史贴文的 search+category 组合查不到（旧 ES 文档无 category 字段）。

-- 历史贴文分类回填（一次性数据脚本，模型逐条分类结果）：
-- 见 database/migrations/20260816_backfill_posts_model.sql
-- 规则：有图片→梗图；其余按内容语义判定 问答/资料/兴趣；未判定保持「默认」。
-- 执行后同样需重建 ES 索引（syncES），否则 ES 里的 category 为旧值。

-- 「梗图」重分类（历史回填时"有图一律梗图"过粗，部分实为教程/提问截图）：
-- 见 scripts/reclassify_meme.py：只读客户端，用硅基流动 Qwen3-VL 逐条识图判定，
-- 输出变更结果与可手动执行的 UPDATE SQL（不写库）。改完 MySQL 后需重建 ES 索引
-- （syncES）同步 category。用法：sudo python3 scripts/reclassify_meme.py [--limit N]

-- 手机号登录（新增 phone 字段、取消 fingerprint_hash 全局唯一索引）
-- 见 design-phone-login.md
ALTER TABLE users
  ADD COLUMN phone VARCHAR(20) NULL AFTER user_display_id,
  ADD UNIQUE KEY uk_users_phone (phone);

ALTER TABLE fingerprints DROP INDEX uk_fingerprints_hash;
-- 可选，提升按指纹查询性能：
-- ALTER TABLE fingerprints ADD INDEX idx_fingerprints_hash (fingerprint_hash);
```

历史迁移示例：

```sql
ALTER TABLE users CHANGE user_external_token user_token VARCHAR(128);
ALTER TABLE users DROP INDEX IF EXISTS idx_external_token;
ALTER TABLE users DROP INDEX IF EXISTS uk_external_token;
ALTER TABLE users ADD INDEX idx_user_token (user_token);
ALTER TABLE users ADD UNIQUE INDEX uk_user_token (user_token);

ALTER TABLE user_identifier_history CHANGE old_value value VARCHAR(255);
ALTER TABLE devices DROP COLUMN IF EXISTS unique_token;
```

---

## 开发

```bash
npm install
npm run start:dev    # 默认监听 7300
npm run build        # 生产编译
```

> 当前仓库已移除原有损坏的 `*.spec.ts` 文件，`npm test` 暂无可用用例。后续补充测试时建议从 `src/user/sms/*`、`src/user/user.service.login.ts` 等核心模块开始。
