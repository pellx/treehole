import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:treehole/services/message_cache.dart';

void main() {
  test('rebuilds the cache once when the box cannot be decrypted', () async {
    var opens = 0;
    var resets = 0;

    final result = await MessageCache.openWithRecovery<String>(
      open: () async {
        opens++;
        if (opens == 1) {
          throw HiveError('Wrong checksum in hive file. Box may be corrupted.');
        }
        return 'opened';
      },
      reset: () async {
        resets++;
      },
    );

    expect(result, 'opened');
    expect(opens, 2);
    expect(resets, 1);
  });

  test('keeps the cache when opening fails for a non-decryption reason',
      () async {
    var resets = 0;

    await expectLater(
      MessageCache.openWithRecovery<String>(
        open: () async => throw const FileSystemException('file is locked'),
        reset: () async {
          resets++;
        },
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(resets, 0);
  });

  test('reports the failure when rebuilding does not help', () async {
    var opens = 0;

    await expectLater(
      MessageCache.openWithRecovery<String>(
        open: () async {
          opens++;
          throw HiveError('still broken');
        },
        reset: () async {},
      ),
      throwsA(isA<HiveError>()),
    );

    expect(opens, 2);
  });

  test('a box written with a lost key never wedges the message cache', () async {
    final dir = await Directory.systemTemp.createTemp('message_cache_recovery');
    addTearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });
    Hive.init(dir.path);

    final stale = await Hive.openBox<String>(
      'cache_under_test',
      encryptionCipher: HiveAesCipher(Hive.generateSecureKey()),
    );
    await stale.put('conversation', 'cached');
    await Hive.close();

    var resets = 0;
    final result = await MessageCache.openWithRecovery<String>(
      open: () async {
        final box = await Hive.openBox<String>(
          'cache_under_test',
          encryptionCipher: HiveAesCipher(Hive.generateSecureKey()),
        );
        final value = box.get('conversation') ?? '';
        await box.close();
        return value;
      },
      reset: () async {
        resets++;
        await Hive.deleteBoxFromDisk('cache_under_test');
      },
    );

    // 密钥丢失时 Hive 会截断无法解密的缓存并继续，旧内容读不到但不会中断私信。
    expect(result, '');
    expect(resets, 0);
  });
}
