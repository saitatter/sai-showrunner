import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system/tokens/tokens.dart';

enum ShowRunnerFeedbackSeverity { info, success, warning, error }

/// The application-level layer used for transient feedback.
///
/// Toasts are rendered in a [Stack] above the application content, so showing
/// a notification never changes the layout height or pushes the current
/// workspace down.
class ShowRunnerToastHost extends StatefulWidget {
  const ShowRunnerToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<ShowRunnerToastHost> createState() => _ShowRunnerToastHostState();
}

class _ShowRunnerToastHostState extends State<ShowRunnerToastHost> {
  _ShowRunnerToast? _toast;
  Timer? _dismissTimer;
  int _toastGeneration = 0;

  void showToast(
    String message, {
    ShowRunnerFeedbackSeverity severity = ShowRunnerFeedbackSeverity.info,
    String? title,
  }) {
    _dismissTimer?.cancel();
    final generation = ++_toastGeneration;
    if (mounted) {
      setState(() {
        _toast = _ShowRunnerToast(
          message: message,
          severity: severity,
          title: title,
        );
      });
    }
    _dismissTimer = Timer(_toastDuration(severity), () {
      if (!mounted || generation != _toastGeneration) return;
      setState(() => _toast = null);
    });
  }

  void dismissToast() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _toastGeneration++;
    if (mounted) setState(() => _toast = null);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toast = _toast;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (toast != null)
          Positioned(
            top: ShowRunnerSpacing.toolbarHeight + 12,
            right: 20,
            child: _ShowRunnerToastCard(toast: toast, onDismiss: dismissToast),
          ),
      ],
    );
  }
}

class _ShowRunnerToast {
  const _ShowRunnerToast({
    required this.message,
    required this.severity,
    this.title,
  });

  final String message;
  final ShowRunnerFeedbackSeverity severity;
  final String? title;
}

Duration _toastDuration(ShowRunnerFeedbackSeverity severity) =>
    switch (severity) {
      ShowRunnerFeedbackSeverity.error => const Duration(seconds: 8),
      ShowRunnerFeedbackSeverity.warning => const Duration(seconds: 6),
      _ => const Duration(seconds: 4),
    };

({Color color, IconData icon}) _toastStyle(
  ShowRunnerFeedbackSeverity severity,
) => switch (severity) {
  ShowRunnerFeedbackSeverity.success => (
    color: const Color(0xff34d399),
    icon: Icons.check_circle_outline,
  ),
  ShowRunnerFeedbackSeverity.warning => (
    color: const Color(0xffffb74d),
    icon: Icons.warning_amber_outlined,
  ),
  ShowRunnerFeedbackSeverity.error => (
    color: const Color(0xffff6b6b),
    icon: Icons.error_outline,
  ),
  ShowRunnerFeedbackSeverity.info => (
    color: const Color(0xff81c7ff),
    icon: Icons.info_outline,
  ),
};

class _ShowRunnerToastCard extends StatelessWidget {
  const _ShowRunnerToastCard({required this.toast, required this.onDismiss});

  final _ShowRunnerToast toast;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final style = _toastStyle(toast.severity);
    final title = toast.title;
    final toastWidth = (MediaQuery.sizeOf(context).width - 40)
        .clamp(280.0, 480.0)
        .toDouble();
    return Semantics(
      key: const ValueKey('showrunner-toast'),
      container: true,
      liveRegion: true,
      label: title == null ? toast.message : '$title: ${toast.message}',
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: toastWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ShowRunnerColors.surfaceC,
              border: Border.all(color: style.color.withValues(alpha: 0.48)),
              borderRadius: BorderRadius.circular(5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: style.color, width: 3)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(style.icon, color: style.color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          Text(
                            toast.message,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'Dismiss',
                    child: IconButton(
                      key: const ValueKey('showrunner-toast-dismiss'),
                      onPressed: onDismiss,
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays transient app feedback as an overlayed toast.
///
/// The public call stays context-based so existing feature actions can report
/// feedback without owning a notification controller. The application frame
/// installs [ShowRunnerToastHost], while the small fallback keeps the helper
/// safe for isolated widgets and tests that do not use the full application.
void showShowRunnerFeedback(
  BuildContext context,
  String message, {
  ShowRunnerFeedbackSeverity severity = ShowRunnerFeedbackSeverity.info,
  String? title,
}) {
  final host = context.findAncestorStateOfType<_ShowRunnerToastHostState>();
  if (host != null) {
    host.showToast(message, severity: severity, title: title);
    return;
  }

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _showFallbackToast(overlay, message, severity: severity, title: title);
}

OverlayEntry? _fallbackToastEntry;

void _showFallbackToast(
  OverlayState overlay,
  String message, {
  required ShowRunnerFeedbackSeverity severity,
  String? title,
}) {
  _fallbackToastEntry?.remove();
  final entry = OverlayEntry(
    builder: (context) => Positioned(
      top: ShowRunnerSpacing.toolbarHeight + 12,
      right: 20,
      child: _ShowRunnerToastCard(
        toast: _ShowRunnerToast(
          message: message,
          severity: severity,
          title: title,
        ),
        onDismiss: () {
          _fallbackToastEntry?.remove();
          _fallbackToastEntry = null;
        },
      ),
    ),
  );
  _fallbackToastEntry = entry;
  overlay.insert(entry);
}
