import 'package:flutter/material.dart';

import '../../plugins/registry/plugin_registry.dart';
import '../../schema/resource.dart';
import 'resource_editor_contribution.dart';

/// Keep the editor subtree mounted when its owner is disabled, preserving
/// authoring history and unsaved input until the owner becomes available again.
class ResourceEditorAvailability extends StatelessWidget {
  const ResourceEditorAvailability({
    super.key,
    required this.contribution,
    required this.resource,
    required this.registryFuture,
    required this.builder,
  });

  final ResourceEditorContribution? contribution;
  final ResourceData resource;
  final Future<DartPluginRegistry> registryFuture;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final editor = contribution;
    final invalid = editor?.readOnlyReason(resource);
    if (editor == null || invalid != null) {
      return _Unavailable(
        reason: invalid ?? 'No resource editor is registered.',
      );
    }
    return FutureBuilder<DartPluginRegistry>(
      future: registryFuture,
      builder: (context, snapshot) {
        final registry = snapshot.data;
        if (registry == null) {
          return _Unavailable(
            reason: snapshot.hasError
                ? 'The plugin registry could not be loaded.'
                : 'Loading the resource owner?',
          );
        }
        return ListenableBuilder(
          listenable: registry,
          child: builder(context),
          builder: (context, child) {
            final enabled =
                registry.manifest(editor.ownerId) != null &&
                registry.isPluginEnabledId(editor.ownerId);
            return Stack(
              fit: StackFit.expand,
              children: [
                ExcludeFocus(
                  excluding: !enabled,
                  child: Offstage(offstage: !enabled, child: child!),
                ),
                if (!enabled)
                  const _Unavailable(
                    reason:
                        'The owning plugin is disabled. Re-enable it to continue editing. Unsaved changes are retained.',
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.reason});
  final String reason;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(reason, textAlign: TextAlign.center),
    ),
  );
}
