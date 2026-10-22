import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/app_feedback.dart';
import '../../../../services/oauth_token.dart';
import 'overlay_presence_controller.dart';

/// Browser-source presentation follows only presence/URL changes, not authoring.
class OverlayBrowserSourcePanel extends StatelessWidget {
  const OverlayBrowserSourcePanel({super.key, required this.presence});
  final OverlayPresenceController presence;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<OverlayPresenceView>(
    valueListenable: presence,
    builder: (context, view, child) {
      final connected = view.presence.connected;
      final url = view.url;
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Tooltip(
                  message: 'OBS Browser Source',
                  child: Icon(
                    connected ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                    size: 15,
                    color: connected
                        ? const Color(0xff54d98c)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  connected
                      ? 'Connected (${view.presence.subscribers})'
                      : 'Disconnected',
                  key: const ValueKey('overlay-browser-source-status'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: connected ? const Color(0xff54d98c) : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy Browser Source URL',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) {
                      showShowRunnerFeedback(
                        context,
                        'Browser Source URL copied.',
                        severity: ShowRunnerFeedbackSeverity.success,
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 15),
                ),
                IconButton(
                  tooltip: 'Open Browser Source URL',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    try {
                      await openOAuthUrlInBrowser(Uri.parse(url));
                    } on Object {
                      if (context.mounted) {
                        showShowRunnerFeedback(
                          context,
                          'Could not open Browser Source URL. Check the overlay runtime and browser settings.',
                          severity: ShowRunnerFeedbackSeverity.error,
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 15),
                ),
              ],
            ),
            SelectableText(
              url,
              key: const ValueKey('overlay-browser-source-url'),
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    },
  );
}
