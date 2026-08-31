import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// `binding.unbound` 推送摘要（含踢人设备，字段对齐 README 附录 E）
class BindingUnboundInfo {
  final String reason;
  final int? deviceId;
  final int? bindingId;
  final int? actorDeviceId;
  final String? actorDeviceDisplayName;
  final String? actorDeviceName;
  final String? actorIp;
  final String? actorBrand;
  final String? actorModel;
  final String? at;

  const BindingUnboundInfo({
    required this.reason,
    this.deviceId,
    this.bindingId,
    this.actorDeviceId,
    this.actorDeviceDisplayName,
    this.actorDeviceName,
    this.actorIp,
    this.actorBrand,
    this.actorModel,
    this.at,
  });

  /// 展示用踢人设备名：自定义名 → 系统名 → 品牌型号 → 设备 id
  String get actorLabel {
    final custom = actorDeviceDisplayName?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final name = actorDeviceName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final hardware = actorHardwareLabel;
    if (hardware != null) return hardware;
    if (actorDeviceId != null) return '设备 #$actorDeviceId';
    return '未知设备';
  }

  /// 品牌 + 型号（有则拼一行）
  String? get actorHardwareLabel {
    final brand = actorBrand?.trim();
    final model = actorModel?.trim();
    if ((brand == null || brand.isEmpty) && (model == null || model.isEmpty)) {
      return null;
    }
    if (brand != null &&
        brand.isNotEmpty &&
        model != null &&
        model.isNotEmpty) {
      if (model.toLowerCase().startsWith(brand.toLowerCase())) return model;
      return '$brand $model';
    }
    return (model != null && model.isNotEmpty) ? model : brand;
  }

  bool get isRemoteUnbind => reason == 'remote_unbind';
  bool get isLocalDue => reason == 'local_unbind_due';

  static BindingUnboundInfo? fromPayload(dynamic data) {
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);
    final reason = '${map['reason'] ?? ''}';
    int? asInt(dynamic v) {
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    String? asStr(dynamic v) {
      if (v == null) return null;
      final s = '$v'.trim();
      return s.isEmpty || s == 'null' ? null : s;
    }

    return BindingUnboundInfo(
      reason: reason.isEmpty ? 'remote_unbind' : reason,
      deviceId: asInt(map['device_id']),
      bindingId: asInt(map['binding_id']),
      actorDeviceId: asInt(map['actor_device_id']),
      actorDeviceDisplayName: asStr(map['actor_device_display_name']),
      actorDeviceName: asStr(map['actor_device_name']),
      actorIp: asStr(map['actor_ip']),
      actorBrand: asStr(map['actor_brand']),
      actorModel: asStr(map['actor_model']),
      at: asStr(map['at']),
    );
  }
}

/// Socket.IO 实时通道（附录 E）
///
/// 同源 path `/node/socket.io`，握手 auth：`session_id` + `session_secret`。
/// 事件：`binding.unbound` / `session.invalidated` / `test.tick`。
class RealtimeService {
  RealtimeService._();

  static final RealtimeService instance = RealtimeService._();

  /// 与 HTTP API 同源（反代终结 TLS）
  static const _host = 'https://tree.leisure.xin';
  static const _path = '/node/socket.io';

  io.Socket? _socket;
  int? _connectedSessionId;
  bool _handlersBound = false;

  void Function(BindingUnboundInfo? info)? onBindingUnbound;
  VoidCallback? onSessionInvalidated;

  /// UI：连接状态文案（未连接 / 连接中 / 已连接 / 错误…）
  final ValueNotifier<String> connectionLabel =
      ValueNotifier<String>('未连接');

  /// UI：最近一次 `test.tick` 展示文案；未测时为 null
  final ValueNotifier<String?> lastTestTickLabel =
      ValueNotifier<String?>(null);

  /// UI：是否正在跑连通性测试
  final ValueNotifier<bool> testRunning = ValueNotifier<bool>(false);

  bool get isConnected => _socket?.connected == true;
  bool get isTestRunning => testRunning.value;

  /// 用当前 session 建连；同 session 已连接则跳过。
  void connect({
    required int sessionId,
    required String sessionSecret,
  }) {
    if (sessionSecret.isEmpty) return;
    if (_connectedSessionId == sessionId && isConnected) return;

    disconnect();
    _connectedSessionId = sessionId;
    connectionLabel.value = '连接中…';

    final socket = io.io(
      _host,
      io.OptionBuilder()
          .setPath(_path)
          .setAuth({
            'session_id': sessionId,
            'session_secret': sessionSecret,
          })
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(20)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .enableForceNew()
          .build(),
    );

    _socket = socket;
    final boundSessionId = sessionId;

    socket.onConnect((_) {
      debugPrint('[Realtime] connected session=$boundSessionId');
      connectionLabel.value = '已连接';
    });
    socket.onDisconnect((_) {
      debugPrint('[Realtime] disconnected session=$boundSessionId');
      testRunning.value = false;
      if (_connectedSessionId == boundSessionId) {
        connectionLabel.value = '未连接';
      }
    });
    socket.onConnectError((err) {
      debugPrint('[Realtime] connect error: $err');
      connectionLabel.value = '连接失败';
    });
    socket.onError((err) {
      debugPrint('[Realtime] error: $err');
    });

    socket.on('binding.unbound', (data) {
      if (_connectedSessionId != boundSessionId) return;
      debugPrint('[Realtime] binding.unbound: $data');
      onBindingUnbound?.call(BindingUnboundInfo.fromPayload(data));
    });
    socket.on('session.invalidated', (data) {
      if (_connectedSessionId != boundSessionId) return;
      debugPrint('[Realtime] session.invalidated: $data');
      onSessionInvalidated?.call();
    });
    socket.on('test.tick', (data) {
      if (_connectedSessionId != boundSessionId) return;
      final n = _readTickN(data);
      final at = _readTickAt(data);
      lastTestTickLabel.value =
          n == null ? '收到 tick（解析失败）' : 'n=$n${at != null ? '  $at' : ''}';
      debugPrint('[Realtime] test.tick: $data');
    });
  }

  void disconnect() {
    stopTest();
    final socket = _socket;
    _socket = null;
    _connectedSessionId = null;
    connectionLabel.value = '未连接';
    if (socket == null) return;
    try {
      socket.clearListeners();
      socket.dispose();
    } catch (e) {
      debugPrint('[Realtime] disconnect: $e');
    }
  }

  /// 向服务端 emit `test.start`，每秒收 `test.tick`
  bool startTest() {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      lastTestTickLabel.value = '未连接，无法开始测试';
      testRunning.value = false;
      return false;
    }
    lastTestTickLabel.value = '等待 tick…';
    socket.emit('test.start');
    testRunning.value = true;
    return true;
  }

  void stopTest() {
    if (!testRunning.value) return;
    try {
      _socket?.emit('test.stop');
    } catch (e) {
      debugPrint('[Realtime] test.stop: $e');
    }
    testRunning.value = false;
  }

  /// 仅绑一次业务回调，避免重复注册
  void bindHandlers({
    required void Function(BindingUnboundInfo? info) bindingUnbound,
    required VoidCallback sessionInvalidated,
  }) {
    if (_handlersBound) return;
    _handlersBound = true;
    onBindingUnbound = bindingUnbound;
    onSessionInvalidated = sessionInvalidated;
  }

  static int? _readTickN(dynamic data) {
    if (data is Map) {
      final raw = data['n'];
      if (raw is num) return raw.toInt();
      return int.tryParse('$raw');
    }
    return null;
  }

  static String? _readTickAt(dynamic data) {
    if (data is Map) {
      final raw = data['at'];
      if (raw is String && raw.isNotEmpty) return raw;
    }
    return null;
  }
}
