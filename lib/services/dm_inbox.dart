import 'package:flutter/foundation.dart';
import 'device_credential_store.dart';
import 'dm_api.dart';

class DmInbox {
  static final unread = ValueNotifier<int>(0);
  static final hasUnread = ValueNotifier<bool>(false);
  static int? visibleConversationId;
  static bool _busy = false;
  static bool _pending = false;

  static Future<void> refresh() async {
    if (_busy) {
      _pending = true;
      return;
    }
    _busy = true;
    DmApi? api;
    try {
      final sid = await DeviceCredentialStore.getSessionId();
      if (sid == null) {
        unread.value = 0;
        hasUnread.value = false;
        return;
      }
      api = await DmApi.open();
      final data = await api.request('unread');
      if (await DeviceCredentialStore.getSessionId() == api.sessionId) {
        unread.value = data['unread_count'] as int;
        hasUnread.value =
            (data['total_unread_count'] as int? ?? unread.value) > 0;
      }
    } catch (_) {
      // Keep the last confirmed count during a temporary network failure.
    } finally {
      api?.close();
      _busy = false;
      if (_pending) {
        _pending = false;
        refresh();
      }
    }
  }
}
