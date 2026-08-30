import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/local.dart';
import '../../services/api.dart';
import '../../services/captcha_service.dart';

/// 阿里云验证码（一点即过/滑块/拼图）内嵌视图。
///
/// 嵌在注册页「通过一些测试」阶段的页面元素流上，与图片/文字共用同一套
/// 中心偏移定位。WebView 背景透明（控制器背景 + HTML body 均透明，
/// Android 默认 TLHC 渲染支持透明合成），页面上只露出验证控件本身。
/// 用户完成真实交互后经 [verifyHandler] 即时调服务端二次校验
/// （VerifyIntelligentCaptcha），通过拿到 Redis 凭证后经 [onVerified]
/// 回传；失败在原位展示原因（服务端已映射为带错误码的中文），可重试——
/// 整页重载以规避 SDK「只能初始化一次」。
class CaptchaView extends StatefulWidget {
  /// 即时校验：验证码脚本回调的 captchaVerifyParam 原样提交服务端，
  /// 返回 Redis 凭证 ticket；失败返回 null（ApiService.lastError 有原因）
  final Future<String?> Function(String captchaVerifyParam) verifyHandler;

  /// 校验通过回调，参数为服务端签发的凭证 ticket
  final ValueChanged<String> onVerified;

  /// 视图高度：需容纳挑战面板（拼图/滑块）在验证条下方展开
  final double height;

  const CaptchaView({
    super.key,
    required this.verifyHandler,
    required this.onVerified,
    this.height = 320,
  });

  @override
  State<CaptchaView> createState() => _CaptchaViewState();
}

class _CaptchaViewState extends State<CaptchaView> {
  WebViewController? _controller;
  String? _error;
  bool _useHostedPage = true;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  /// （重）加载验证码页面。优先加载站点托管页（真实 origin/cookie 环境，
  /// 官方 App 接入文档做法）；托管页主框架加载失败时回退到内联 HTML
  /// （内容一致）。整页重载同时重置 SDK 初始化状态。
  void _loadPage() {
    setState(() => _error = null);
    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('CaptchaChannel', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) async {
          // 校验页面脚本可用：托管页被 CSP 拦截时内联脚本不执行、也无资源
          // 错误事件，须主动探测。不可用则回退内联 HTML（loadHtmlString
          // 非 HTTP 响应、不受 CSP 限制，内容与托管页一致）
          var scriptOk = false;
          try {
            final result = await controller
                .runJavaScriptReturningResult(
                    'typeof window.__renderCaptcha === "function"');
            scriptOk = result.toString() == 'true';
          } catch (_) {}
          if (!scriptOk && _useHostedPage) {
            debugPrint('[CaptchaView] 托管页脚本不可用（CSP?），回退内联 HTML');
            if (!mounted) return;
            setState(() => _useHostedPage = false);
            _loadPage();
            return;
          }
          if (!mounted) return;
          try {
            await controller.runJavaScript('window.__renderCaptcha()');
          } catch (e) {
            debugPrint('[CaptchaView] render call failed: $e');
          }
        },
        onWebResourceError: (err) {
          debugPrint('[CaptchaView] Resource error: '
              '${err.errorType} — ${err.description}');
          if (err.isForMainFrame == true && _useHostedPage && mounted) {
            setState(() => _useHostedPage = false);
            _loadPage();
          }
        },
      ));
    if (_useHostedPage) {
      // 官方建议验证码页面禁用缓存，确保可及时获取最新验证码
      controller.loadRequest(
        CaptchaPage.pageUri,
        headers: const {'Cache-Control': 'no-cache'},
      );
    } else {
      controller.loadHtmlString(CaptchaPage.buildHtml(), baseUrl: kPowApiBase);
    }
    setState(() => _controller = controller);
  }

  Future<void> _onMessage(JavaScriptMessage msg) async {
    final parsed = CaptchaPage.parse(msg.message);
    if (!mounted) return;
    if (parsed.status == 'success' && parsed.token != null) {
      if (_verifying) return; // SDK 重复回调防护
      _verifying = true;
      debugPrint(
          '[CaptchaView] 验证通过，即时二次校验中 token len=${parsed.token!.length}');
      final ticket = await widget.verifyHandler(parsed.token!);
      if (!mounted) return;
      _verifying = false;
      if (ticket != null) {
        widget.onVerified(ticket);
        return;
      }
      setState(() => _error = ApiService.lastError ?? '验证失败，请重试');
      return;
    }
    if (parsed.message != null) {
      debugPrint('[CaptchaView] verify error: ${parsed.message}');
    }
    setState(() => _error = parsed.message ?? '验证失败，请重试');
  }

  @override
  Widget build(BuildContext context) {
    // 无加载指示：页面背景透明，SDK 渲染完成前自然为空白，
    // 避免加载图标在「通过一些测试」阶段闪现
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: _error != null
          ? _buildError(context)
          : _controller == null
              ? const SizedBox.shrink()
              : WebViewWidget(controller: _controller!),
    );
  }

  Widget _buildError(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(_error!,
                style: TextStyle(
                    fontSize: 13,
                    color: onSurface.withValues(alpha: 0.7)),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loadPage,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Icon(Icons.refresh,
                  size: 20, color: onSurface.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}
