import 'package:flutter/foundation.dart';

/// 消息模块测试数据（只在「设置 → 调试模式 → 消息模块测试」里开启）。
///
/// 设计原则：
/// 1. 完全离线，不访问后端、不写 Hive，关闭 App 即消失；
/// 2. 会话结构与 `/node/messages/dm/conversations` 返回的 JSON 一致，
///    这样会话行、聊天页可以直接复用真实组件，测试"所见即线上"；
/// 3. 覆盖私信模块的全部状态分支：待接受的请求（对方发起 / 我发起）、
///    已拒绝（对方发起 / 我发起）、已接受但无消息、有历史且部分未读、
///    置顶 + 免打扰 + 99+ 未读、超长昵称、长文本压力、发送失败。
class DmMockData extends ChangeNotifier {
  DmMockData._();
  static final DmMockData instance = DmMockData._();

  /// 测试用的"我"的 user_id。
  static const int selfUserId = 1;

  bool _enabled = false;
  bool get enabled => _enabled;

  final List<Map<String, dynamic>> _conversations = [];
  final Map<int, List<Map<String, dynamic>>> _messages = {};

  int _nextConversationId = 200;
  int _nextMessageId = 5000;
  int _nextSeq = 900;

  /// 打开后，下一条发送的消息会模拟失败（用于测试红色感叹号与重试）。
  bool failNextSend = false;

  /// 调试页开关：设置下一条消息是否模拟发送失败。
  void setFailNextSend(bool value) {
    failNextSend = value;
    notifyListeners();
  }

  /// 会话列表（测试模式下的数据源）。
  List<Map<String, dynamic>> get conversations => _conversations;

  /// 某个会话的全部消息，按 seq 升序。
  List<Map<String, dynamic>> messagesOf(int conversationId) =>
      List<Map<String, dynamic>>.from(_messages[conversationId] ?? const []);

  Map<String, dynamic>? conversationOf(int conversationId) {
    for (final item in _conversations) {
      if (item['id'] == conversationId) return item;
    }
    return null;
  }

  /// 开启测试模式；首次开启自动铺满全部场景数据。
  void enable() {
    _enabled = true;
    if (_conversations.isEmpty) _seed();
    notifyListeners();
  }

  void disable() {
    _enabled = false;
    notifyListeners();
  }

  /// 恢复初始场景（清掉手动模拟出来的变化）。
  void reset() {
    _conversations.clear();
    _messages.clear();
    _nextConversationId = 200;
    _nextMessageId = 5000;
    _nextSeq = 900;
    failNextSend = false;
    _seed();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 模拟事件：调试页上的按钮都调这里，消息页/聊天页监听后自动刷新。
  // ---------------------------------------------------------------------------

  /// 模拟"对方发来一条新消息"：给指定会话追加消息并增加未读。
  void incomingMessage({int? conversationId, String? content}) {
    final target = conversationOf(conversationId ?? 104);
    if (target == null || target['status'] != 'accepted') return;
    final id = target['id'] as int;
    final message = _newMessage(
      id,
      content ?? _nextIncomingText(),
      senderId: target['peer_user_id'] as int,
    );
    _messages[id]!.add(message);
    target['last_message'] = {
      'content': message['content'],
      'created_at': message['created_at'],
      'sender_id': message['sender_id'],
      'seq': message['seq'],
    };
    target['unread_count'] = (target['unread_count'] as int) + 1;
    notifyListeners();
  }

  /// 模拟一个全新陌生人的私信请求（对方发起，0 条历史消息）。
  void spawnStrangerRequest() {
    final id = _nextConversationId++;
    final names = ['新来的陌生人', '路过的小猫', '夜航船', '不确定的落日'];
    final assets = [
      'assets/mu/mu-login.png',
      'assets/mu/mu-flower.png',
      'assets/mu/mu-think.png',
      'assets/420px-Transparent_Akkarin.jpg',
    ];
    final index = id % names.length;
    _conversations.insert(
      0,
      _cap(
        id: id,
        name: names[index],
        asset: assets[index],
        status: 'pending',
        isRequester: false,
        history: const [],
      ),
    );
    _messages[id] = [];
    notifyListeners();
  }

  /// 对方接受了「我」发出的请求（用于 pending → accepted 的流转）。
  void peerAccepts(int conversationId) {
    final target = conversationOf(conversationId);
    if (target == null) return;
    target['status'] = 'accepted';
    target['can_send'] = true;
    target['accepted_at'] = DateTime.now().toUtc().toIso8601String();
    notifyListeners();
  }

  /// 对方拒绝了「我」发出的请求。
  void peerRejects(int conversationId) {    final target = conversationOf(conversationId);
    if (target == null) return;
    target['status'] = 'rejected';
    target['can_send'] = false;
    target['rejected_at'] = DateTime.now().toUtc().toIso8601String();
    notifyListeners();
  }

  /// 模拟「我发起一条新的私信请求」（对应消息页的「发起私信」）。
  void spawnOutgoingRequest() {
    final id = _nextConversationId++;
    _conversations.insert(
      0,
      _cap(
        id: id,
        name: '新联系人 ${id - 199}',
        asset: 'assets/mu/mu-true.png',
        status: 'pending',
        isRequester: true,
      ),
    );
    notifyListeners();
  }

  /// 我接受对方的请求。
  void accept(int conversationId) {
    final target = conversationOf(conversationId);
    if (target == null || target['status'] != 'pending') return;
    target['status'] = 'accepted';
    target['can_send'] = true;
    target['accepted_at'] = DateTime.now().toUtc().toIso8601String();
    notifyListeners();
  }

  /// 我拒绝对方的请求。
  void reject(int conversationId) {
    final target = conversationOf(conversationId);
    if (target == null || target['status'] != 'pending') return;
    target['status'] = 'rejected';
    target['can_send'] = false;
    target['rejected_at'] = DateTime.now().toUtc().toIso8601String();
    notifyListeners();
  }

  /// 一键清空未读。
  void markAllRead() {
    for (final item in _conversations) {
      item['unread_count'] = 0;
    }
    notifyListeners();
  }

  /// 自己发一条消息。返回消息对象，页面据此渲染"发送中"。
  Map<String, dynamic> sendMessage(int conversationId, String content) {
    final target = conversationOf(conversationId);
    final message = _newMessage(
      conversationId,
      content,
      senderId: selfUserId,
      localStatus: 'sending',
    );
    _messages[conversationId]!.add(message);
    target?['last_message'] = {
      'content': content,
      'created_at': message['created_at'],
      'sender_id': selfUserId,
      'seq': message['seq'],
    };
    notifyListeners();
    return message;
  }

  /// 发送结束：按 [failNextSend] 决定成功还是失败。
  void completeSend(int conversationId, int messageId) {
    final message = _messageOf(conversationId, messageId);
    if (message == null) return;
    message['local_status'] = failNextSend ? 'failed' : 'sent';
    if (failNextSend) failNextSend = false;
    notifyListeners();
  }

  /// 重试失败消息。
  void retrySend(int conversationId, int messageId) {
    final message = _messageOf(conversationId, messageId);
    if (message == null) return;
    message['local_status'] = 'sending';
    notifyListeners();
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      message['local_status'] = 'sent';
      notifyListeners();
    });
  }

  Map<String, dynamic>? _messageOf(int conversationId, int messageId) {
    for (final item in _messages[conversationId] ?? const []) {
      if (item['id'] == messageId) return item;
    }
    return null;
  }

  /// 把某个会话本地标记为已读（进入聊天页时调用）。
  void markRead(int conversationId) {
    final target = conversationOf(conversationId);
    if (target == null || target['unread_count'] == 0) return;
    target['unread_count'] = 0;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 内部：新消息与场景数据
  // ---------------------------------------------------------------------------

  int _incomingIndex = 0;
  static const List<String> _incomingTexts = [
    '在吗？刚看到你的消息',
    '这个想法我挺喜欢的，展开说说？',
    '哈哈哈哈，你这也太真实了',
    '那你后来是怎么处理的？',
    '我先去吃个饭，晚点回来聊',
    '刚看到广场那条，确实有点难顶',
    '你说的这个我也遇到过',
    '有道理，不过我还是有点犹豫',
  ];
  String _nextIncomingText() {
    final text = _incomingTexts[_incomingIndex % _incomingTexts.length];
    _incomingIndex++;
    return text;
  }

  Map<String, dynamic> _newMessage(
    int conversationId,
    String content, {
    required int senderId,
    String? localStatus,
  }) {
    final message = <String, dynamic>{
      'id': _nextMessageId++,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'seq': _nextSeq++,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (localStatus != null) message['local_status'] = localStatus;
    return message;
  }

  /// 构造一条会话。历史消息用 (内容, 是否我发的, 多少分钟前) 描述。
  Map<String, dynamic> _cap({
    required int id,
    required String name,
    required String asset,
    required String status,
    required bool isRequester,
    int unread = 0,
    bool muted = false,
    bool pinned = false,
    List<_Hist> history = const [],
  }) {
    final peerId = 1000 + id * 7;
    final messages = <Map<String, dynamic>>[];
    Map<String, dynamic>? last;
    for (final item in history) {
      final message = <String, dynamic>{
        'id': _nextMessageId++,
        'conversation_id': id,
        'sender_id': item.mine ? selfUserId : peerId,
        'content': item.content,
        'seq': _nextSeq++,
        'created_at': DateTime.now()
            .toUtc()
            .subtract(Duration(minutes: item.minutesAgo))
            .toIso8601String(),
      };
      messages.add(message);
      last = message;
    }
    _messages[id] = messages;
    final now = DateTime.now().toUtc();
    return <String, dynamic>{
      'id': id,
      'peer_user_id': peerId,
      'peer': {
        'user_id': peerId,
        'user_display_id': name,
        'avatar_url': null,
        'avatar_asset': asset,
      },
      'last_message': last == null
          ? null
          : {
              'content': last['content'],
              'created_at': last['created_at'],
              'sender_id': last['sender_id'],
              'seq': last['seq'],
            },
      'unread_count': unread,
      'muted': muted,
      'pinned': pinned,
      'status': status,
      'is_requester': isRequester,
      'can_send': status == 'accepted',
      'requested_at': status == 'pending'
          ? now.subtract(const Duration(hours: 2)).toIso8601String()
          : null,
      'accepted_at': status == 'accepted'
          ? now.subtract(const Duration(days: 2)).toIso8601String()
          : null,
      'rejected_at': status == 'rejected'
          ? now.subtract(const Duration(hours: 5)).toIso8601String()
          : null,
    };
  }

  /// 铺满全部场景，会话按时间倒序插入。
  void _seed() {
    // 1. 对方发来请求，已有几句往来 —— 会话行出现「请求」标签与同意/拒绝按钮。
    _conversations.add(
      _cap(
        id: 101,
        name: '林夕',
        asset: 'assets/mu/mu-think.png',
        status: 'pending',
        isRequester: false,
        unread: 2,
        history: const [
          _Hist('你好，看到你在广场发的那条帖子', false, 190),
          _Hist('我也在纠结类似的问题，想请教一下', false, 186),
        ],
      ),
    );

    // 2. 完全陌生的请求，没有历史消息 —— 测试"陌生对话刚发来申请"。
    _conversations.add(
      _cap(
        id: 102,
        name: '阿 ken',
        asset: 'assets/420px-Transparent_Akkarin.jpg',
        status: 'pending',
        isRequester: false,
        unread: 0,
      ),
    );

    // 3. 已建立但一条消息都没有 —— 测试空会话。
    _conversations.add(
      _cap(
        id: 103,
        name: '苏晚',
        asset: 'assets/mu/mu-flower.png',
        status: 'accepted',
        isRequester: true,
      ),
    );

    // 4. 已有历史消息，部分已读、部分未读，且刚来了新消息。
    _conversations.add(
      _cap(
        id: 104,
        name: '阿哲',
        asset: 'assets/mu/mu-flase.png',
        status: 'accepted',
        isRequester: true,
        unread: 3,
        history: const [
          _Hist('在吗？', false, 300),
          _Hist('在的，刚忙完', true, 296),
          _Hist('想问问你那个项目后来落地了吗', false, 290),
          _Hist('落地了一半，后面被砍了', true, 285),
          _Hist('那还挺可惜的', false, 280),
          _Hist('没办法，资源不够', true, 240),
          _Hist('你们当时用的什么方案？', false, 200),
          _Hist('自研的后端，前端直接 Flutter 一把梭', true, 190),
          _Hist('这个选择现在看还 OK 吗', false, 120),
          _Hist('还行，就是有些细节要补', true, 60),
          _Hist('比如？', false, 30),
          _Hist('比如消息模块的边界情况，最近在补', true, 8),
        ],
      ),
    );

    // 5. 置顶 + 免打扰 + 未读 —— 测试置顶底色、免打扰图标、红点。
    _conversations.add(
      _cap(
        id: 105,
        name: '豆豆',
        asset: 'assets/mu/mu-true.png',
        status: 'accepted',
        isRequester: false,
        unread: 5,
        muted: true,
        pinned: true,
        history: const [
          _Hist('今晚还去图书馆吗', false, 60 * 26),
          _Hist('不去了，今天有点累', true, 60 * 25),
          _Hist('那明天？', false, 60 * 24),
        ],
      ),
    );

    // 6. 超长昵称 + 99+ 未读 —— 测试昵称与摘要的省略号、角标。
    _conversations.add(
      _cap(
        id: 106,
        name: '橘子汽水味的夏天啊真的很好喝对吧',
        asset: 'assets/mu/reflash-puton.png',
        status: 'accepted',
        isRequester: true,
        unread: 128,
        history: const [
          _Hist('这个昵称是不是有点长', true, 60 * 40),
          _Hist('还行吧哈哈哈哈哈哈哈哈哈', false, 60 * 39),
        ],
      ),
    );

    // 7. 长文本压力：2000 字、换行、表情、连续多条 —— 测试气泡换行与最大宽度。
    final longText = '这是一条用于测试气泡宽度的长消息。' * 30;
    _conversations.add(
      _cap(
        id: 107,
        name: '老白',
        asset: 'assets/mu/reflash-waiting.png',
        status: 'accepted',
        isRequester: false,
        unread: 1,
        history: [
          _Hist(longText, false, 60 * 5),
          _Hist('第一条', true, 60 * 4),
          _Hist('第二条', true, 60 * 4),
          _Hist('第三条\n带一个换行', true, 60 * 3),
          _Hist('第四条 😀🎉 带表情', true, 60 * 2),
          _Hist('最后一条，应该出现在最下面', false, 60),
        ],
      ),
    );

    // 8. 我发起、对方拒绝 —— 24 小时冷却文案。
    _conversations.add(
      _cap(
        id: 108,
        name: '陈默',
        asset: 'assets/mu/mu-think.png',
        status: 'rejected',
        isRequester: true,
        history: const [_Hist('你好，可以聊两句吗', true, 60 * 3)],
      ),
    );

    // 9. 对方发起、我拒绝 —— 另一种 rejected 文案。
    _conversations.add(
      _cap(
        id: 109,
        name: '木木',
        asset: 'assets/mu/mu-flower.png',
        status: 'rejected',
        isRequester: false,
        history: const [_Hist('打扰了，想认识一下', false, 60 * 6)],
      ),
    );

    // 10. 我发起、等待对方接受 —— 可被"对方接受/拒绝"按钮流转。
    _conversations.add(
      _cap(
        id: 110,
        name: '沈七',
        asset: 'assets/mu/mu-login.png',
        status: 'pending',
        isRequester: true,
        history: const [_Hist('你好，之前在广场看到你的回复，想聊聊', true, 45)],
      ),
    );
  }
}

/// 场景数据里的一条历史消息：内容 + 谁发的 + 多少分钟前。
class _Hist {
  final String content;
  final bool mine;
  final int minutesAgo;
  const _Hist(this.content, this.mine, this.minutesAgo);
}
