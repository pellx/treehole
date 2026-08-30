class ChatConversation {
  final int id;
  final int peerUserId;
  final String peerDisplayId;
  final String? lastPreview;
  final String? lastMessageAt;
  final int? lastSenderUserId;
  final int unreadCount;

  const ChatConversation({
    required this.id,
    required this.peerUserId,
    required this.peerDisplayId,
    this.lastPreview,
    this.lastMessageAt,
    this.lastSenderUserId,
    this.unreadCount = 0,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    return ChatConversation(
      id: _asInt(json['id']),
      peerUserId: _asInt(json['peer_user_id']),
      peerDisplayId: json['peer_display_id'] as String? ?? '用户',
      lastPreview: json['last_preview'] as String?,
      lastMessageAt: json['last_message_at'] as String?,
      lastSenderUserId: json['last_sender_user_id'] == null
          ? null
          : _asInt(json['last_sender_user_id']),
      unreadCount: _asInt(json['unread_count']),
    );
  }

  ChatConversation copyWith({
    String? peerDisplayId,
    String? lastPreview,
    String? lastMessageAt,
    int? lastSenderUserId,
    int? unreadCount,
  }) {
    return ChatConversation(
      id: id,
      peerUserId: peerUserId,
      peerDisplayId: peerDisplayId ?? this.peerDisplayId,
      lastPreview: lastPreview ?? this.lastPreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastSenderUserId: lastSenderUserId ?? this.lastSenderUserId,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class ChatMessage {
  final int id;
  final int conversationId;
  final int senderUserId;
  final String body;
  final String createdAt;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderUserId,
    required this.body,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: _asInt(json['id']),
      conversationId: _asInt(json['conversation_id']),
      senderUserId: _asInt(json['sender_user_id']),
      body: json['body'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class ChatLookupResult {
  final int userId;
  final String userDisplayId;

  const ChatLookupResult({required this.userId, required this.userDisplayId});

  factory ChatLookupResult.fromJson(Map<String, dynamic> json) {
    return ChatLookupResult(
      userId: _asInt(json['user_id']),
      userDisplayId: json['user_display_id'] as String? ?? '',
    );
  }
}

class ChatRealtimePayload {
  final ChatConversation conversation;
  final ChatMessage message;

  const ChatRealtimePayload({
    required this.conversation,
    required this.message,
  });
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}
