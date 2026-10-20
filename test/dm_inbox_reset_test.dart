import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/services/dm_inbox.dart';

void main() {
  test('reset clears the unread badge without a network request', () {
    DmInbox.unread.value = 5;
    DmInbox.hasUnread.value = true;

    DmInbox.reset();

    expect(DmInbox.unread.value, 0);
    expect(DmInbox.hasUnread.value, isFalse);
  });
}
