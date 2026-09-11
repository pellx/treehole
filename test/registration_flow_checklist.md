# 注册链路测试计划

## 自动化测试（本仓库）

| 文件 | 覆盖 |
|---|---|
| `test/api_contract_test.dart` | lastError 生命周期（开始清理/成功清空/网络/超时/缺字段）、registerV2 幂等 ID、registerV2/result 恢复端点、sms 契约（无 CAPTCHA/PoW） |
| `test/activation_state_test.dart` | activationPending 标记、registered 不变量（pending 期间不得为 true）、registration_request_id 持久化 |

## 手工 / 集成测试清单

> 前置：后端已应用 `tmp_backend_patch/reg_idempotency/` 补丁并重新部署。

1. **普通新设备注册成功**：走完 captcha → 取名 → 确认；观察
   `binding/create → session/create → PostStorage.registered=true`，
   杀掉应用重启后直接进入主页面且接口正常。
2. **CAPTCHA 失败 / 过期 / 重复使用**：分别制造 F001 风控拒绝、
   ticket 超 10 分钟、重复提交同一 ticket；页面提示可理解，且过期后
   自动回到验证阶段。
3. **PoW 失败和过期**：取名页停留 > 3 分钟后提交，提示后重取 PoW
   可成功。
4. **昵称已占用后修改昵称重试**：`NAME_TAKEN` 时 ticket 保留，
   改名直接重试成功（无需重做验证）。
5. **registerV2 成功但 binding/create 失败**：用代理断开在
   registerV2 响应后的所有请求 → 页面进入「注册成功，激活未完成」，
   点「重试建立会话」后恢复网络，激活成功并置 registered=true。
   全程不再次调用 registerV2（抓包确认）。
6. **binding/create 成功但 session/create 失败**：同上但只断开
   session/create；重试时 activateAfterRegister 直接补建 session
   （不再重复建绑）。
7. **注册响应超时但服务端已建号**：代理在服务端处理后丢弃响应 →
   客户端超时后自动调 `registerV2/result` 恢复原结果；数据库确认
   只创建了一个用户。
8. **应用重启后恢复待激活注册**：在激活中断状态杀应用重开 →
   启动时 ensureSession 自动恢复激活；再开注册页直接进入
   activating 阶段而非重新注册。
9. **已注册设备短信登录**：sms/send 返回 `mode: login`，验证码登录
   成功并直接拿到 session。
10. **已注册设备短信注册新账号**：sms/send 返回 `mode: register`，
    填写昵称注册成功，主设备为本机。
11. **短信验证码错误 / 过期 / 超次**：分别提示 `SMS_CODE_INVALID` /
    `SMS_CODE_EXPIRED` / `SMS_CODE_ATTEMPTS_EXCEEDED`。
12. **手机号发送冷却和频率限制**：冷却倒计时生效；
    `SMS_DAILY_LIMIT_EXCEEDED` / `SMS_IP_RATE_LIMIT_EXCEEDED` 提示正确。
13. **有效 token 登录**：粘贴 token 登录成功，registered=true。
14. **无效 token / 指纹不匹配 / 切号锁 / 转移申请过期**：分别提示
    `USER_NOT_FOUND` / `FINGERPRINT_MISMATCH` / `DEVICE_SESSION_LOCKED` /
    `TRANSFER_INVALID`，且网络错误不会被误判为以上业务错误
    （断网重试不应触发切号或 secret 轮换——抓包确认无 login 请求）。
15. **连续刷新注册页**：检测中连点右上角刷新多次，最终展示最后一次
    检测的结果；旧请求回包不覆盖新状态（可在代理中给不同请求不同
    延迟验证）。

## 最终通过标准

```text
注册接口成功
→ 设备绑定成功
→ session 创建成功
→ PostStorage.registered=true
→ 应用重启后 session 可恢复
→ 用户可以正常进入主页面
```
