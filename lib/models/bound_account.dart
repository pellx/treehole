import '../services/timezone_service.dart';

DateTime? _parseApiDateTime(dynamic raw) {
  if (raw is! String) return null;
  return TimezoneService.parseServerDateTime(raw);
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
      unbindRequestedAt: _parseApiDateTime(json['unbind_requested_at']),
      userToken: token.isNotEmpty ? token : preview,
      userDisplayId: json['user_display_id'] as String?,
      createdAt: _parseApiDateTime(json['created_at']),
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
