import 'package:flutter/material.dart';

/// Shows only the approved server avatar; network errors fall back to the default.
class UserAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final Color backgroundColor;
  final bool loading;

  /// 测试数据专用：直接显示本地资源图（消息模块测试模式使用），
  /// 为空时保持原有的「网络头像 → 默认图」逻辑。
  final String? assetPath;

  const UserAvatar({
    super.key,
    required this.url,
    required this.radius,
    required this.backgroundColor,
    this.loading = false,
    this.assetPath,
  });

  Widget _fallback() => Image.asset(
    'assets/420px-Transparent_Akkarin.jpg',
    width: radius * 2,
    height: radius * 2,
    fit: BoxFit.cover,
  );

  Widget _image() {
    if (assetPath != null && assetPath!.isNotEmpty) {
      return Image.asset(assetPath!, fit: BoxFit.cover);
    }
    if (url == null || url!.isEmpty) return _fallback();
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, error, stack) => _fallback(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: loading ? '头像上传审核中' : '用户头像',
      image: true,
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: backgroundColor),
              _image(),
            ],
          ),
        ),
      ),
    );
  }
}
