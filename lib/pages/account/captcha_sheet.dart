import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/captcha_service.dart';
import '../../config/local.dart';
import '../../theme/app_colors.dart';

/// 验证码底部浮层：加载阿里云验证码页面（滑块/智能验证）。
///
/// 用户完成验证后以 `Navigator.pop(captchaVerifyParam)` 关闭；
/// 直接关闭浮层返回 null。失败时在浮层内展示原因并提供重试
/// （整页重载，规避 SDK「只能初始化一次」）。
class CaptchaSheet extends StatefulWidget {
  const CaptchaSheet({super.key});

  /// 弹出验证码浮层，返回 captchaVerifyParam；取消/失败关闭返回 null。
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CaptchaSheet(),
    );
  }

  @override
  State<CaptchaSheet> createState() => _CaptchaSheetState();
}

class _CaptchaSheetState extends State<CaptchaSheet> {
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
            debugPrint('[CaptchaSheet] Resource error: '
                '${err.errorType} — ${err.description}'),
      ))
      ..loadHtmlString(CaptchaPage.buildHtml(), baseUrl: kPowApiBase);
    setState(() => _controller = controller);
  }

  void _onMessage(JavaScriptMessage msg) {
    final parsed = CaptchaPage.parse(msg.message);
    if (!mounted) return;
    if (parsed.status == 'success' && parsed.token != null) {
      debugPrint('[CaptchaSheet] 验证通过 token len=${parsed.token!.length}');
      Navigator.of(context).pop(parsed.token);
      return;
    }
    if (parsed.message != null) {
      debugPrint('[CaptchaSheet] verify error: ${parsed.message}');
    }
    setState(() => _error = parsed.message ?? '验证失败，请重试');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: colors.register.pageBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('安全验证',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: onSurface)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 20, color: onSurface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 210,
              width: double.infinity,
              child: _error != null
                  ? _buildError(onSurface)
                  : _controller == null
                      ? const Center(child: CircularProgressIndicator())
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              WebViewWidget(controller: _controller!),
                              if (!_loaded)
                                const Center(
                                    child: CircularProgressIndicator()),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(Color onSurface) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!,
              style: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.7)),
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
