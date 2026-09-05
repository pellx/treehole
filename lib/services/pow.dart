import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class PoWChallenge {
  final String challengeId;
  final String challenge;
  final int difficulty;

  const PoWChallenge({
    required this.challengeId,
    required this.challenge,
    required this.difficulty,
  });

  factory PoWChallenge.fromJson(Map<String, dynamic> json) {
    return PoWChallenge(
      challengeId: json['challenge_id'] as String,
      challenge: json['challenge'] as String,
      difficulty: json['difficulty'] as int,
    );
  }
}

/// PoW 求解结果（challenge_id + nonce），提交给后端验证
class PoWResult {
  final String challengeId;
  final int nonce;

  const PoWResult({required this.challengeId, required this.nonce});
}

class PoWService {
  static const _timeout = Duration(seconds: 30);
  static const _maxIterations = 200_000_000;

  /// 在后台 isolate 中暴力搜索 nonce，30 秒超时
  static Future<int?> solve(PoWChallenge c) async {
    try {
      return await Isolate.run(
        () => _solveSync(c),
      ).timeout(_timeout, onTimeout: () => null);
    } catch (e) {
      debugPrint('[PoW] Exception: $e');
      return null;
    }
  }

  static int? _solveSync(PoWChallenge c) {
    final inputBase = utf8.encode(c.challenge);
    int nonce = 0;
    while (nonce < _maxIterations) {
      final nonceStr = nonce.toString();
      final input = Uint8List(inputBase.length + nonceStr.length);
      input.setAll(0, inputBase);
      for (int i = 0; i < nonceStr.length; i++) {
        input[inputBase.length + i] = nonceStr.codeUnitAt(i);
      }
      final hash = sha256.convert(input).bytes;
      if (_checkDifficulty(hash, c.difficulty)) return nonce;
      nonce++;
    }
    return null; // 超限未找到
  }

  static bool _checkDifficulty(List<int> hash, int bits) {
    int fullBytes = bits ~/ 8;
    int remainingBits = bits % 8;
    for (int i = 0; i < fullBytes; i++) {
      if (hash[i] != 0) return false;
    }
    if (remainingBits > 0) {
      int mask = 0xFF << (8 - remainingBits);
      if ((hash[fullBytes] & mask) != 0) return false;
    }
    return true;
  }
}
