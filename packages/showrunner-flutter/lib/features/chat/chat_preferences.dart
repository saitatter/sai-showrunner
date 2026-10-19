import 'chat_message.dart';
import 'safe_regex.dart';

enum ChatRuleMode { prefix, contains, regex }

final class ChatIgnoreRule {
  ChatIgnoreRule(this.mode, this.pattern) {
    if (pattern.isEmpty || pattern.length > 2048) {
      throw const FormatException(
        'Ignore patterns must contain 1–2048 characters.',
      );
    }
    if (mode == ChatRuleMode.regex) RegExp(pattern);
  }
  final ChatRuleMode mode;
  final String pattern;
  Future<bool> matches(String text) async => switch (mode) {
    ChatRuleMode.prefix => text.toLowerCase().startsWith(pattern.toLowerCase()),
    ChatRuleMode.contains => text.toLowerCase().contains(pattern.toLowerCase()),
    ChatRuleMode.regex => await findChatRegex(pattern, text) != null,
  };
  Map<String, String> toJson() => {'mode': mode.name, 'pattern': pattern};
}

/// Shared presentation policy. Hiding a message does not imply blocking commands.
final class ChatPreferences {
  ChatPreferences({
    this.fontSize = 14,
    this.font = 'system',
    this.timestamps = false,
    this.newestFirst = false,
    this.alternatingRows = false,
    this.platformIcons = true,
    this.roleBadges = true,
    this.animatedEmotes = true,
    this.hideCommands = false,
    this.preventIgnoredCommands = false,
    Set<String> ignoredUsers = const {},
    Set<String> highlightedUsers = const {},
    Set<ChatPermission> highlightedRoles = const {},
    List<String> highlightTerms = const [],
    List<ChatIgnoreRule> ignoreRules = const [],
  }) : ignoredUsers = Set.unmodifiable(ignoredUsers),
       highlightedUsers = Set.unmodifiable(highlightedUsers),
       highlightedRoles = Set.unmodifiable(highlightedRoles),
       highlightTerms = List.unmodifiable(highlightTerms),
       ignoreRules = List.unmodifiable(ignoreRules) {
    if (!fontSize.isFinite ||
        fontSize < 10 ||
        fontSize > 28 ||
        !['system', 'monospace', 'serif'].contains(font)) {
      throw const FormatException('Unsupported chat font or size.');
    }
    for (final id in {...ignoredUsers, ...highlightedUsers}) {
      if (id.length > 128 ||
          !RegExp(r'^(twitch|youtube):[^\s:]+$').hasMatch(id)) {
        throw const FormatException(
          'Users require platform:userId identities.',
        );
      }
    }
    if (ignoreRules.length > 32 ||
        highlightTerms.length > 32 ||
        highlightedUsers.length > 500 ||
        ignoredUsers.length > 500 ||
        highlightTerms.any((s) => s.isEmpty || s.length > 256)) {
      throw const FormatException('Chat rule limits exceeded.');
    }
  }
  final double fontSize;
  final String font;
  final bool timestamps,
      newestFirst,
      alternatingRows,
      platformIcons,
      roleBadges,
      animatedEmotes,
      hideCommands,
      preventIgnoredCommands;
  final Set<String> ignoredUsers, highlightedUsers;
  final Set<ChatPermission> highlightedRoles;
  final List<String> highlightTerms;
  final List<ChatIgnoreRule> ignoreRules;
  bool get hasIgnores =>
      ignoredUsers.isNotEmpty || ignoreRules.isNotEmpty || hideCommands;

  bool highlights(ChatMessage message) =>
      !message.deleted &&
      (highlightedUsers.contains(message.userIdentity) ||
          highlightedRoles.any(message.hasRole) ||
          highlightTerms.any(
            (s) => message.text.toLowerCase().contains(s.toLowerCase()),
          ));

  Future<bool> ignores(ChatMessage message) async {
    if (ignoredUsers.contains(message.userIdentity)) return true;
    for (final rule in ignoreRules) {
      if (await rule.matches(message.text)) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'fontSize': fontSize,
    'font': font,
    'timestamps': timestamps,
    'newestFirst': newestFirst,
    'alternatingRows': alternatingRows,
    'platformIcons': platformIcons,
    'roleBadges': roleBadges,
    'animatedEmotes': animatedEmotes,
    'hideCommands': hideCommands,
    'preventIgnoredCommands': preventIgnoredCommands,
    'ignoredUsers': ignoredUsers.toList(),
    'highlightedUsers': highlightedUsers.toList(),
    'highlightedRoles': highlightedRoles.map((r) => r.name).toList(),
    'highlightTerms': highlightTerms,
    'ignoreRules': ignoreRules.map((r) => r.toJson()).toList(),
  };

  factory ChatPreferences.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported chat preferences version.');
    }
    List<String> strings(String key) => (json[key] as List).cast<String>();
    return ChatPreferences(
      fontSize: (json['fontSize'] as num).toDouble(),
      font: json['font'] as String,
      timestamps: json['timestamps'] as bool,
      newestFirst: json['newestFirst'] as bool,
      alternatingRows: json['alternatingRows'] as bool,
      platformIcons: json['platformIcons'] as bool,
      roleBadges: json['roleBadges'] as bool,
      animatedEmotes: json['animatedEmotes'] as bool,
      hideCommands: json['hideCommands'] as bool,
      preventIgnoredCommands: json['preventIgnoredCommands'] as bool,
      ignoredUsers: strings('ignoredUsers').toSet(),
      highlightedUsers: strings('highlightedUsers').toSet(),
      highlightedRoles: strings(
        'highlightedRoles',
      ).map(ChatPermission.values.byName).toSet(),
      highlightTerms: strings('highlightTerms'),
      ignoreRules: [
        for (final rule in json['ignoreRules'] as List)
          ChatIgnoreRule(
            ChatRuleMode.values.byName(rule['mode'] as String),
            rule['pattern'] as String,
          ),
      ],
    );
  }
}
