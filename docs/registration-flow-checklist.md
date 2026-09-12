# 账号注册流程与检测清单

## 当前发布状态

- Flutter 客户端修复已完成并通过静态分析与注册相关测试。
- 后端源码及 `dist` 已部署到 `/var/www/treehole-nest`，隔离构建通过。
- PM2 已重载且进程在线；注册结果恢复路由冒烟检查通过。
- iOS `utsname.version` 超过数据库 `varchar(100)` 导致注册事务回滚的问题，
  已在映射层按列长度安全截断。

## 状态不变量

1. `activation_pending=true` 时，`registered` 必须为 `false`。
2. 只有 binding/session 建立成功后，才能写入 `registered=true`。
3. 一旦服务端完成建号，后续失败只能重试激活或按请求 ID 恢复，不能再次建号。
4. 切换到新注册账号前必须清除旧 session，避免“新 token + 旧 session”。
5. 同一次普通注册的所有重试必须复用同一个 `registration_request_id`。

## 流程 A：设备检测与普通注册

链路：

`采集指纹 → POST /user/check → 获取 PoW → CAPTCHA 校验 → POST /user/registerV2 → 保存 token/secret/指纹 → 标记待激活 → binding/create（必要时）→ session/create → 标记已注册`

检测清单：

- [ ] 指纹采集失败时停在检测失败页，并能重试。
- [ ] `/user/check` 网络、超时、缺字段和业务错误分别显示有效提示。
- [ ] 连续点击刷新时，旧检测响应不会覆盖新响应。
- [ ] CAPTCHA 通过后取得 ticket；昵称占用时可改名重试，不重复验证。
- [ ] PoW 过期时重新获取 challenge，不沿用失效 nonce。
- [ ] 请求包含持久化的 `registration_request_id`。
- [ ] 相同请求 ID 并发/重试不会创建第二个用户。
- [ ] 建号成功后先保存凭证并置 `activation_pending=true`。
- [ ] session 成功后才置 `registered=true`，并清理请求 ID。

## 流程 B：响应丢失与应用重启恢复

链路：

`registerV2 超时/断连 → GET /user/registerV2/result → 取回原 token/secret → 激活`

若应用在落盘前退出：

`启动注册页 → 读取 registration_request_id → 查询原结果 → 落盘凭证 → 激活`

检测清单：

- [ ] 模拟服务端已建号但客户端 registerV2 超时，查询接口返回原凭证。
- [ ] 查询 404 时不覆盖 registerV2 的原始网络错误。
- [ ] 启动恢复查询断网时停在可重试错误页，不误判为未注册。
- [ ] 启动恢复成功后从 profile 补齐昵称。
- [ ] 恢复全过程不再次调用 registerV2。
- [ ] 恢复成功后清除 `registration_request_id` 和 `activation_pending`。

## 流程 C：建号成功、激活失败

链路：

`凭证已落盘 → session/create → DEVICE_NOT_BOUND 时 binding/create → session/create → 成功`

检测清单：

- [ ] 网络中断时保留 token、device secret 和待激活标记。
- [ ] 页面只显示“重试建立会话/短信找回/返回”，不提供重复注册入口。
- [ ] 应用重启后 `ensureSession` 优先恢复待激活流程，不清除新 token。
- [ ] 缺失 token/secret 时退出待激活死循环，并提示短信找回。
- [ ] 激活成功后 realtime 同步恢复，账号进入正常登录态。

## 流程 D：已注册设备上的短信新注册

链路：

`sms/send(scene=register) → sms/register → 清旧 session → 保存新凭证 → 待激活 → session/create`

检测清单：

- [ ] 短信注册请求只发送手机号、验证码、昵称和设备指纹，不要求 CAPTCHA/PoW。
- [ ] 后端返回的发送模式与客户端解析一致。
- [ ] 新账号建号后旧 session 被清除。
- [ ] `activation_pending=true` 会把旧账号遗留的 `registered=true` 改为 false。
- [ ] 子页激活失败后返回，父注册页会接管待激活恢复。
- [ ] session 成功后才显示新账号已注册。

## 流程 E：短信找回与令牌登录

链路：

`sms/send(scene=login) → sms/login → 保存/轮换凭证 → session`，或 `粘贴用户令牌 → login/binding → session`

检测清单：

- [ ] 手机号未绑定、验证码错误、限流和网络错误均有明确提示。
- [ ] 登录成功后 profile 昵称写入本地。
- [ ] 登录失败不会误置 `registered=true`。
- [ ] 新 session 建立后旧 session 不再被继续使用。

## 发布验收

- [x] 重载 PM2 应用并确认进程在线、无 unstable restart。
- [x] 确认 `GET /node/user/registerV2/result` 命中新路由。
- [x] 确认当前 iOS Darwin Kernel 长字符串不会再触发列溢出。
- [ ] 用测试账号完整走一次普通注册和短信注册。
- [ ] 人为断网分别覆盖“提交前、建号响应后、激活时”三个时点。
- [ ] 检查数据库无同一请求导致的重复用户，Redis 失败占位会立即释放。
- [ ] 检查 PM2 日志无 DTO 白名单拒绝 `registration_request_id`。
