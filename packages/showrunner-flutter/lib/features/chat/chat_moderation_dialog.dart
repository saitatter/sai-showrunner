import 'package:flutter/material.dart';
import 'chat_message.dart';
import 'unified_chat_runtime.dart';

class ChatModerationDialog extends StatefulWidget {
  const ChatModerationDialog({
    super.key,
    required this.message,
    required this.action,
  });
  final ChatMessage message;
  final ChatQuickAction action;
  @override
  State<ChatModerationDialog> createState() => _ChatModerationDialogState();
}

class _ChatModerationDialogState extends State<ChatModerationDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final warning = widget.action == ChatQuickAction.warnUser;
    return AlertDialog(
      title: Text('${widget.action.label} on ${widget.message.platform.name}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.message.userName}: ${widget.message.text}'),
            if (warning)
              TextField(
                controller: _reason,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Warning reason'),
                onChanged: (_) => setState(() {}),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: warning && _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
