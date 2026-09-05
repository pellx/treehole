import '../services/timezone_service.dart';

/// POST /user/devices2user 单条设备
class BoundDeviceInfo {
  /// user_device_binding.id
  final int bindingId;
  final int deviceId;

  /// active / unbind_pending
  final String status;
  final DateTime? unbindRequestedAt;

  /// 仅 delete 响应可能带回；列表侧可用 requested+2天推算
  final DateTime? unbindExecuteAt;
  final String? deviceDisplayName;
  final String? deviceName;
  final String? fingerprint;
  final String? brand;
  final String? model;
  final String? os;

  /// CPU 架构（如 arm64-v8a；iOS 为 machine）
  final String? abi;

  /// 是否当前主设备
  final bool isPrimary;

  /// 是否主设备迁移目标（待生效）
  final bool isPrimaryPending;

  const BoundDeviceInfo({
    required this.bindingId,
    required this.deviceId,
    this.status = 'active',
    this.unbindRequestedAt,
    this.unbindExecuteAt,
    this.deviceDisplayName,
    this.deviceName,
    this.fingerprint,
    this.brand,
    this.model,
    this.os,
    this.abi,
    this.isPrimary = false,
    this.isPrimaryPending = false,
  });

  bool get isUnbindPending => status == 'unbind_pending';

  /// 正式解绑时间：优先接口字段，否则申请时间 + 2 天
  DateTime? get effectiveUnbindExecuteAt {
    if (unbindExecuteAt != null) return unbindExecuteAt;
    final requested = unbindRequestedAt;
    if (requested == null) return null;
    return requested.add(const Duration(days: 2));
  }

  factory BoundDeviceInfo.fromJson(Map<String, dynamic> json) {
    final bindingRaw = json['id'] ?? json['binding_id'];
    final deviceRaw = json['device_id'];
    if (bindingRaw is! num) {
      throw FormatException('响应缺少绑定 id');
    }
    if (deviceRaw is! num) {
      throw FormatException('响应缺少 device_id');
    }
    return BoundDeviceInfo(
      bindingId: bindingRaw.toInt(),
      deviceId: deviceRaw.toInt(),
      status: json['status'] as String? ?? 'active',
      unbindRequestedAt: TimezoneService.parseServerDateTime(json['unbind_requested_at']),
      unbindExecuteAt: TimezoneService.parseServerDateTime(json['unbind_execute_at']),
      deviceDisplayName: json['device_display_name'] as String?,
      deviceName: json['device_name'] as String?,
      fingerprint: json['fingerprint'] as String?,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      os: json['os'] as String?,
      abi: json['abi'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
      isPrimaryPending: json['is_primary_pending'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': bindingId,
    'device_id': deviceId,
    'status': status,
    'unbind_requested_at': unbindRequestedAt?.toIso8601String(),
    'unbind_execute_at': unbindExecuteAt?.toIso8601String(),
    'device_display_name': deviceDisplayName,
    'device_name': deviceName,
    'fingerprint': fingerprint,
    'brand': brand,
    'model': model,
    'os': os,
    'abi': abi,
    'is_primary': isPrimary,
    'is_primary_pending': isPrimaryPending,
  };
}

/// POST /user/devices2user 完整响应
class BoundDevicesResult {
  final List<BoundDeviceInfo> devices;
  final int? primaryDeviceId;
  final int? primaryDevicePendingId;
  final DateTime? primaryTransferRequestedAt;
  final DateTime? primaryTransferExecuteAt;

  const BoundDevicesResult({
    required this.devices,
    this.primaryDeviceId,
    this.primaryDevicePendingId,
    this.primaryTransferRequestedAt,
    this.primaryTransferExecuteAt,
  });

  factory BoundDevicesResult.fromJson(Map<String, dynamic> json) {
    final list = json['devices'];
    if (list is! List) {
      throw FormatException('响应缺少 devices');
    }
    return BoundDevicesResult(
      devices: list
          .whereType<Map>()
          .map((e) => BoundDeviceInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
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

/// POST /user/user2device 单条账户绑定
class BoundAccountInfo {
  /// user_device_binding.id
  final int bindingId;
  final int deviceId;
  final String status;
  final DateTime? unbindRequestedAt;
  final String userToken;
  final String? userDisplayId;

  /// 用户注册时间
  final DateTime? createdAt;

  const BoundAccountInfo({
    required this.bindingId,
    required this.deviceId,
    this.status = 'active',
    this.unbindRequestedAt,
    required this.userToken,
    this.userDisplayId,
    this.createdAt,
  });

  bool get isUnbindPending => status == 'unbind_pending';

  factory BoundAccountInfo.fromJson(Map<String, dynamic> json) {
    final bindingRaw = json['id'] ?? json['binding_id'];
    // 缓存仅存遮罩预览；接口返回完整 token
    final token = (json['user_token'] as String?)?.trim() ?? '';
    final preview = (json['user_token_preview'] as String?)?.trim() ?? '';
    return BoundAccountInfo(
      bindingId: (bindingRaw as num).toInt(),
      deviceId: (json['device_id'] as num).toInt(),
      status: json['status'] as String? ?? 'active',
      unbindRequestedAt: TimezoneService.parseServerDateTime(json['unbind_requested_at']),
      userToken: token.isNotEmpty ? token : preview,
      userDisplayId: json['user_display_id'] as String?,
      createdAt: TimezoneService.parseServerDateTime(json['created_at']),
    );
  }

  /// 本地缓存用：不含完整 user_token，仅留遮罩预览供列表展示
  Map<String, dynamic> toCacheJson() {
    final token = userToken.trim();
    String? preview;
    if (token.isNotEmpty) {
      const head = 4;
      const tail = 4;
      preview = token.length > head + tail
          ? '${token.substring(0, head)}...${token.substring(token.length - tail)}'
          : token;
    }
    return {
      'id': bindingId,
      'device_id': deviceId,
      'status': status,
      'unbind_requested_at': unbindRequestedAt?.toIso8601String(),
      'user_display_id': userDisplayId,
      'created_at': createdAt?.toIso8601String(),
      if (preview != null) 'user_token_preview': preview,
    };
  }
}
