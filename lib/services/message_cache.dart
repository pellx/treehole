import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Account-scoped encrypted cache. Credentials themselves are never stored here.
class MessageCache {
  final Box<String> box;
  final String scope;
  MessageCache(this.box, this.scope);
  static Future<Box<String>>? _opening;
  static const _secure = FlutterSecureStorage();
  static final Map<String, Future<void>> _locks = {};

  static Future<MessageCache> open(String token) async {
    final box = await (_opening ??= _openBox());
    return MessageCache(box, sha256.convert(utf8.encode(token)).toString());
  }

  static Future<Box<String>> _openBox() async {
    try {
      var key = await _secure.read(key: 'message_cache_key_v1');
      if (key == null) {
        key = base64UrlEncode(Hive.generateSecureKey());
        await _secure.write(key: 'message_cache_key_v1', value: key);
      }
      return await Hive.openBox<String>(
        'message_cache_v1',
        encryptionCipher: HiveAesCipher(base64Url.decode(key)),
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
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
