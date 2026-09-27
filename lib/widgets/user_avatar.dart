import 'package:flutter/material.dart';

/// Shows only the approved server avatar; network errors fall back to the default.
class UserAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final Color backgroundColor;
  final bool loading;

  const UserAvatar({
    super.key,
    required this.url,
    required this.radius,
    required this.backgroundColor,
    this.loading = false,
  });

  Widget _fallback() => Image.asset(
    'assets/420px-Transparent_Akkarin.jpg',
    width: radius * 2,
    height: radius * 2,
    fit: BoxFit.cover,
  );

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
              if (url == null || url!.isEmpty)
                _fallback()
              else
                Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => _fallback(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
