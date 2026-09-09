import 'package:flutter/material.dart';

enum ShowRunnerFeedbackSeverity { info, success, warning, error }

/// Displays transient app feedback using the same full-width banner treatment
/// as startup and provider errors. This keeps important information visible at
/// the top of the workspace instead of hiding it in a bottom SnackBar.
void showShowRunnerFeedback(
  BuildContext context,
  String message, {
  ShowRunnerFeedbackSeverity severity = ShowRunnerFeedbackSeverity.info,
  String? title,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final (color, icon, fallbackTitle) = switch (severity) {
    ShowRunnerFeedbackSeverity.success => (
      const Color(0xff34d399),
      Icons.check_circle_outline,
      'Done',
    ),
    ShowRunnerFeedbackSeverity.warning => (
      const Color(0xffffb74d),
      Icons.warning_amber_outlined,
      'Warning',
    ),
    ShowRunnerFeedbackSeverity.error => (
      const Color(0xffff6b6b),
      Icons.error_outline,
      'Error',
    ),
    ShowRunnerFeedbackSeverity.info => (
      const Color(0xff81c7ff),
      Icons.info_outline,
      'Info',
    ),
  };

  messenger.hideCurrentMaterialBanner();
  messenger.showMaterialBanner(
    MaterialBanner(
      backgroundColor: color.withValues(alpha: 0.14),
      leading: Icon(icon, color: color),
      content: Text(
        title == null ? message : '$title\n$message',
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
          onPressed: messenger.hideCurrentMaterialBanner,
          child: Text(title == null ? 'Dismiss' : fallbackTitle),
        ),
      ],
    ),
  );
}
