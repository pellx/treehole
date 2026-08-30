import 'dart:convert';

import '../config/local.dart';

/// 阿里云验证码 2.0 页面构建与 JS 消息协议（可见交互式，滑块/智能验证）
///
/// 官方《App 侧发送验证请求实践教程》明确：App 内以 JS 自动触发无痕验证
/// 会被风控判为疑似攻击（F001）——无痕验证需采集真实用户行为且有动作触发。
/// 因此 App 场景应使用滑块/拼图等需要真实交互的形态：由可见 WebView 承载
/// H5 验证码页面，用户完成验证后经 JS channel 把 captchaVerifyParam 回传，
/// 再交给后端 VerifyIntelligentCaptcha 校验。
///
/// 接入方式遵循官方《Web/H5 客户端 V2 架构接入》文档：
///   - region/prefix 必须在 SDK 脚本加载之前写入全局变量
///     window.AliyunCaptchaConfig，initAliyunCaptcha 只接收其余参数；
///   - 场景 ID 参数名为 SceneId（大写 S、大写 I，小写 sceneId 不生效）；
///   - captchaVerifyParam 必须原样透传，禁止修改；无业务验证场景时回调
///     返回值中 bizResult 留空（false 会使 SDK 重新初始化作废本次状态）；
///   - initAliyunCaptcha 只能初始化一次，重试必须整页重载重置 SDK 状态
///     （SDK 未暴露 destroyCaptcha）；
///   - region 仅接受 'cn'/'sgp'，须与服务端 VerifyIntelligentCaptcha
///     端点地域一致，否则验证请求报错。
class CaptchaPage {
  CaptchaPage._();

  /// 构建验证码页面 HTML（prefix/region/sceneId 由 local.dart 注入）。
  ///
  /// 嵌入式（mode: 'embed'）渲染在 element 上：智能验证场景展示「点击开始/
  /// 滑块」控件，由用户真实点击触发；无痕验证场景则静默通过后直接回调。
  /// 页面不含自动触发逻辑（官方明确自动触发无痕验证可能不通过）。
  static String buildHtml() => '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script>
    // 官方要求：region/prefix 在引入 SDK 脚本之前保存到全局变量 AliyunCaptchaConfig
    window.AliyunCaptchaConfig = {
      region: "$kAliyunCaptchaRegion",
      prefix: "$kAliyunCaptchaPrefix"
    };
  </script>
  <script src="https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js"></script>
  <style>
    body { margin: 0; padding: 0; background: #fafafa; display: flex;
           align-items: center; justify-content: center; min-height: 100vh; }
    #captcha-element { width: 100%; }
  </style>
</head>
<body>
  <div id="captcha-element"></div>
  <button id="captcha-button" style="display:none"></button>
  <script>
    function __post(status, token, message) {
      CaptchaChannel.postMessage(JSON.stringify({status: status, token: token, message: message}));
    }

    window.__renderCaptcha = function() {
      function doRender() {
        if (typeof initAliyunCaptcha === 'undefined') return;
        try {
          initAliyunCaptcha({
            SceneId: "$kAliyunCaptchaSceneId",
            mode: 'embed',
            element: '#captcha-element',
            button: '#captcha-button',
            language: 'cn',
            slideStyle: { width: 320, height: 40 },
            immediate: true,
            captchaVerifyCallback: function(param, callback) {
              // ES5 兼容写法：经第二参 callback 回传验证结果；
              // 无业务验证场景 captchaResult 必填、bizResult 留空
              function done() {
                if (typeof callback === 'function') {
                  callback({captchaResult: true});
                }
              }
              var obj;
              try {
                obj = (typeof param === 'string') ? JSON.parse(param) : param;
              } catch (e) {
                obj = null;
              }
              obj = obj || {};
              // param 原样透传给后端；但下列降级形态服务端必然拒验，
              // 本地直接判失败，避免把无效参数当 token 提交
              if (obj.err && obj.err.code) {
                __post('error', null, 'INIT_FAIL ' + obj.err.code + ': '
                  + String(obj.err.msg || '').slice(0, 300));
                return done();
              }
              if (obj.failover === 'T') {
                __post('error', null, 'FAILOVER: 验证码服务降级');
                return done();
              }
              if (!obj.certifyId || String(obj.certifyId).length < 8) {
                __post('error', null, 'BAD_PARAM: ' + String(param).slice(0, 200));
                return done();
              }
              __post('success', (typeof param === 'string') ? param : JSON.stringify(param), null);
              return done();
            },
            onBizResultCallback: function(res) {
              // 无业务验证场景，无需处理
            },
            getInstance: function(instance) {
              // 官方固定写法：绑定验证码实例（当前无进一步操作）
            },
            onError: function(err) {
              // 初始化接口请求失败/超时
              __post('error', null, 'onError: ' + JSON.stringify(err).slice(0, 300));
            }
          });
        } catch (e) {
          __post('error', null, 'render failed: ' + e.message);
        }
      }

      if (typeof initAliyunCaptcha !== 'undefined') {
        doRender();
      } else {
        var attempts = 0;
        var interval = setInterval(function() {
          attempts++;
          if (typeof initAliyunCaptcha !== 'undefined') {
            clearInterval(interval);
            doRender();
          } else if (attempts >= 90) {
            clearInterval(interval);
            __post('error', null, 'AliyunCaptcha script load timeout (45s)');
          }
        }, 500);
      }
    };
  </script>
</body>
</html>
''';

  /// JS channel 回传消息
  static CaptchaMessage parse(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return CaptchaMessage(
        status: data['status'] as String? ?? 'error',
        token: data['token'] as String?,
        message: data['message'] as String?,
      );
    } catch (_) {
      return const CaptchaMessage(status: 'error', message: '验证码消息解析失败');
    }
  }
}

/// buildHtml 页面经 CaptchaChannel 回传的一条消息
class CaptchaMessage {
  final String status; // success | error
  final String? token; // captchaVerifyParam（status=success 时有效）
  final String? message; // 失败原因（status=error 时有效）

  const CaptchaMessage({required this.status, this.token, this.message});
}
