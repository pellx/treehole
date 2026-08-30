import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/comment.dart';
import '../models/device_fingerprint.dart';
import '../models/post.dart';
import '../models/post_meta.dart';
import 'pow.dart';
import '../models/post_draft.dart';
import '../models/upload_result.dart';
import '../models/version_info.dart';
import 'timezone_service.dart';

bool _isHttpSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;

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
      switchedAt: _parseApiDateTime(json['switched_at']),
      ownerUserId: (json['owner_user_id'] as num?)?.toInt(),
      expiresAt: _parseApiDateTime(json['expires_at']),
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
      displayIdChangedAt: DateTime.tryParse(
        json['display_id_changed_at']?.toString() ?? '',
      ),
      tokenResetAt: DateTime.tryParse(json['token_reset_at']?.toString() ?? ''),
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

DateTime? _parseApiDateTime(dynamic raw) {
  if (raw is! String) return null;
  return TimezoneService.parseServerDateTime(raw);
}

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
      unbindRequestedAt: _parseApiDateTime(json['unbind_requested_at']),
      unbindExecuteAt: _parseApiDateTime(json['unbind_execute_at']),
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
      primaryTransferRequestedAt: _parseApiDateTime(
        json['primary_transfer_requested_at'],
      ),
      primaryTransferExecuteAt: _parseApiDateTime(
        json['primary_transfer_execute_at'],
      ),
    );
  }
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
      primaryTransferRequestedAt: _parseApiDateTime(
        json['primary_transfer_requested_at'],
      ),
      primaryTransferExecuteAt: _parseApiDateTime(
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
      expiresAt: _parseApiDateTime(json['expires_at']),
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
      unbindRequestedAt: _parseApiDateTime(json['unbind_requested_at']),
      unbindExecuteAt: _parseApiDateTime(json['unbind_execute_at']),
    );
  }
}

/// PoW 求解结果（challenge_id + nonce）
class PoWResult {
  final String challengeId;
  final int nonce;

  const PoWResult({required this.challengeId, required this.nonce});
}

class ApiService {
  static const _base = 'https://tree.leisure.xin/node/posts';
  static const _commentBase =
      'https://tree.leisure.xin/node/posts/comment'; // 回复 API
  static const _thumbBase =
      'https://tree.leisure.xin/node/file-processor/convert/2webp/upload';
  static const _originalBase = 'https://www.leisure.xin:33433/upload';
  static const _uploadBase =
      'https://tree.leisure.xin/node/file-processor/upload';
  static const _versionBase = 'https://tree.leisure.xin/node/versions';
  static const _timeout = Duration(seconds: 30);
  static const _useMock = false;

  /// 共享 HTTP 客户端：复用 TCP/TLS 连接，避免每次请求重新握手
  static final http.Client _client = http.Client();

  /// 最近一次 API 调用失败的错误消息（用于前端展示审核拒绝原因）
  static String? lastError;

  /// rename 返回 RENAME_TOO_FREQUENT 时解析出的下次可改时间
  static DateTime? lastNextRenameAt;

  /// rename 返回 RENAME_TOO_FREQUENT 时解析出的上次改名时间
  static DateTime? lastDisplayIdChangedAt;

  static Future<List<int>> getIdList({
    String? search,
    String? author,
    String? dateStart,
    String? dateEnd,
    String? category,
    String? sort,
  }) async {
    if (_useMock) return [12, 345, 6789];
    final params = <String, String>{};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (author != null && author.isNotEmpty) params['author'] = author;
    if (dateStart != null && dateStart.isNotEmpty) {
      params['dateStart'] = dateStart;
    }
    if (dateEnd != null && dateEnd.isNotEmpty) {
      params['dateEnd'] = dateEnd;
    }
    if (category != null && category.isNotEmpty) params['category'] = category;
    if (sort != null && sort.isNotEmpty) params['sort'] = sort;
    var uri = Uri.parse('$_base/idList');
    if (params.isNotEmpty) {
      uri = uri.replace(queryParameters: params);
    }
    final res = await _client.get(uri).timeout(_timeout);
    final decoded = jsonDecode(res.body);
    if (decoded is List) {
      return List<int>.from(decoded);
    }
    throw Exception(
      decoded is Map && decoded['message'] != null
          ? decoded['message']
          : 'Unexpected response: ${res.body}',
    );
  }

  /// v2 返回贴文元数据列表，支持前端按 created_at / update_at / reply_times 排序。
  static Future<IdListV2Result> getIdListV2({
    String? search,
    String? author,
    String? dateStart,
    String? dateEnd,
    String? category,
  }) async {
    if (_useMock) {
      return IdListV2Result(
        total: 3,
        items: [
          PostMeta(id: 12, replyTimes: 0),
          PostMeta(id: 345, replyTimes: 1),
          PostMeta(id: 6789, replyTimes: 2),
        ],
      );
    }
    final params = <String, String>{};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (author != null && author.isNotEmpty) params['author'] = author;
    if (dateStart != null && dateStart.isNotEmpty) {
      params['dateStart'] = dateStart;
    }
    if (dateEnd != null && dateEnd.isNotEmpty) {
      params['dateEnd'] = dateEnd;
    }
    if (category != null && category.isNotEmpty) params['category'] = category;
    var uri = Uri.parse('$_base/idListv2');
    if (params.isNotEmpty) {
      uri = uri.replace(queryParameters: params);
    }
    final res = await _client.get(uri).timeout(_timeout);
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return IdListV2Result.fromJson(decoded);
    }
    throw Exception(
      decoded is Map && decoded['message'] != null
          ? decoded['message']
          : 'Unexpected response: ${res.body}',
    );
  }

  static Future<Post?> getPost(int id) async {
    if (_useMock) return _mockPost(id);
    try {
      final res = await _client.get(Uri.parse('$_base/$id')).timeout(_timeout);
      if (!_isHttpSuccess(res.statusCode)) {
        debugPrint('[ApiService] getPost($id) status=${res.statusCode}');
        return null;
      }
      return Post.fromJson(jsonDecode(res.body));
    } catch (e) {
      debugPrint('[ApiService] getPost($id) error: $e');
      return null;
    }
  }

  static Future<ThumbnailData?> downloadThumbnail(String fileName) async {
    try {
      final isGif = fileName.toLowerCase().endsWith('.gif');
      final url = isGif ? '$_originalBase/$fileName' : '$_thumbBase/$fileName';
      final res = await _client.get(Uri.parse(url)).timeout(_timeout);
      if (!_isHttpSuccess(res.statusCode)) {
        debugPrint(
          '[ApiService] downloadThumbnail($fileName) status=${res.statusCode}',
        );
        return null;
      }
      final bytes = res.bodyBytes;
      // 优先读图片头拿尺寸（不做整图解码）；解析不了再走 codec 兜底
      final dims = _readImageSize(bytes) ?? await _decodeSize(bytes);
      return ThumbnailData(bytes: bytes, width: dims.$1, height: dims.$2);
    } catch (e) {
      debugPrint('[ApiService] downloadThumbnail($fileName) error: $e');
      return null;
    }
  }

  static Future<(int, int)> _decodeSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    return (w, h);
  }

  /// 从图片头读取宽高（PNG/JPEG/GIF/WebP），比整图解码快得多；识别失败返回 null
  static (int, int)? _readImageSize(Uint8List bytes) {
    final b = bytes;
    if (b.length < 12) return null;
    // PNG：签名 + IHDR，宽高在偏移 16..24（大端）
    if (b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b.length >= 24) {
      return (
        (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19],
        (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23],
      );
    }
    // GIF：宽高在偏移 6..10（小端）
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b.length >= 10) {
      return (b[6] | (b[7] << 8), b[8] | (b[9] << 8));
    }
    // JPEG：逐个扫描段，直到 SOF 段取出宽高
    if (b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = b[i + 1];
        // SOI/EOI 无长度段
        if (marker == 0xD8 || marker == 0xD9) {
          i += 2;
          continue;
        }
        // TEM/RSTn 等无长度段标记，直接跳过
        if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
          i += 2;
          continue;
        }
        // SOS：其后为熵编码数据，不再有段结构
        if (marker == 0xDA) break;
        // SOF0-SOF15（排除 DHT/DAC 等）带精度+高+宽
        if (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) {
          final h = (b[i + 5] << 8) | b[i + 6];
          final w = (b[i + 7] << 8) | b[i + 8];
          return (w, h);
        }
        final len = (b[i + 2] << 8) | b[i + 3];
        i += 2 + len;
      }
    }
    // WebP：RIFF....WEBP，按 VP8X / VP8L / VP8 三种 chunk 解析
    if (b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      final chunk = String.fromCharCodes(b.sublist(12, 16));
      if (chunk == 'VP8X' && b.length >= 30) {
        return (
          1 + (b[24] | (b[25] << 8) | (b[26] << 16)),
          1 + (b[27] | (b[28] << 8) | (b[29] << 16)),
        );
      }
      if (chunk == 'VP8L' && b.length >= 25) {
        final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
        return (1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF));
      }
      if (chunk == 'VP8 ' && b.length >= 30) {
        return (b[26] | (b[27] << 8), b[28] | (b[29] << 8));
      }
    }
    return null;
  }

  /// 上传不带 session（后端 DTO 禁止）；署名时传 [userId]。
  static Future<UploadResult?> uploadFile(
    PostUploadType type,
    File file, {
    String? userId,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_uploadBase));
      request.fields['type'] = type.apiValue;
      final uid = userId?.trim();
      if (uid != null && uid.isNotEmpty) {
        request.fields['user_id'] = uid;
      }
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      final streamed = await _client.send(request).timeout(_timeout);
      if (!_isHttpSuccess(streamed.statusCode)) {
        final body = await streamed.stream.bytesToString();
        debugPrint(
          '[ApiService] uploadFile($type, ${file.path}) status=${streamed.statusCode} body=$body',
        );
        lastError = _parseErrorMessage(body);
        return null;
      }
      final body = await streamed.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      return UploadResult(
        type: type,
        original: data['originalName'] as String? ?? file.uri.pathSegments.last,
        filename: data['filename'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('[ApiService] uploadFile($type, ${file.path}) error: $e');
      return null;
    }
  }

  static Future<Post?> createPost(PostDraft draft) async {
    try {
      final res = await _client
          .post(
            Uri.parse(_base),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(draft.toJson()),
          )
          .timeout(_timeout);
      if (!_isHttpSuccess(res.statusCode)) {
        debugPrint(
          '[ApiService] createPost status=${res.statusCode} body=${res.body}',
        );
        lastError = _parseErrorMessage(res.body);
        return null;
      }
      return Post.fromJson(jsonDecode(res.body));
    } catch (e) {
      debugPrint('[ApiService] createPost error: $e');
      return null;
    }
  }

  // ---- 回复 ----

  static Future<Comment?> getComment(int id) async {
    try {
      final res = await _client
          .get(Uri.parse('$_commentBase/$id'))
          .timeout(_timeout);
      if (!_isHttpSuccess(res.statusCode)) {
        debugPrint('[ApiService] getComment($id) status=${res.statusCode}');
        return null;
      }
      return Comment.fromJson(jsonDecode(res.body));
    } catch (e) {
      debugPrint('[ApiService] getComment($id) error: $e');
      return null;
    }
  }

  /// 回复不带 session（后端 DTO 禁止）；署名时传 [userId]。
  static Future<Comment?> createComment({
    required int postId,
    required String content,
    String? author,
    bool isAnonymous = false,
    int? toId,
    String? userId,
  }) async {
    try {
      final body = <String, dynamic>{
        'postId': postId,
        'content': content,
        'is_anonymous': isAnonymous,
      };
      if (author != null && author.isNotEmpty) body['author'] = author;
      final uid = userId?.trim();
      if (uid != null && uid.isNotEmpty) body['user_id'] = uid;
      if (toId != null) body['toId'] = toId;
      final res = await _client
          .post(
            Uri.parse(_commentBase),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!_isHttpSuccess(res.statusCode)) {
        debugPrint(
          '[ApiService] createComment status=${res.statusCode} body=${res.body}',
        );
        lastError = _parseErrorMessage(res.body);
        return null;
      }
      return Comment.fromJson(jsonDecode(res.body));
    } catch (e) {
      debugPrint('[ApiService] createComment error: $e');
      return null;
    }
  }

  /// 从 API 错误响应中提取 message 字段
  /// Nest 可能返回 string，或 ValidationPipe 的 string[]
  static String _parseErrorMessage(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) {
        return msg.map((e) => e.toString()).join('；');
      }
      return '操作失败';
    } catch (_) {
      return '操作失败';
    }
  }

  // ---- 版本更新 ----

  static Future<VersionInfo?> getLatestVersion({
    String platform = 'android',
  }) async {
    try {
      final res = await _client
          .get(Uri.parse('$_versionBase/latest?platform=$platform'))
          .timeout(_timeout);
      if (!_isHttpSuccess(res.statusCode)) {
        debugPrint('[ApiService] getLatestVersion status=${res.statusCode}');
        return null;
      }
      return VersionInfo.fromJson(jsonDecode(res.body));
    } catch (e) {
      debugPrint('[ApiService] getLatestVersion error: $e');
      return null;
    }
  }

  static Future<List<VersionInfo>> getAllVersions({
    String platform = 'android',
  }) async {
    try {
      final res = await _client
          .get(Uri.parse('$_versionBase?platform=$platform'))
          .timeout(_timeout);
      if (!_isHttpSuccess(res.statusCode)) {
        debugPrint('[ApiService] getAllVersions status=${res.statusCode}');
        return [];
      }
      final list = jsonDecode(res.body) as List;
      return list
          .map((j) => VersionInfo.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ApiService] getAllVersions error: $e');
      return [];
    }
  }

  // ---- 账号注册 ----

  static const _userBase = 'https://tree.leisure.xin/node/user';

  /// POST /user/check — 纯查询，不消耗验证码/PoW，返回该指纹是否已注册
  static Future<bool?> check({
    required DeviceFingerprint deviceFingerPrint,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/check'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'device_finger_print': deviceFingerPrint.toJson(),
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['registered'] as bool? ?? false;
      }
      debugPrint(
        '[ApiService] check status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] check error: $e');
      return null;
    }
  }

  /// POST /user/registerV2 — 为新设备创建用户，返回 user_token + device_secret
  /// 验证码改为阿里云验证码 2.0（后端 VerifyIntelligentCaptcha）
  static Future<RegisterResult?> registerV2({
    required String userDisplayId,
    required DeviceFingerprint deviceFingerPrint,
    required String verificationCaptcha,
    required PoWResult verificationPow,
  }) async {
    try {
      final requestBody = {
        'user_display_id': userDisplayId,
        'device_finger_print': deviceFingerPrint.toJson(),
        'verification_captcha': verificationCaptcha,
        'verification_pow': {
          'challenge_id': verificationPow.challengeId,
          'nonce': verificationPow.nonce,
        },
      };
      debugPrint('[ApiService] registerV2 提交 name=$userDisplayId '
          'captcha(len=${verificationCaptcha.length}) '
          'pow=${verificationPow.challengeId}/nonce=${verificationPow.nonce}');
      final res = await _client
          .post(
            Uri.parse('$_userBase/registerV2'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final token = data['user_token'] as String?;
        final secret = data['device_secret'] as String?;
        if (token != null && secret != null) {
          return RegisterResult(userToken: token, deviceSecret: secret);
        }
        lastError = '响应缺少字段';
        debugPrint('[ApiService] registerV2 missing fields');
      } else {
        lastError = _parseErrorMessage(res.body);
        debugPrint(
          '[ApiService] registerV2 status=${res.statusCode} body=${res.body}',
        );
      }
      return null;
    } catch (e) {
      lastError = '网络连接失败';
      debugPrint('[ApiService] registerV2 error: $e');
      return null;
    }
  }

  /// 获取 PoW hashcash challenge
  static Future<PoWChallenge?> getPoWChallenge() async {
    try {
      final res = await _client
          .get(Uri.parse('$_userBase/pow-challenge'))
          .timeout(_timeout);
      if (!_isHttpSuccess(res.statusCode)) {
        debugPrint('[ApiService] getPoWChallenge status=${res.statusCode}');
        return null;
      }
      return PoWChallenge.fromJson(jsonDecode(res.body));
    } catch (e) {
      debugPrint('[ApiService] getPoWChallenge error: $e');
      return null;
    }
  }

  /// POST /user/login — 建绑并轮换 device_secret（**不**签发 session）
  /// 请求不带旧 secret；成功后须用响应中的新 device_secret 覆盖本地，再调 session/create。
  static Future<LoginResult?> login({
    required String userToken,
    required String fingerprintHash,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_token': userToken,
              'fingerprint_hash': fingerprintHash,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        try {
          return LoginResult.fromJson(data);
        } catch (e) {
          debugPrint('[ApiService] login parse error: $e body=${res.body}');
          lastError = '登录响应解析失败';
          return null;
        }
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] login status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] login error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/binding/create — 建绑并校验现有 device_secret（不轮换、不签发 session）
  static Future<BindingCreateResult?> createBinding({
    required String userToken,
    required String fingerprintHash,
    required String deviceSecret,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/binding/create'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_token': userToken,
              'fingerprint_hash': fingerprintHash,
              'device_secret': deviceSecret,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        try {
          return BindingCreateResult.fromJson(data);
        } catch (e) {
          debugPrint(
            '[ApiService] createBinding parse error: $e body=${res.body}',
          );
          lastError = '建绑响应解析失败';
          return null;
        }
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] createBinding status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] createBinding error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/session/create — 申请 session（一设备一有效 session；异用户切号写 2 天锁）
  /// 需要 user_token + device_secret + fingerprint_hash
  static Future<SessionCreateResult?> createSession({
    required String userToken,
    required String deviceSecret,
    required String fingerprintHash,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/session/create'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_token': userToken,
              'device_secret': deviceSecret,
              'fingerprint_hash': fingerprintHash,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final sessionId = data['session_id'] as int?;
        final sessionSecret = data['session_secret'] as String?;
        if (sessionId != null && sessionSecret != null) {
          return SessionCreateResult(
            sessionId: sessionId,
            sessionSecret: sessionSecret,
          );
        }
        debugPrint('[ApiService] createSession missing fields: ${res.body}');
        return null;
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] createSession status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] createSession error: $e');
      return null;
    }
  }

  /// POST /user/binding/last-switch — 本机上次切号锁（需有效 session）
  static Future<LastSwitchResult?> getLastSwitch({
    required int sessionId,
    required String sessionSecret,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/binding/last-switch'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return LastSwitchResult.fromJson(data);
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] getLastSwitch status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] getLastSwitch error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/session/validate — 校验 session 是否有效
  static Future<SessionValidateResult?> validateSession({
    required int sessionId,
    required String sessionSecret,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/session/validate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return SessionValidateResult(
          valid: data['valid'] == true,
          userId: data['user_id'] as int?,
        );
      }
      debugPrint(
        '[ApiService] validateSession status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] validateSession error: $e');
      return null;
    }
  }

  /// POST /user/profile — 查询名字与令牌重置时间
  static Future<UserProfileResult?> getUserProfile({
    required int sessionId,
    required String sessionSecret,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/profile'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return UserProfileResult.fromJson(data);
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] getUserProfile status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] getUserProfile error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/rename — session 鉴权改名（两周冷却）
  static Future<RenameResult?> rename({
    required int sessionId,
    required String sessionSecret,
    required String newName,
  }) async {
    lastNextRenameAt = null;
    lastDisplayIdChangedAt = null;
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/rename'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
              'new_name': newName,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final name = data['user_display_id'] as String?;
        if (name == null || name.isEmpty) {
          lastError = '响应缺少 user_display_id';
          return null;
        }
        return RenameResult(
          userDisplayId: name,
          displayIdChangedAt: DateTime.tryParse(
            data['display_id_changed_at']?.toString() ?? '',
          ),
        );
      }
      lastError = _parseErrorMessage(res.body);
      _parseRenameCooldownFields(res.body);
      debugPrint(
        '[ApiService] rename status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] rename error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// 从 RENAME_TOO_FREQUENT 错误体解析冷却时间字段
  static void _parseRenameCooldownFields(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      lastDisplayIdChangedAt = DateTime.tryParse(
        data['display_id_changed_at']?.toString() ?? '',
      );
      lastNextRenameAt = DateTime.tryParse(
        data['next_rename_at']?.toString() ?? '',
      );
    } catch (_) {
      // 旧后端可能无此字段，忽略
    }
  }

  /// POST /user/token/reset — 重置用户令牌（无冷却）
  static Future<TokenResetResult?> resetUserToken({
    required int sessionId,
    required String sessionSecret,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/token/reset'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final token = data['user_token'] as String?;
        if (token == null) {
          lastError = '响应缺少 user_token';
          return null;
        }
        return TokenResetResult(
          userToken: token,
          tokenResetAt: DateTime.tryParse(
            data['token_reset_at']?.toString() ?? '',
          ),
        );
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] resetUserToken status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] resetUserToken error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/devices2user — 当前账户绑定的设备列表（含主设备字段）
  static Future<BoundDevicesResult?> listBoundDevices({
    required int sessionId,
    required String sessionSecret,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/devices2user'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        try {
          return BoundDevicesResult.fromJson(
            jsonDecode(res.body) as Map<String, dynamic>,
          );
        } catch (e) {
          debugPrint(
            '[ApiService] listBoundDevices parse error: $e body=${res.body}',
          );
          lastError = '设备数据解析失败（后端可能未返回绑定 id，请重新编译部署）';
          return null;
        }
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] listBoundDevices status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] listBoundDevices error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/binding/primary-transfer — 主设备迁移（须在主设备 session 上发起）
  static Future<PrimaryTransferResult?> requestPrimaryTransfer({
    required int sessionId,
    required String sessionSecret,
    required int bindingId,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/binding/primary-transfer'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
              'id': bindingId,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        return PrimaryTransferResult.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>,
        );
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] requestPrimaryTransfer status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] requestPrimaryTransfer error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/binding/primary-transfer-cancel — 取消主设备迁移
  static Future<bool> cancelPrimaryTransfer({
    required int sessionId,
    required String sessionSecret,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/binding/primary-transfer-cancel'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) return true;
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] cancelPrimaryTransfer status=${res.statusCode} body=${res.body}',
      );
      return false;
    } catch (e) {
      debugPrint('[ApiService] cancelPrimaryTransfer error: $e');
      lastError = '网络连接失败';
      return false;
    }
  }

  /// POST /user/user2device — 当前设备绑定的账户列表
  static Future<List<BoundAccountInfo>?> listBoundAccounts({
    required int sessionId,
    required String sessionSecret,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/user2device'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = data['users'];
        if (list is! List) {
          lastError = '响应缺少 users';
          return null;
        }
        return list
            .whereType<Map>()
            .map((e) => BoundAccountInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] listBoundAccounts status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] listBoundAccounts error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/binding/transfer-request — 本机发起跨设备转移申请（15 分钟有效）
  static Future<BindingTransferResult?> requestBindingTransfer({
    required int sessionId,
    required String sessionSecret,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/binding/transfer-request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        try {
          return BindingTransferResult.fromJson(data);
        } catch (e) {
          debugPrint(
            '[ApiService] requestBindingTransfer parse error: $e body=${res.body}',
          );
          lastError = '转移申请响应解析失败';
          return null;
        }
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] requestBindingTransfer status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] requestBindingTransfer error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/binding/rename — 按绑定 id 修改设备显示名
  static Future<String?> renameBinding({
    required int sessionId,
    required String sessionSecret,
    required int bindingId,
    required String newName,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/binding/rename'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
              'id': bindingId,
              'new_name': newName,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['device_display_name'] as String?;
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] renameBinding status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] renameBinding error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/binding/delete — 申请解绑（进入 unbind_pending，约 2 天后正式解绑）
  static Future<BindingUnbindResult?> deleteBinding({
    required int sessionId,
    required String sessionSecret,
    required int bindingId,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/binding/delete'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
              'id': bindingId,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return BindingUnbindResult.fromJson(data);
      }
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] deleteBinding status=${res.statusCode} body=${res.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[ApiService] deleteBinding error: $e');
      lastError = '网络连接失败';
      return null;
    }
  }

  /// POST /user/binding/delete-cancel — 取消解绑申请，恢复 active
  static Future<bool> cancelDeleteBinding({
    required int sessionId,
    required String sessionSecret,
    required int bindingId,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_userBase/binding/delete-cancel'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'session_secret': sessionSecret,
              'id': bindingId,
            }),
          )
          .timeout(_timeout);
      if (_isHttpSuccess(res.statusCode)) return true;
      lastError = _parseErrorMessage(res.body);
      debugPrint(
        '[ApiService] cancelDeleteBinding status=${res.statusCode} body=${res.body}',
      );
      return false;
    } catch (e) {
      debugPrint('[ApiService] cancelDeleteBinding error: $e');
      lastError = '网络连接失败';
      return false;
    }
  }

  static Post _mockPost(int id) {
    return Post(
      id: id,
      title: 'Mock Post $id',
      content: 'This is mock content for post $id.',
      author: 'mock_user',
      createdAt: DateTime.now().toIso8601String(),
    );
  }
}

class ThumbnailData {
  final Uint8List bytes;
  final int width;
  final int height;
  const ThumbnailData({
    required this.bytes,
    required this.width,
    required this.height,
  });
}
