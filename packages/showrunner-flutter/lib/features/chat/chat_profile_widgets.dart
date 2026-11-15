import 'dart:async';
import 'package:flutter/material.dart';
import 'chat_message.dart';
import 'chat_user_profile.dart';
import 'unified_chat_runtime.dart';

IconData _badgeIcon(String role) => switch (role) {
  'broadcaster' => Icons.campaign,
  'moderator' => Icons.shield,
  'vip' => Icons.diamond,
  'subscriber' || 'founder' => Icons.star,
  'bot' => Icons.smart_toy_outlined,
  _ => Icons.verified,
};

class ChatProfileAvatar extends StatelessWidget {
  const ChatProfileAvatar({super.key, required this.profile, this.size = 32});
  final ChatUserProfile profile;
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: profile.avatarUrl == null
          ? Icon(Icons.account_circle, size: size)
          : Image.network(
              profile.avatarUrl!,
              fit: BoxFit.cover,
              cacheWidth: 96,
              semanticLabel: 'Avatar for ${profile.name}',
              errorBuilder: (_, _, _) => Icon(Icons.account_circle, size: size),
            ),
    ),
  );
}

class ChatProfileBadges extends StatelessWidget {
  const ChatProfileBadges({super.key, required this.badges});
  final List<ChatUserBadge> badges;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final badge in badges)
        Tooltip(
          message: badge.title,
          child: badge.imageUrl == null
              ? Icon(_badgeIcon(badge.role), size: 18)
              : Image.network(
                  badge.imageUrl!,
                  width: 18,
                  height: 18,
                  cacheWidth: 36,
                  errorBuilder: (_, _, _) =>
                      Icon(_badgeIcon(badge.role), size: 18),
                ),
        ),
    ],
  );
}

class ChatUserProfileDialog extends StatefulWidget {
  const ChatUserProfileDialog({
    super.key,
    required this.runtime,
    required this.message,
  });
  final UnifiedChatRuntime runtime;
  final ChatMessage message;
  @override
  State<ChatUserProfileDialog> createState() => _ChatUserProfileDialogState();
}

class _ChatUserProfileDialogState extends State<ChatUserProfileDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  void _load() {
    unawaited(
      widget.runtime.loadUserProfiles([widget.message]).catchError((Object _) {
        // The owning runtime may have closed while this read-only dialog was open.
      }),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.runtime,
    builder: (context, _) {
      final profile = widget.runtime.userProfile(widget.message);
      final count = widget.runtime.messages
          .where((m) => m.userIdentity == widget.message.userIdentity)
          .length;
      return AlertDialog(
        title: Text(profile.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChatProfileAvatar(profile: profile, size: 64),
              const SizedBox(height: 12),
              if (profile.login.isNotEmpty) Text('@${profile.login}'),
              SelectableText('${widget.message.platform.name}: ${profile.id}'),
              const SizedBox(height: 8),
              ChatProfileBadges(badges: profile.badges),
              const SizedBox(height: 8),
              Text(
                '$count ${count == 1 ? 'message' : 'messages'} in retained session history',
              ),
              if (widget.message.platform == ChatPlatform.twitch &&
                  widget.runtime.profileStatus == 'loading')
                const LinearProgressIndicator(),
              if (widget.message.platform == ChatPlatform.twitch &&
                  widget.runtime.profileStatus == 'unavailable')
                const Text(
                  'Public profile unavailable. Check the Twitch connection or retry.',
                ),
            ],
          ),
        ),
        actions: [
          if (widget.message.platform == ChatPlatform.twitch)
            TextButton(
              onPressed: widget.runtime.profileStatus == 'loading'
                  ? null
                  : _load,
              child: const Text('Refresh profile'),
            ),
          if (widget.message.platform == ChatPlatform.twitch)
            TextButton(
              onPressed: widget.runtime.profileStatus == 'loading'
                  ? null
                  : () {
                      unawaited(
                        widget.runtime
                            .loadUserProfiles(widget.runtime.messages.reversed)
                            .catchError((Object _) {
                              /* Runtime closed while dialog was open. */
                            }),
                      );
                    },
              child: const Text('Load recent profiles'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
