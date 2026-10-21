import 'package:flutter_test/flutter_test.dart';
import 'package:treehole/services/dm_mock_data.dart';

void main() {
  final store = DmMockData.instance;

  setUp(() {
    store.enable();
    store.reset();
  });

  test('测试数据覆盖私信模块的关键状态', () {
    expect(store.conversations.length, 10);

    final statuses = store.conversations
        .map((item) => '${item['status']}/${item['is_requester']}')
        .toSet();
    expect(
      statuses,
      containsAll(<String>[
        'pending/false',
        'pending/true',
        'accepted/true',
        'accepted/false',
        'rejected/true',
        'rejected/false',
      ]),
    );

    // 置顶、免打扰、99+ 未读、空会话、超长昵称各至少一条。
    expect(store.conversations.any((item) => item['pinned'] == true), isTrue);
    expect(store.conversations.any((item) => item['muted'] == true), isTrue);
    expect(
      store.conversations.any((item) => (item['unread_count'] as int) >= 99),
      isTrue,
    );
    expect(
      store.conversations.any((item) => item['last_message'] == null),
      isTrue,
    );
    expect(
      store.conversations.any(
        (item) => (item['peer'] as Map)['avatar_asset'] != null,
      ),
      isTrue,
    );
  });

  test('接受 / 拒绝请求会改变会话状态', () {
    store.accept(101);
    expect(store.conversationOf(101)!['status'], 'accepted');
    expect(store.conversationOf(101)!['can_send'], isTrue);

    store.reject(102);
    expect(store.conversationOf(102)!['status'], 'rejected');
    expect(store.conversationOf(102)!['can_send'], isFalse);
  });

  test('对方发来新消息会增加未读并更新摘要', () {
    final before = store.conversationOf(104)!['unread_count'] as int;
    store.incomingMessage(conversationId: 104);
    final after = store.conversationOf(104)!;
    expect(after['unread_count'], before + 1);
    expect((after['last_message'] as Map)['content'], isNotEmpty);
    expect(
      store.messagesOf(104).last['sender_id'],
      after['peer_user_id'],
    );
  });

  test('发送消息先进入发送中，失败后可重试成功', () {
    store.setFailNextSend(true);
    final message = store.sendMessage(104, '测试发送');
    expect(message['local_status'], 'sending');

    store.completeSend(104, message['id'] as int);
    expect(store.messagesOf(104).last['local_status'], 'failed');
    // 失败开关只生效一次。
    expect(store.failNextSend, isFalse);

    store.retrySend(104, message['id'] as int);
    expect(store.messagesOf(104).last['local_status'], 'sending');
  });

  test('新增陌生请求与我方请求都会插入会话', () {
    final before = store.conversations.length;
    store.spawnStrangerRequest();
    store.spawnOutgoingRequest();
    expect(store.conversations.length, before + 2);
    expect(store.conversations.first['is_requester'], isTrue);
    expect(store.conversations.last['status'], 'pending');
  });

  test('标记已读与重置', () {
    store.markAllRead();
    expect(
      store.conversations.every((item) => item['unread_count'] == 0),
      isTrue,
    );

    store.reset();
    expect(store.conversations.length, 10);
    expect(
      store.conversations.any((item) => (item['unread_count'] as int) > 0),
      isTrue,
    );
  });
}
