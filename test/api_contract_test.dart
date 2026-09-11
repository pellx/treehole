import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:treehole/models/device_fingerprint.dart';
import 'package:treehole/services/api.dart';
import 'package:treehole/services/pow.dart';

/// API 契约 + lastError 生命周期测试。
///
/// 覆盖注册链路修复计划的验收点：
/// - 每次请求开始清理旧错误；成功清空；网络/超时/缺字段分别设置明确错误
/// - registerV2 携带 registration_request_id（幂等键）
/// - sms/register 不携带 CAPTCHA/PoW（与生产后端契约一致）
/// - registerV2/result 响应丢失恢复端点
void main() {
  final fp = DeviceFingerprint.unknown();
  const pow = PoWResult(challengeId: 'cid', nonce: 42);

  /// 用 [handler] 构造 MockClient 并注入 ApiService，返回捕获的请求
  List<http.Request> useClient(
    Future<http.Response> Function(http.Request req) handler,
  ) {
    final seen = <http.Request>[];
    ApiService.debugHttpClient = MockClient((req) async {
      seen.add(req);
      return handler(req);
    });
    return seen;
  }

  http.Response jsonRes(int status, Object body) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});

  tearDown(() => ApiService.lastError = null);

  group('registerV2', () {
    test('请求携带 registration_request_id；成功清空 lastError', () async {
      ApiService.lastError = '上一次残留的失败';
      final seen = useClient((req) async => jsonRes(201, {
            'user_token': 'tok123',
            'device_secret': 'sec456',
          }));

      final r = await ApiService.registerV2(
        userDisplayId: 'name',
        deviceFingerPrint: fp,
        captchaTicket: 'ticket',
        verificationPow: pow,
        registrationRequestId: 'req-uuid-1',
      );

      expect(r, isNotNull);
      expect(r!.userToken, 'tok123');
      expect(ApiService.lastError, isNull);

      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body['registration_request_id'], 'req-uuid-1');
      expect(body['verification_captcha_ticket'], 'ticket');
      expect(body['user_display_id'], 'name');
      expect(body.containsKey('verification_captcha'), isFalse);
    });

    test('服务端业务错误：lastError 取 message', () async {
      useClient((req) async => jsonRes(400, {'message': 'NAME_TAKEN'}));
      final r = await ApiService.registerV2(
        userDisplayId: 'name',
        deviceFingerPrint: fp,
        captchaTicket: 'ticket',
        verificationPow: pow,
        registrationRequestId: 'req-uuid-2',
      );
      expect(r, isNull);
      expect(ApiService.lastError, 'NAME_TAKEN');
    });

    test('超时：lastError 为服务器响应超时', () async {
      useClient((req) async => throw TimeoutException('timeout'));
      final r = await ApiService.registerV2(
        userDisplayId: 'name',
        deviceFingerPrint: fp,
        captchaTicket: 'ticket',
        verificationPow: pow,
      );
      expect(r, isNull);
      expect(ApiService.lastError, ApiService.errTimeout);
      expect(ApiService.isNetworkError(ApiService.lastError), isTrue);
    });

    test('断连：lastError 为网络连接失败', () async {
      useClient((req) async => throw http.ClientException('conn reset'));
      final r = await ApiService.registerV2(
        userDisplayId: 'name',
        deviceFingerPrint: fp,
        captchaTicket: 'ticket',
        verificationPow: pow,
      );
      expect(r, isNull);
      expect(ApiService.lastError, ApiService.errNetwork);
    });
  });

  group('fetchRegistrationResult（响应丢失恢复）', () {
    test('已完成：返回原注册结果', () async {
      final seen = useClient((req) async => jsonRes(200, {
            'user_token': 'tok',
            'device_secret': 'sec',
          }));
      final r = await ApiService.fetchRegistrationResult('req-uuid-1');
      expect(r, isNotNull);
      expect(r!.userToken, 'tok');
      expect(seen.single.url.path, endsWith('/user/registerV2/result'));
      expect(seen.single.url.queryParameters['registration_request_id'],
          'req-uuid-1');
    });

    test('未完成/不存在：返回 null 且不写 lastError', () async {
      ApiService.lastError = ApiService.errTimeout; // 来自 registerV2 的超时
      useClient(
          (req) async => jsonRes(404, {'message': 'REGISTRATION_RESULT_NOT_FOUND'}));
      final r = await ApiService.fetchRegistrationResult('req-uuid-x');
      expect(r, isNull);
      // 不覆盖 registerV2 的原始错误
      expect(ApiService.lastError, ApiService.errTimeout);
    });
  });

  group('check', () {
    test('成功清空旧错误并返回 registered', () async {
      ApiService.lastError = '残留';
      final seen = useClient((req) async => jsonRes(200, {'registered': true}));
      final r = await ApiService.check(deviceFingerPrint: fp);
      expect(r, isTrue);
      expect(ApiService.lastError, isNull);
      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body.containsKey('device_finger_print'), isTrue);
    });

    test('网络失败设置网络错误', () async {
      useClient((req) async => throw http.ClientException('down'));
      final r = await ApiService.check(deviceFingerPrint: fp);
      expect(r, isNull);
      expect(ApiService.lastError, ApiService.errNetwork);
    });

    test('响应缺少 registered 字段', () async {
      useClient((req) async => jsonRes(200, {'foo': 1}));
      final r = await ApiService.check(deviceFingerPrint: fp);
      expect(r, isNull);
      expect(ApiService.lastError, ApiService.errMissingField);
    });
  });

  group('verifyCaptcha', () {
    test('成功返回 ticket 并清空旧错误', () async {
      ApiService.lastError = '残留';
      useClient((req) async => jsonRes(200, {'captcha_ticket': 't-1'}));
      final t = await ApiService.verifyCaptcha('param');
      expect(t, 't-1');
      expect(ApiService.lastError, isNull);
    });

    test('缺少 ticket 字段 → 响应缺少字段', () async {
      useClient((req) async => jsonRes(200, {}));
      final t = await ApiService.verifyCaptcha('param');
      expect(t, isNull);
      expect(ApiService.lastError, ApiService.errMissingField);
    });
  });

  group('createBinding / createSession', () {
    test('createBinding 成功清空旧错误', () async {
      ApiService.lastError = '残留';
      final seen = useClient(
          (req) async => jsonRes(200, {'binding_id': 7, 'device_id': 9}));
      final r = await ApiService.createBinding(
        userToken: 'tok',
        fingerprintHash: 'hash',
        deviceSecret: 'sec',
      );
      expect(r, isNotNull);
      expect(ApiService.lastError, isNull);
      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body['user_token'], 'tok');
      expect(body['device_secret'], 'sec');
      expect(body['fingerprint_hash'], 'hash');
    });

    test('createSession 缺字段 → 响应缺少字段', () async {
      useClient((req) async => jsonRes(201, {'session_id': 1}));
      final r = await ApiService.createSession(
        userToken: 'tok',
        deviceSecret: 'sec',
        fingerprintHash: 'hash',
      );
      expect(r, isNull);
      expect(ApiService.lastError, ApiService.errMissingField);
    });

    test('createSession 网络错误不误判为业务错误', () async {
      useClient((req) async => throw TimeoutException('t'));
      final r = await ApiService.createSession(
        userToken: 'tok',
        deviceSecret: 'sec',
        fingerprintHash: 'hash',
      );
      expect(r, isNull);
      expect(ApiService.lastError, ApiService.errTimeout);
      // 绝不能是设备/账户类业务错误码
      expect(ApiService.lastError, isNot('DEVICE_NOT_BOUND'));
      expect(ApiService.lastError, isNot('DEVICE_SECRET_INVALID'));
    });

    test('createSession 成功清空旧错误', () async {
      ApiService.lastError = ApiService.errNetwork;
      useClient((req) async =>
          jsonRes(201, {'session_id': 3, 'session_secret': 'ss'}));
      final r = await ApiService.createSession(
        userToken: 'tok',
        deviceSecret: 'sec',
        fingerprintHash: 'hash',
      );
      expect(r, isNotNull);
      expect(ApiService.lastError, isNull);
    });
  });

  group('sms 契约（与生产后端一致，防漂移）', () {
    test('smsSend：携带 phone/scene/fingerprint_hash', () async {
      final seen = useClient((req) async => jsonRes(200, {
            'sent': true,
            'cooldown_seconds': 60,
            'mode': 'register',
          }));
      final r = await ApiService.smsSend(
        phone: '13800000000',
        scene: 'register',
        fingerprintHash: 'hash',
      );
      expect(r, isNotNull);
      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body['phone'], '13800000000');
      expect(body['scene'], 'register');
      expect(body['fingerprint_hash'], 'hash');
    });

    test('smsRegister：只携带手机号/验证码/昵称/指纹，不含 CAPTCHA/PoW',
        () async {
      final seen = useClient((req) async => jsonRes(201, {
            'user_token': 'tok',
            'device_secret': 'sec',
          }));
      final r = await ApiService.smsRegister(
        phone: '13800000000',
        code: '123456',
        userDisplayId: 'name',
        deviceFingerPrint: fp,
      );
      expect(r, isNotNull);
      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body.keys.toSet(),
          {'phone', 'code', 'user_display_id', 'device_finger_print'});
      expect(body.containsKey('verification_captcha'), isFalse);
      expect(body.containsKey('verification_pow'), isFalse);
    });
  });
}
