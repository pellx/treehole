// 手机号短信接口的响应模型（API.md 4b–4e）

/// POST /user/sms/send 响应
class SmsSendResult {
  /// 是否已发送；冷却期内为 false（不视为错误）
  final bool sent;

  /// sent=false 时为剩余冷却秒数；否则为本次冷却时长
  final int cooldownSeconds;

  /// 携带指纹发送时的判定模式：
  /// login（手机号已注册）/ recover（绑定到本机主设备账户后登录）/
  /// register（注册新账户）；未携带指纹时为 null
  final String? mode;

  const SmsSendResult({
    required this.sent,
    required this.cooldownSeconds,
    this.mode,
  });
}

/// POST /user/sms/login 响应 — 服务端直接签发 session
class SmsLoginResult {
  final int sessionId;
  final String sessionSecret;

  /// 部分后端版本会随响应带出 user_token；缺省时本机仅保存 session，
  /// 账户切换/解绑 failover 的令牌机制对该账户不可用
  final String? userToken;

  const SmsLoginResult({
    required this.sessionId,
    required this.sessionSecret,
    this.userToken,
  });
}
