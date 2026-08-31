import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 统一应用顶栏：左侧返回箭头 + 居中标题 + 可选右侧操作
class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  final bool automaticallyImplyLeading;
  final Color? backgroundColor;
  final double height;

  const AppAppBar({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
    this.automaticallyImplyLeading = true,
    this.backgroundColor,
    this.height = AppDimens.settingsBarHeight,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final barText = colors.common.barText;
    final bg = backgroundColor ?? colors.common.drawerHeaderBg;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: bg,
        statusBarIconBrightness:
            ThemeData.estimateBrightnessForColor(bg) == Brightness.light
                ? Brightness.dark
                : Brightness.light,
      ),
      child: Container(
        color: bg,
        child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: NavigationToolbar(
            middle: Text(
              title,
              style: TextStyle(
                fontSize: AppDimens.settingsBarHeight * 0.354,
                fontWeight: FontWeight.w500,
                color: barText,
              ),
            ),
            leading: automaticallyImplyLeading
                ? IconButton(
                    icon: Icon(
                      _useCupertinoBack(context)
                          ? Icons.arrow_back_ios
                          : Icons.arrow_back,
                      color: barText,
                      size: 24,
                    ),
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  )
                : const SizedBox(width: 48),
            trailing: trailing ?? const SizedBox(width: 48),
          ),
        ),
        ),
      ),
    );
  }

  bool _useCupertinoBack(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  @override
  Size get preferredSize => Size.fromHeight(height);
}

/// 统一页面外壳：顶栏 + 安全区主体
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? trailing;
  final bool resizeToAvoidBottomInset;
  final Color? backgroundColor;
  final VoidCallback? onBack;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.trailing,
    this.resizeToAvoidBottomInset = true,
    this.backgroundColor,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor:
          backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          AppAppBar(title: title, trailing: trailing, onBack: onBack),
          Expanded(child: body),
        ],
      ),
    );
  }
}
