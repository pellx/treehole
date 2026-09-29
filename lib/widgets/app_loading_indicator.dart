import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 统一加载指示器：优先使用 CircularProgressIndicator，保留 GIF 作为占位
class AppLoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;
  final bool useGif;

  const AppLoadingIndicator({
    super.key,
    this.size = 40,
    this.color,
    this.useGif = false,
  });

  @override
  Widget build(BuildContext context) {
    if (useGif) {
      return Image(
        image: const AssetImage('assets/loading.gif'),
        width: size,
        height: size,
      );
    }
    final colors = Theme.of(context).extension<AppColors>()!;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: size < 30 ? 2.5 : 3,
        color: color ?? colors.common.green,
      ),
    );
  }
}

/// 全屏居中加载
class AppLoadingCenter extends StatelessWidget {
  final String? message;
  final bool showIndicator;
  const AppLoadingCenter({super.key, this.message, this.showIndicator = true});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIndicator) const AppLoadingIndicator(),
          if (message != null) ...[
            if (showIndicator) const SizedBox(height: 12),
            Text(
              message!,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
