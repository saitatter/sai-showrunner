import 'package:flutter/material.dart';

/// Shared empty/error/disabled presentation; callers supply safe user-facing text.
class WorkspaceNotice extends StatelessWidget {
  const WorkspaceNotice({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.icon = Icons.warning_amber,
    this.color = Colors.orange,
  });

  final String message;
  final String? title;
  final Widget? action;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: title == null
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (title != null) ...[Text(title!), const SizedBox(height: 4)],
              Text(message, textAlign: title == null ? TextAlign.center : null),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    ),
  );
}
