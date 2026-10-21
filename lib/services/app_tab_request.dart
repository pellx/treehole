import 'package:flutter/foundation.dart';

/// 跨页面请求切换主界面底部 Tab。
///
/// 目前只有「设置 → 消息模块测试」使用：点完测试数据后直接跳到消息页，
/// 省得用户自己返回再点底部导航。
class AppTabRequest {
  AppTabRequest._();

  static final ValueNotifier<int?> pending = ValueNotifier<int?>(null);

  static void go(int index) => pending.value = index;
}
