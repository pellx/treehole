import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/local.dart';
import '../../services/captcha_service.dart';

/// 阿里云验证码（一点即过/滑块）内嵌视图。
///
/// 嵌在注册页「通过一些测试」阶段：用户完成真实点击验证后经 [onVerified]
/// 回传 captchaVerifyParam。失败时在原位展示原因（服务端已映射为带错误码的
/// 中文），可重试——整页重载以规避 SDK「只能初始化一次」。
class CaptchaView extends StatefulWidget {
  /// 验证通过回调，参数为 captchaVerifyParam（须立即提交业务请求）
  final ValueChanged<String> onVerified;

  const CaptchaView({super.key, required this.onVerified});

  @override
  State<CaptchaView> createState() => _CaptchaViewState();
}

class _CaptchaViewState extends State<CaptchaView> {
  WebViewController? _controller;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  /// （重）加载验证码页面。整页重载同时重置 SDK 初始化状态。
  void _loadPage() {
    setState(() {
      _error = null;
      _loaded = false;
    });
    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('CaptchaChannel', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
          controller.runJavaScript('window.__renderCaptcha()');
        },
        onWebResourceError: (err) =>
            debugPrint('[CaptchaView] Resource error: '
                '${err.errorType} — ${err.description}'),
      ))
      ..loadHtmlString(CaptchaPage.buildHtml(), baseUrl: kPowApiBase);
    setState(() => _controller = controller);
  }

  void _onMessage(JavaScriptMessage msg) {
    final parsed = CaptchaPage.parse(msg.message);
    if (!mounted) return;
    if (parsed.status == 'success' && parsed.token != null) {
      debugPrint('[CaptchaView] 验证通过 token len=${parsed.token!.length}');
      widget.onVerified(parsed.token!);
      return;
    }
    if (parsed.message != null) {
      debugPrint('[CaptchaView] verify error: ${parsed.message}');
    }
    setState(() => _error = parsed.message ?? '验证失败，请重试');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      width: double.infinity,
      child: _error != null
          ? _buildError(context)
          : _controller == null
              ? const Center(child: CircularProgressIndicator())
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      WebViewWidget(controller: _controller!),
                      if (!_loaded)
                        const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!,
              style: TextStyle(
                  fontSize: 13, color: onSurface.withValues(alpha: 0.7)),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _loadPage,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
