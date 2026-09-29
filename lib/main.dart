import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'services/binding_cache.dart';
import 'services/storage.dart';
import 'services/startup_posts.dart';
import 'services/timezone_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  final postsReady = PostStorage.init();
  final bindingReady = BindingCache.init();
  final timezoneReady = TimezoneService.init();
  await postsReady;
  // Start fetching before building the UI, while the native launch screen remains.
  StartupPosts.start();
  await Future.wait([bindingReady, timezoneReady]);
  runApp(TreeholeApp(key: appKey));
}
