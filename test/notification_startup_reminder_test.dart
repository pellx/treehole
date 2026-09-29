import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:treehole/services/dm_notifications.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'treehole-notification-reminder-',
    );
    Hive.init(temporaryDirectory.path);
  });

  tearDown(() async {
    await Hive.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('startup reminder is consumed before any user decision', () async {
    expect(await DmNotifications.consumeStartupReminder(), isTrue);
    // Dismissing the dialog does not call requestPermission or set requested.
    expect(Hive.box('dm_notification_preferences').get('requested'), isNull);
    expect(await DmNotifications.consumeStartupReminder(), isFalse);
  });

  test('second launch stays silent after preferences are reopened', () async {
    expect(await DmNotifications.consumeStartupReminder(), isTrue);
    await Hive.close();
    Hive.init(temporaryDirectory.path);

    expect(await DmNotifications.consumeStartupReminder(), isFalse);
  });

  test(
    'previous native permission requests suppress the new reminder',
    () async {
      final box = await Hive.openBox('dm_notification_preferences');
      await box.put('requested', true);

      expect(await DmNotifications.consumeStartupReminder(), isFalse);
      await Hive.close();
      Hive.init(temporaryDirectory.path);
      expect(await DmNotifications.consumeStartupReminder(), isFalse);
    },
  );
}
