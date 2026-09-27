import 'dart:async';

import 'package:flutter/material.dart';

final _activeToastDismissals = Expando<VoidCallback>();

/// 普通反馈统一使用下半部小提示；重要内容使用居中的确认弹窗。
/// 返回关闭函数；同一页面的新提示会替换旧提示，不占用页面布局。
VoidCallback showAppToast(
  BuildContext context, {
  required String message,
  Duration duration = const Duration(milliseconds: 1500),
}) {
  final overlay = Overlay.of(context);
  _activeToastDismissals[overlay]?.call();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 100),
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  var removed = false;
  Timer? timer;
  void dismiss() {
    if (removed) return;
    removed = true;
    timer?.cancel();
    if (_activeToastDismissals[overlay] == dismiss) {
      _activeToastDismissals[overlay] = null;
    }
    entry.remove();
    entry.dispose();
  }

  _activeToastDismissals[overlay] = dismiss;
  timer = Timer(duration, dismiss);
  return dismiss;
}
