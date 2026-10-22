import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_message.dart';
import 'chat_actions_dialog.dart';
import 'chat_message_body.dart';
import 'configured_chat_action.dart';
import 'unified_chat_runtime.dart';

class ChatTimeline extends StatelessWidget {
  const ChatTimeline({
    super.key,
    required this.runtime,
    required this.search,
    this.filter,
    this.userIdentity,
    this.pausedIdentities,
    this.pausedEventIds,
    required this.showEvents,
    required this.busy,
    required this.onRun,
    required this.onModerate,
    required this.onReply,
    required this.onUser,
  });
  final UnifiedChatRuntime runtime;
  final String search;
  final ChatPlatform? filter;
  final String? userIdentity;
  final Set<String>? pausedIdentities, pausedEventIds;
  final bool showEvents, busy;
  final Future<void> Function(Future<void> Function()) onRun;
  final Future<void> Function(ChatMessage, ChatQuickAction) onModerate;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<String> onUser;
  Widget _eventFeed(UnifiedChatRuntime runtime, String search) {
    final events = runtime.events
        .where(
          (e) =>
              (filter == null || e.platform == filter) &&
              (pausedEventIds == null || pausedEventIds!.contains(e.id)) &&
              (userIdentity == null ||
                  '${e.platform.name}:${e.userId}' == userIdentity) &&
              (search.isEmpty ||
                  '${e.type} ${e.userName} ${e.message}'.toLowerCase().contains(
                    search,
                  )),
        )
        .toList();
    if (events.isEmpty) {
      return const Center(child: Text('No provider events in this session.'));
    }
    events.setAll(0, events.reversed.toList());
    return ListView.builder(
      reverse: !runtime.preferences.newestFirst,
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final actions = runtime
            .actionsFor(ChatActionScope.event, event.platform)
            .toList();
        return ListTile(
          leading: const Icon(Icons.bolt),
          title: Text(
            '${runtime.preferences.timestamps ? '${event.time.toLocal().toIso8601String().substring(11, 19)} ' : ''}${event.platform.name} - ${event.type} - ${event.userName}',
          ),
          subtitle: Text(event.message),
          trailing: actions.isEmpty
              ? null
              : PopupMenuButton<String>(
                  tooltip: 'Event actions',
                  onSelected: busy
                      ? null
                      : (id) => onRun(
                          () => runtime.runConfiguredAction(
                            id,
                            platform: event.platform,
                            eventId: event.id,
                          ),
                        ),
                  itemBuilder: (_) => [
                    for (final action in actions)
                      PopupMenuItem(
                        value: action.id,
                        child: Text(action.label),
                      ),
                  ],
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runtime,
    builder: (context, _) {
      final preferences = runtime.preferences;
      final messages = runtime.messages
          .where(
            (m) =>
                (filter == null || m.platform == filter) &&
                (userIdentity == null || m.userIdentity == userIdentity) &&
                (pausedIdentities == null ||
                    pausedIdentities!.contains(m.identity)) &&
                (search.isEmpty ||
                    '${m.userName} ${m.text}'.toLowerCase().contains(search)),
          )
          .toList()
          .reversed
          .toList();
      return showEvents
          ? _eventFeed(runtime, search)
          : messages.isEmpty
          ? const Center(
              child: Text('No messages. Connect Twitch or YouTube in Plugins.'),
            )
          : ListView.builder(
              reverse: !preferences.newestFirst,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return ListTile(
                  tileColor: preferences.highlights(message)
                      ? Theme.of(context).colorScheme.primaryContainer
                      : preferences.alternatingRows && index.isOdd
                      ? Theme.of(context).colorScheme.surfaceContainer
                      : null,
                  leading: !preferences.platformIcons
                      ? null
                      : Tooltip(
                          message: message.platform.name,
                          child: Icon(
                            message.platform == ChatPlatform.twitch
                                ? Icons.live_tv
                                : Icons.smart_display_outlined,
                          ),
                        ),
                  title: Text(
                    '${preferences.timestamps ? '${message.receivedAt.toLocal().toIso8601String().substring(11, 19)} ' : ''}${message.userName}${preferences.roleBadges && message.isBroadcaster
                        ? ' · owner'
                        : preferences.roleBadges && message.isModerator
                        ? ' · moderator'
                        : ''}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: preferences.highlights(message)
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : null,
                    ),
                  ),
                  subtitle: ChatMessageBody(
                    parts: runtime.messageParts(message),
                    animate: preferences.animatedEmotes,
                    style: TextStyle(
                      fontSize: preferences.fontSize,
                      color: preferences.highlights(message)
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : null,
                      fontFamily: preferences.font == 'system'
                          ? null
                          : preferences.font,
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Message and user actions',
                    onSelected: (value) {
                      if (value == 'copy') {
                        Clipboard.setData(ClipboardData(text: message.text));
                      } else if (value == 'reply') {
                        onReply(message);
                      } else if (value == 'user') {
                        onUser(message.userIdentity);
                      } else if (value.startsWith('configured:')) {
                        onRun(
                          () => runtime.runConfiguredAction(
                            value.substring('configured:'.length),
                            platform: message.platform,
                            messageIdentity: message.identity,
                          ),
                        );
                      } else {
                        onModerate(
                          message,
                          ChatQuickAction.values.byName(value),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'reply', child: Text('Reply')),
                      const PopupMenuItem(
                        value: 'copy',
                        child: Text('Copy message'),
                      ),
                      const PopupMenuItem(
                        value: 'user',
                        child: Text('Show messages from user'),
                      ),
                      if (!busy && !message.deleted)
                        for (final scope in [
                          ChatActionScope.message,
                          ChatActionScope.user,
                        ])
                          for (final action in runtime.actionsFor(
                            scope,
                            message.platform,
                          ))
                            PopupMenuItem(
                              value: 'configured:${action.id}',
                              child: Row(
                                children: [
                                  Icon(
                                    chatActionIcon(action.icon),
                                    color: chatActionColor(action.color),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${scope.name}: ${action.label}'),
                                ],
                              ),
                            ),
                      if (!busy && !message.deleted && message.id.isNotEmpty)
                        const PopupMenuItem(
                          value: 'deleteMessage',
                          child: Text('Delete message'),
                        ),
                      if (!busy &&
                          !message.isBroadcaster &&
                          message.userId.isNotEmpty) ...[
                        const PopupMenuItem(
                          value: 'timeout',
                          child: Text('Timeout for 60 seconds'),
                        ),
                        const PopupMenuItem(
                          value: 'ban',
                          child: Text('Ban user'),
                        ),
                        if (message.platform == ChatPlatform.twitch)
                          const PopupMenuItem(
                            value: 'unban',
                            child: Text('Unban user'),
                          ),
                      ],
                    ],
                  ),
                );
              },
            );
    },
  );
}
