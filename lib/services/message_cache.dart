import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Account-scoped encrypted cache. Credentials themselves are never stored here.
class MessageCache {
  final Box<String> box;
  final String scope;
  MessageCache(this.box, this.scope);
  static Future<Box<String>>? _opening;
  static const _secure = FlutterSecureStorage();
  static const _boxName = 'message_cache_v1';
  static const _keyName = 'message_cache_key_v1';
  static const _keyBytes = 32;
  static final Map<String, Future<void>> _locks = {};

  static Future<MessageCache> open(String token) async {
    final box = await (_opening ??= _openBox());
    return MessageCache(box, sha256.convert(utf8.encode(token)).toString());
  }

  static Future<Box<String>> _openBox() async {
    try {
      return await openWithRecovery(
        open: _openWithStoredKey,
        reset: _resetCache,
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  /// 安全存储里的密钥与磁盘上的缓存不匹配时（系统清除数据、备份恢复不完整等），
  /// 旧缓存永远无法解密。此时清掉缓存并按需重建密钥，让私信恢复到可用状态；
  /// 其他错误（例如文件被占用）原样抛出，避免误删可恢复的缓存。
  @visibleForTesting
  static Future<T> openWithRecovery<T>({
    required Future<T> Function() open,
    required Future<void> Function() reset,
  }) async {
    try {
      return await open();
    } on HiveError {
      await reset();
      return open();
    }
  }

  static Future<Box<String>> _openWithStoredKey() async {
    final key = await _readKey() ?? await _createKey();
    return Hive.openBox<String>(
      _boxName,
      encryptionCipher: HiveAesCipher(key),
    );
  }

  static Future<List<int>?> _readKey() async {
    final stored = await _secure.read(key: _keyName);
    if (stored == null) return null;
    try {
      final key = base64Url.decode(stored);
      return key.length == _keyBytes ? key : null;
    } on FormatException {
      return null;
    }
  }

  static Future<List<int>> _createKey() async {
    final key = Hive.generateSecureKey();
    await _secure.write(key: _keyName, value: base64UrlEncode(key));
    return key;
  }

  static Future<void> _resetCache() async {
    try {
      if (Hive.isBoxOpen(_boxName)) {
        await Hive.box<String>(_boxName).close();
      }
    } catch (_) {}
    try {
      await Hive.deleteBoxFromDisk(_boxName);
    } catch (_) {}
    try {
      await _secure.delete(key: _keyName);
    } catch (_) {}
  }

  Map<String, dynamic>? read(String key) {
    final raw = box.get('$scope/$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> value) =>
      box.put('$scope/$key', jsonEncode(value));
  Future<void> clear() async {
    await box.deleteAll(
      box.keys.where((key) => key.toString().startsWith('$scope/')).toList(),
    );
  }

  Future<T> serial<T>(String key, Future<T> Function() work) async {
    final name = '$scope/$key';
    final previous = _locks[name] ?? Future<void>.value();
    final next = previous.then((_) => work());
    final settled = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _locks[name] = settled;
    try {
      return await next;
    } finally {
      if (identical(_locks[name], settled)) _locks.remove(name);
    }
  }
}
