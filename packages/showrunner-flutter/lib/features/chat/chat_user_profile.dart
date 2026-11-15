final class ChatUserBadge {
  const ChatUserBadge({required this.title, required this.role, this.imageUrl});
  final String title, role;
  final String? imageUrl;
  Map<String, Object?> toJson() => {
    'title': title,
    'role': role,
    'imageUrl': ?imageUrl,
  };
}

final class ChatUserProfile {
  const ChatUserProfile({
    required this.id,
    required this.name,
    this.login = '',
    this.avatarUrl,
    this.badges = const [],
  });
  final String id, name, login;
  final String? avatarUrl;
  final List<ChatUserBadge> badges;
  Map<String, Object?> toJson() => {
    'userId': id,
    'name': name,
    'login': login,
    'avatarUrl': ?avatarUrl,
    'badges': badges.map((b) => b.toJson()).toList(),
  };
}
