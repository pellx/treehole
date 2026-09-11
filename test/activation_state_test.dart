import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:treehole/services/storage.dart';

/// 注册激活状态机（PostStorage）：
/// activationPending 标记 + registration_request_id 持久化。
///
/// 对应修复计划验收点：「应用重启后可以继续激活」——
/// pending 与请求 ID 都落在 Hive（account box），重启后可读回。
void main() {
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('hive_activation_test');
    Hive.init(tmpDir.path);
    await PostStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test('activationPending 默认 false，可置位/清除', () async {
    expect(PostStorage.isActivationPending(), isFalse);

    await PostStorage.setActivationPending(true);
    expect(PostStorage.isActivationPending(), isTrue);

    await PostStorage.setActivationPending(false);
    expect(PostStorage.isActivationPending(), isFalse);
  });

  test('registered 与 activationPending 相互独立', () async {
    // 关键不变量：registered=true 只能在激活完成后置位，
    // pending 期间 registered 必须保持 false
    await PostStorage.setActivationPending(true);
    expect(PostStorage.isRegistered(), isFalse);

    await PostStorage.setRegistered(true);
    expect(PostStorage.isActivationPending(), isTrue);

    // 激活完成：清 pending，保留 registered
    await PostStorage.setActivationPending(false);
    expect(PostStorage.isRegistered(), isTrue);
    expect(PostStorage.isActivationPending(), isFalse);

    await PostStorage.setRegistered(false);
  });

  test('registration_request_id 持久化与清除', () async {
    expect(PostStorage.getRegistrationRequestId(), isNull);

    await PostStorage.saveRegistrationRequestId('req-uuid-1');
    expect(PostStorage.getRegistrationRequestId(), 'req-uuid-1');

    // 直读底层 box 验证确已落盘（重启后由同一 Hive box 读回）
    expect(Hive.box('account').get('registration_request_id'), 'req-uuid-1');

    await PostStorage.clearRegistrationRequestId();
    expect(PostStorage.getRegistrationRequestId(), isNull);
  });
}
