import '../services/timezone_service.dart';

/// POST /user/register 返回的凭证
class RegisterResult {
  final String userToken;
  final String deviceSecret;

  const RegisterResult({required this.userToken, required this.deviceSecret});
}

/// POST /user/session/create 返回的 session 凭证
class SessionCreateResult {
  final int sessionId;
  final String sessionSecret;

  const SessionCreateResult({
    required this.sessionId,
    required this.sessionSecret,
  });
}

/// POST /user/login 返回轮换后的 device_secret（不签发 session）
class LoginResult {
  final String deviceSecret;
  final int bindingId;
  final int deviceId;

  const LoginResult({
    required this.deviceSecret,
    required this.bindingId,
    required this.deviceId,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    final secret = json['device_secret'] as String?;
    if (secret == null || secret.isEmpty) {
      throw FormatException('响应缺少 device_secret');
    }
    return LoginResult(
      deviceSecret: secret,
      bindingId: (json['binding_id'] as num).toInt(),
      deviceId: (json['device_id'] as num).toInt(),
    );
  }
}

/// POST /user/binding/create 响应
class BindingCreateResult {
  final int bindingId;
  final int deviceId;

  const BindingCreateResult({required this.bindingId, required this.deviceId});

  factory BindingCreateResult.fromJson(Map<String, dynamic> json) {
    return BindingCreateResult(
      bindingId: (json['binding_id'] as num).toInt(),
      deviceId: (json['device_id'] as num).toInt(),
    );
  }
}

/// POST /user/binding/last-switch 本机切号锁状态
class LastSwitchResult {
  final DateTime? switchedAt;
  final int? ownerUserId;
  final DateTime? expiresAt;

  const LastSwitchResult({this.switchedAt, this.ownerUserId, this.expiresAt});

  bool get isLocked {
    final exp = expiresAt;
    return exp != null && exp.isAfter(DateTime.now());
  }

  factory LastSwitchResult.fromJson(Map<String, dynamic> json) {
    return LastSwitchResult(
      switchedAt: TimezoneService.parseServerDateTime(json['switched_at']),
      ownerUserId: (json['owner_user_id'] as num?)?.toInt(),
      expiresAt: TimezoneService.parseServerDateTime(json['expires_at']),
    );
  }
}

/// POST /user/session/validate 返回的校验结果
class SessionValidateResult {
  final bool valid;
  final int? userId;

  const SessionValidateResult({required this.valid, this.userId});
}

/// POST /user/profile 返回的用户资料
class UserProfileResult {
  final String userDisplayId;
  final DateTime? displayIdChangedAt;
  final DateTime? tokenResetAt;

  const UserProfileResult({
    required this.userDisplayId,
    this.displayIdChangedAt,
    this.tokenResetAt,
  });

  factory UserProfileResult.fromJson(Map<String, dynamic> json) {
    return UserProfileResult(
      userDisplayId: json['user_display_id'] as String? ?? '',
      displayIdChangedAt: TimezoneService.parseServerDateTime(
        json['display_id_changed_at'],
      ),
      tokenResetAt: TimezoneService.parseServerDateTime(
        json['token_reset_at'],
      ),
    );
  }
}

/// POST /user/rename 成功返回
class RenameResult {
  final String userDisplayId;
  final DateTime? displayIdChangedAt;

  const RenameResult({required this.userDisplayId, this.displayIdChangedAt});
}

/// POST /user/token/reset 返回的新令牌
class TokenResetResult {
  final String userToken;
  final DateTime? tokenResetAt;

  const TokenResetResult({required this.userToken, this.tokenResetAt});
}

/// POST /user/binding/primary-transfer 响应
class PrimaryTransferResult {
  final int? primaryDeviceId;
  final int? primaryDevicePendingId;
  final DateTime? primaryTransferRequestedAt;
  final DateTime? primaryTransferExecuteAt;

  const PrimaryTransferResult({
    this.primaryDeviceId,
    this.primaryDevicePendingId,
    this.primaryTransferRequestedAt,
    this.primaryTransferExecuteAt,
  });

  factory PrimaryTransferResult.fromJson(Map<String, dynamic> json) {
    return PrimaryTransferResult(
      primaryDeviceId: (json['primary_device_id'] as num?)?.toInt(),
      primaryDevicePendingId: (json['primary_device_pending_id'] as num?)
          ?.toInt(),
      primaryTransferRequestedAt: TimezoneService.parseServerDateTime(
        json['primary_transfer_requested_at'],
      ),
      primaryTransferExecuteAt: TimezoneService.parseServerDateTime(
        json['primary_transfer_execute_at'],
      ),
    );
  }
}

/// POST /user/binding/transfer-request 成功响应
class BindingTransferResult {
  final int fromDeviceId;
  final int expiresIn;
  final DateTime? expiresAt;

  const BindingTransferResult({
    required this.fromDeviceId,
    required this.expiresIn,
    this.expiresAt,
  });

  factory BindingTransferResult.fromJson(Map<String, dynamic> json) {
    return BindingTransferResult(
      fromDeviceId: (json['from_device_id'] as num).toInt(),
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      expiresAt: TimezoneService.parseServerDateTime(json['expires_at']),
    );
  }
}

/// POST /user/binding/delete 成功响应
class BindingUnbindResult {
  final int bindingId;
  final int deviceId;
  final String status;
  final DateTime? unbindRequestedAt;
  final DateTime? unbindExecuteAt;

  const BindingUnbindResult({
    required this.bindingId,
    required this.deviceId,
    required this.status,
    this.unbindRequestedAt,
    this.unbindExecuteAt,
  });

  factory BindingUnbindResult.fromJson(Map<String, dynamic> json) {
    return BindingUnbindResult(
      bindingId: (json['id'] as num).toInt(),
      deviceId: (json['device_id'] as num).toInt(),
      status: json['status'] as String? ?? 'unbind_pending',
      unbindRequestedAt: TimezoneService.parseServerDateTime(json['unbind_requested_at']),
      unbindExecuteAt: TimezoneService.parseServerDateTime(json['unbind_execute_at']),
    );
  }
}
