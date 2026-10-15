class Profile {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final bool isAdmin;
  final String accountStatus;

  Profile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.isAdmin = false,
    this.accountStatus = 'active',
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        username: (j['username'] ?? '') as String,
        displayName: (j['display_name'] ?? j['username'] ?? '') as String,
        avatarUrl: j['avatar_url'] as String?,
        bio: j['bio'] as String?,
        isAdmin: j['is_admin'] == true,
        accountStatus: (j['account_status'] ?? 'active') as String,
      );

  Profile copyWith({bool? isAdmin}) => Profile(
        id: id,
        username: username,
        displayName: displayName,
        avatarUrl: avatarUrl,
        bio: bio,
        isAdmin: isAdmin ?? this.isAdmin,
        accountStatus: accountStatus,
      );
}

class ChatItem {
  final String id;
  final bool isGroup;
  final String title;
  final String? avatarUrl;
  final String? otherUserId;
  final String preview;
  final DateTime? lastMessageAt;
  final int unread;
  final bool archived;
  final bool muted;

  ChatItem({
    required this.id,
    required this.isGroup,
    required this.title,
    this.avatarUrl,
    this.otherUserId,
    this.preview = '',
    this.lastMessageAt,
    this.unread = 0,
    this.archived = false,
    this.muted = false,
  });
}

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String? content;
  final String? mediaUrl;
  final String? mediaType;
  final String? mediaName;
  final int? mediaSize;
  final DateTime createdAt;
  final bool deleted;
  final bool edited;
  final String? replyToId;
  final bool pending;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.content,
    this.mediaUrl,
    this.mediaType,
    this.mediaName,
    this.mediaSize,
    required this.createdAt,
    this.deleted = false,
    this.edited = false,
    this.replyToId,
    this.pending = false,
  });

  static const columns =
      'id, chat_id, sender_id, content, media_url, media_type, media_name, media_size, created_at, deleted, reply_to_id, edited';

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        chatId: j['chat_id'] as String,
        senderId: j['sender_id'] as String,
        content: j['content'] as String?,
        mediaUrl: j['media_url'] as String?,
        mediaType: j['media_type'] as String?,
        mediaName: j['media_name'] as String?,
        mediaSize: (j['media_size'] as num?)?.toInt(),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        deleted: j['deleted'] == true,
        edited: j['edited'] == true,
        replyToId: j['reply_to_id'] as String?,
      );
}

class Relationship {
  final String id;
  final String requesterId;
  final String addresseeId;
  final String status; // pending | accepted | ...
  Relationship(this.id, this.requesterId, this.addresseeId, this.status);
  factory Relationship.fromJson(Map<String, dynamic> j) =>
      Relationship(j['id'] as String, j['requester_id'] as String, j['addressee_id'] as String, j['status'] as String);
}

class ContactRow {
  final Relationship rel;
  final Profile profile;
  ContactRow(this.rel, this.profile);
}
