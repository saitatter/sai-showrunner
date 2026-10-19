import 'chat_message.dart';
import 'safe_regex.dart';

enum CommandMatchMode { command, exact, startsWith, contains, regex }

enum CommandGrant { allow, deny }

enum CommandArgumentMode { words, quoted, remainder }

final class ChatCommand {
  ChatCommand({
    required this.id,
    required this.name,
    required this.pattern,
    required this.automationFile,
    List<String> aliases = const [],
    Set<ChatPlatform> platforms = const {
      ChatPlatform.twitch,
      ChatPlatform.youtube,
    },
    this.enabled = true,
    this.caseSensitive = false,
    this.matchMode = CommandMatchMode.command,
    this.argumentMode = CommandArgumentMode.quoted,
    this.permission = ChatPermission.everyone,
    this.globalCooldown = Duration.zero,
    this.userCooldown = Duration.zero,
    this.minimumArguments = 0,
    this.queueId = 'default',
    this.grant = CommandGrant.allow,
    Set<ChatPermission> roles = const {},
    Set<String> users = const {},
    Set<String> groups = const {},
    Set<ChatOrigin> origins = const {ChatOrigin.chat},
    this.ignoreBots = true,
    this.ignoreInternal = true,
    this.broadcasterBypass = false,
    this.persistCounter = true,
    this.persistUserCounter = true,
    this.group = '',
    this.includeInList = true,
  }) : roles = Set.unmodifiable(roles),
       users = Set.unmodifiable(users),
       groups = Set.unmodifiable(groups),
       origins = Set.unmodifiable(origins),
       aliases = List.unmodifiable(aliases),
       platforms = Set.unmodifiable(platforms) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid command ID.');
    }
    if (name.trim().isEmpty ||
        pattern.trim().isEmpty ||
        pattern != pattern.trim()) {
      throw const FormatException('Command name and pattern are required.');
    }
    if (automationFile.isEmpty ||
        automationFile.contains('/') ||
        automationFile.contains('\\') ||
        !automationFile.endsWith('.yaml')) {
      throw const FormatException('Select a saved automation.');
    }
    if (platforms.isEmpty) {
      throw const FormatException('Select at least one platform.');
    }
    if (queueId.trim().isEmpty ||
        queueId.contains('/') ||
        queueId.contains('\\')) {
      throw const FormatException('Invalid queue ID.');
    }
    if (globalCooldown.isNegative ||
        userCooldown.isNegative ||
        minimumArguments < 0) {
      throw const FormatException(
        'Cooldowns and argument count cannot be negative.',
      );
    }
    for (final value in [pattern, ...aliases]) {
      if (value.trim().isEmpty || value != value.trim()) {
        throw const FormatException('Empty command alias.');
      }
      if (matchMode == CommandMatchMode.command &&
          RegExp(r'\s').hasMatch(value)) {
        throw const FormatException('Command names cannot contain spaces.');
      }
    }
    if (origins.isEmpty) {
      throw const FormatException('Select at least one message source.');
    }
    for (final user in users) {
      if (!RegExp(r'^(twitch|youtube):[^\s:]+$').hasMatch(user)) {
        throw const FormatException(
          'Users must use platform:userId, for example twitch:123.',
        );
      }
    }
    if (groups.any(
      (g) => g.trim().isEmpty || g.contains('/') || g.contains('\\'),
    )) {
      throw const FormatException('Invalid viewer group ID.');
    }
    if (matchMode == CommandMatchMode.regex) {
      for (final expression in [pattern, ...aliases]) {
        if (expression.length > 2048) {
          throw const FormatException('Regex is too long.');
        }
        RegExp(expression, caseSensitive: caseSensitive);
      }
    }
    final patterns = [
      pattern,
      ...aliases,
    ].map((s) => caseSensitive ? s : s.toLowerCase()).toList();
    if (patterns.toSet().length != patterns.length) {
      throw const FormatException('Command aliases must be unique.');
    }
  }

  final String id, name, pattern, automationFile, queueId, group;
  final CommandGrant grant;
  final Set<ChatPermission> roles;
  final Set<String> users, groups;
  final Set<ChatOrigin> origins;
  final bool ignoreBots,
      ignoreInternal,
      broadcasterBypass,
      persistCounter,
      persistUserCounter,
      includeInList;

  Future<CommandMatch?> matchAsync(String text) async {
    if (matchMode != CommandMatchMode.regex) return match(text);
    for (final expression in [pattern, ...aliases]) {
      final result = await findChatRegex(
        expression,
        text,
        caseSensitive: caseSensitive,
      );
      if (result == null) continue;
      final groups = (result['groups'] as List).cast<String?>();
      return CommandMatch(
        groups.first ?? '',
        text.substring(result['end'] as int).trim(),
        groups.skip(1).map((g) => g ?? '').toList(),
        captures: {
          for (var i = 0; i < groups.length; i++) '$i': groups[i],
          ...Map<String, String?>.from(result['named'] as Map),
        },
      );
    }
    return null;
  }

  bool grants(ChatMessage message, Set<String> memberships) {
    if (broadcasterBypass && message.isBroadcaster) return true;
    if (!message.permits(permission)) return false;
    final empty = roles.isEmpty && users.isEmpty && groups.isEmpty;
    final listed =
        users.contains(message.userIdentity) ||
        roles.any(message.hasRole) ||
        groups.any(memberships.contains);
    return grant == CommandGrant.allow ? empty || listed : !listed;
  }

  final List<String> aliases;
  final Set<ChatPlatform> platforms;
  final bool enabled, caseSensitive;
  final CommandMatchMode matchMode;
  final CommandArgumentMode argumentMode;
  final ChatPermission permission;
  final Duration globalCooldown, userCooldown;
  final int minimumArguments;

  CommandMatch? match(String text) => matchCommandText(
    text,
    [pattern, ...aliases],
    mode: matchMode,
    argumentMode: argumentMode,
    caseSensitive: caseSensitive,
  );

  Map<String, dynamic> toJson() => {
    'grant': grant.name,
    'roles': roles.map((r) => r.name).toList(),
    'users': users.toList(),
    'groups': groups.toList(),
    'origins': origins.map((o) => o.name).toList(),
    'ignoreBots': ignoreBots,
    'ignoreInternal': ignoreInternal,
    'broadcasterBypass': broadcasterBypass,
    'persistCounter': persistCounter,
    'persistUserCounter': persistUserCounter,
    'group': group,
    'includeInList': includeInList,
    'id': id,
    'name': name,
    'pattern': pattern,
    'automationFile': automationFile,
    'queueId': queueId,
    'aliases': aliases,
    'platforms': platforms.map((p) => p.name).toList(),
    'enabled': enabled,
    'caseSensitive': caseSensitive,
    'matchMode': matchMode.name,
    'argumentMode': argumentMode.name,
    'permission': permission.name,
    'globalCooldownMs': globalCooldown.inMilliseconds,
    'userCooldownMs': userCooldown.inMilliseconds,
    'minimumArguments': minimumArguments,
  };

  factory ChatCommand.fromJson(Map<String, dynamic> json) => ChatCommand(
    grant: CommandGrant.values.byName(json['grant'] as String? ?? 'allow'),
    roles: (json['roles'] as List? ?? [])
        .map((r) => ChatPermission.values.byName(r as String))
        .toSet(),
    users: (json['users'] as List? ?? []).cast<String>().toSet(),
    groups: (json['groups'] as List? ?? []).cast<String>().toSet(),
    origins: (json['origins'] as List? ?? ['chat'])
        .map((o) => ChatOrigin.values.byName(o as String))
        .toSet(),
    ignoreBots: json['ignoreBots'] as bool? ?? true,
    ignoreInternal: json['ignoreInternal'] as bool? ?? true,
    broadcasterBypass: json['broadcasterBypass'] as bool? ?? false,
    persistCounter: json['persistCounter'] as bool? ?? true,
    persistUserCounter: json['persistUserCounter'] as bool? ?? true,
    group: json['group'] as String? ?? '',
    includeInList: json['includeInList'] as bool? ?? true,
    id: json['id'] as String,
    name: json['name'] as String,
    pattern: json['pattern'] as String,
    automationFile: json['automationFile'] as String,
    queueId: json['queueId'] as String,
    aliases: (json['aliases'] as List).cast<String>(),
    platforms: (json['platforms'] as List)
        .map((p) => ChatPlatform.values.byName(p as String))
        .toSet(),
    enabled: json['enabled'] as bool,
    caseSensitive: json['caseSensitive'] as bool,
    matchMode: CommandMatchMode.values.byName(json['matchMode'] as String),
    argumentMode: CommandArgumentMode.values.byName(
      json['argumentMode'] as String,
    ),
    permission: ChatPermission.values.byName(json['permission'] as String),
    globalCooldown: Duration(milliseconds: json['globalCooldownMs'] as int),
    userCooldown: Duration(milliseconds: json['userCooldownMs'] as int),
    minimumArguments: json['minimumArguments'] as int,
  );
}

final class CommandMatch {
  CommandMatch(
    this.matchedText,
    this.argumentText,
    List<String> arguments, {
    Map<String, String?> captures = const {},
  }) : arguments = List.unmodifiable(arguments),
       captures = Map.unmodifiable(captures);
  final Map<String, String?> captures;
  final String matchedText, argumentText;
  final List<String> arguments;
}

CommandMatch? matchCommandText(
  String text,
  List<String> patterns, {
  CommandMatchMode mode = CommandMatchMode.command,
  CommandArgumentMode argumentMode = CommandArgumentMode.quoted,
  bool caseSensitive = false,
}) {
  final original = text.trim();
  final haystack = caseSensitive ? original : original.toLowerCase();
  for (final pattern in patterns) {
    if (pattern.isEmpty) continue;
    final needle = caseSensitive ? pattern : pattern.toLowerCase();
    final index = switch (mode) {
      CommandMatchMode.regex => throw UnsupportedError(
        'Use matchAsync for bounded regex matching.',
      ),
      CommandMatchMode.exact => haystack == needle ? 0 : -1,
      CommandMatchMode.contains => haystack.indexOf(needle),
      CommandMatchMode.startsWith => haystack.startsWith(needle) ? 0 : -1,
      CommandMatchMode.command =>
        haystack.startsWith(needle) &&
                (haystack.length == needle.length ||
                    RegExp(r'\s').hasMatch(haystack[needle.length]))
            ? 0
            : -1,
    };
    if (index < 0) continue;
    final remaining = original.substring(index + pattern.length).trim();
    final arguments = switch (argumentMode) {
      CommandArgumentMode.remainder =>
        remaining.isEmpty ? <String>[] : [remaining],
      CommandArgumentMode.words =>
        remaining.isEmpty ? <String>[] : remaining.split(RegExp(r'\s+')),
      CommandArgumentMode.quoted => parseCommandArguments(remaining),
    };
    if (arguments == null) return null;
    return CommandMatch(
      original.substring(index, index + pattern.length),
      remaining,
      arguments,
    );
  }
  return null;
}

/// Returns null for unclosed quotes/escapes; never evaluates chat input.
List<String>? parseCommandArguments(String value) {
  final result = <String>[];
  var buffer = StringBuffer();
  String? quote;
  var escaped = false;
  var started = false;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (escaped) {
      buffer.write(char);
      escaped = false;
      started = true;
    } else if (char == r'\') {
      escaped = true;
      started = true;
    } else if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
    } else if (char == '"' || char == "'") {
      quote = char;
      started = true;
    } else if (RegExp(r'\s').hasMatch(char)) {
      if (started) {
        result.add(buffer.toString());
        buffer = StringBuffer();
        started = false;
      }
    } else {
      buffer.write(char);
      started = true;
    }
  }
  if (quote != null || escaped) return null;
  if (started) result.add(buffer.toString());
  return result;
}
