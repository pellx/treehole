import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens_register.dart';
import '../settings/settings_navigation.dart';
import 'sms_login_page.dart';
import 'sms_register_page.dart';

/// 设备已注册引导页。
///
/// RegisterPage 检测到设备环境已注册后替换进入（pushReplacement），
/// 提供两条继续路径（均走手机号验证码）与一行求助小字：
///   1. 通过绑定的手机号找回 → [SmsLoginPage]
///   2. 注册新账号（手机号） → [SmsRegisterPage]
///
/// 子页完成找回/注册后 pop(true)，本页随之退出并回到进入前的页面；
/// 取消返回时停留本页，可换另一条路径。
class DeviceRegisteredPage extends StatelessWidget {
  const DeviceRegisteredPage({super.key});

  Future<void> _open(BuildContext context, Widget page) async {
    final success =
        await Navigator.of(context).push<bool>(bottomUpRoute<bool>(page));
    if (success == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Stack 内相对中心偏移定位（与注册页同一套坐标系）
  Widget _layer({required double vOffset, required Widget child}) {
    return Positioned.fill(
      child: Align(
        alignment: Alignment.center,
        child: Transform.translate(
          offset: Offset(0, vOffset),
          child: child,
        ),
      ),
    );
  }

  Widget _actionButton(
    AppColors colors,
    String label,
    VoidCallback onPressed, {
    required double vOffset,
  }) {
    return _layer(
      vOffset: vOffset,
      child: SizedBox(
        width: RegisterDimens.deviceRegisteredButtonWidth,
        height: RegisterDimens.deviceRegisteredButtonHeight,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.register.buttonBg,
            foregroundColor: colors.register.buttonText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                  RegisterDimens.deviceRegisteredButtonRadius),
              side: BorderSide(
                color: colors.register.buttonBorderColor,
                width: RegisterDimens.deviceRegisteredButtonBorderWidth,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: RegisterDimens.deviceRegisteredButtonFontSize,
              fontWeight: FontWeight.w500,
              letterSpacing: RegisterDimens.deviceRegisteredButtonLetterSpacing,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: colors.register.pageBg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 中心 + VOffset → Positioned 左上角（与注册页一致）
            double centerLeft(double width, double hOffset) =>
                constraints.maxWidth / 2 - width / 2 + hOffset;
            double centerTop(double height, double vOffset) =>
                constraints.maxHeight / 2 - height / 2 + vOffset;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // 白色椭圆背景
                Positioned(
                  left: centerLeft(
                    RegisterDimens.ellipseWidth,
                    RegisterDimens.ellipseHOffset,
                  ),
                  top: centerTop(
                    RegisterDimens.ellipseHeight,
                    RegisterDimens.ellipseVOffset,
                  ),
                  width: RegisterDimens.ellipseWidth,
                  height: RegisterDimens.ellipseHeight,
                  child: IgnorePointer(
                    child: ClipOval(
                      child: ColoredBox(color: colors.register.ellipseBg),
                    ),
                  ),
                ),
                // 插图（与注册页「已注册」阶段一致）
                Positioned(
                  left: centerLeft(
                    RegisterDimens.flaseWidth,
                    RegisterDimens.flaseHOffset,
                  ),
                  top: centerTop(
                    RegisterDimens.flaseHeight,
                    RegisterDimens.flaseVOffset,
                  ),
                  width: RegisterDimens.flaseWidth,
                  height: RegisterDimens.flaseHeight,
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/mu/mu-flase.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                // 标题
                _layer(
                  vOffset: RegisterDimens.phaseTitleVOffset,
                  child: Text(
                    '该设备环境已注册，该如何继续',
                    style: TextStyle(
                      fontSize: RegisterDimens.phaseTitleFontSize,
                      fontWeight: FontWeight.bold,
                      color: onSurface,
                    ),
                  ),
                ),
                // 按钮 1：通过绑定的手机号找回
                _actionButton(
                  colors,
                  '通过绑定的手机号找回',
                  () => _open(context, const SmsLoginPage()),
                  vOffset: RegisterDimens.deviceRegisteredButton1VOffset,
                ),
                // 按钮 2：注册新账号（手机号）
                _actionButton(
                  colors,
                  '注册新账号（手机号）',
                  () => _open(context, const SmsRegisterPage()),
                  vOffset: RegisterDimens.deviceRegisteredButton2VOffset,
                ),
                // 一行小字
                _layer(
                  vOffset: RegisterDimens.deviceRegisteredHintVOffset,
                  child: Text(
                    '如需帮助，请联系我们',
                    style: TextStyle(
                      fontSize: RegisterDimens.deviceRegisteredHintFontSize,
                      color: onSurface.withValues(
                        alpha: RegisterDimens.deviceRegisteredHintAlpha,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
