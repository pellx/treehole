import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'services/binding_cache.dart';
import 'services/storage.dart';
import 'services/timezone_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // 两套 Hive box 并行打开，缩短启动阻塞
  await Future.wait([
    PostStorage.init(),
    BindingCache.init(),
    TimezoneService.init(),
  ]);
  runApp(TreeholeApp(key: appKey));
}
