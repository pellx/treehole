import 'dart:async';
import 'package:flutter/widgets.dart';

/// Keep the platform launch screen until Square has its first usable result.
class StartupFrame {
  static Timer? _timeout;
  static bool _waiting = false;

  static void defer() {
    _waiting = true;
    WidgetsBinding.instance.deferFirstFrame();
    // A failed or slow network must not leave the launch screen stuck forever.
    _timeout = Timer(const Duration(seconds: 12), ready);
  }

  static void ready() {
    if (!_waiting) return;
    _waiting = false;
    _timeout?.cancel();
    _timeout = null;
    WidgetsBinding.instance.allowFirstFrame();
  }
}
