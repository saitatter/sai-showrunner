import 'package:flutter/material.dart';
import 'overlay_obs_controller.dart';

class OverlayObsSourceControl extends StatelessWidget {
  const OverlayObsSourceControl({
    super.key,
    required this.view,
    required this.onOpen,
    required this.onCheck,
    required this.onCreate,
    required this.onFix,
  });
  final OverlayObsView view;
  final VoidCallback onOpen, onCheck, onCreate, onFix;
  @override
  Widget build(BuildContext context) {
    final selected = view.selected;
    final status = view.status;
    if (!view.available) return const SizedBox.shrink();
    if (selected == null) {
      return Tooltip(
        message: 'Select an OBS connection to manage its Browser Source.',
        child: OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.link_off),
          label: const Text('Select OBS Connection'),
        ),
      );
    }
    if (view.sourceLoading) {
      return const SizedBox(
        width: 42,
        height: 42,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (view.error != null || status?.connected != true) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: view.error ?? 'OBS connection has not been checked.',
            child: Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(width: 6),
          if (selected.isLocal)
            OutlinedButton.icon(
              key: const ValueKey('overlay-open-obs'),
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open OBS'),
            )
          else
            Tooltip(
              message: 'ShowRunner cannot launch OBS on a remote computer.',
              child: const Chip(label: Text('Remote OBS')),
            ),
          IconButton(
            key: const ValueKey('overlay-check-obs'),
            tooltip: 'Check OBS connection',
            onPressed: onCheck,
            icon: const Icon(Icons.refresh),
          ),
        ],
      );
    }
    if (status!.needsCreate) {
      return FilledButton.icon(
        key: const ValueKey('overlay-create-browser-source'),
        onPressed: onCreate,
        icon: const Icon(Icons.add),
        label: const Text('Create Source'),
      );
    }
    if (status.needsFix) {
      return FilledButton.tonalIcon(
        key: const ValueKey('overlay-fix-browser-source'),
        onPressed: onFix,
        icon: const Icon(Icons.build_outlined),
        label: const Text('Fix OBS Source'),
      );
    }
    return Tooltip(
      message: 'This Browser Source is set to the current overlay.',
      child: Chip(
        key: const ValueKey('overlay-browser-source-ready'),
        avatar: const Icon(Icons.web_asset_outlined, size: 18),
        label: Text(status.sourceName ?? 'OBS source ready'),
      ),
    );
  }
}
