import 'package:flutter/material.dart';

import '../../../../components/data_inputs/numeric_input_formatter.dart';
import '../../../../schema/json.dart';

/// A form draft, including latent values while preview is disabled.
/// The editor controller remains the owner of the persisted configuration.
@immutable
class OverlayPreviewSettings {
  const OverlayPreviewSettings({
    required this.enabled,
    required this.fromObs,
    required this.source,
    required this.offsetX,
    required this.offsetY,
    this.extra = const {},
  });

  factory OverlayPreviewSettings.fromConfig(Object? config) {
    final map = config is Map
        ? Map<String, dynamic>.from(config)
        : <String, dynamic>{};
    return OverlayPreviewSettings(
      enabled: config is Map,
      fromObs: map['source'] == 'obs',
      source: map['source'] == 'obs' ? '' : '${map['source'] ?? ''}',
      offsetX: '${map['offsetX'] ?? 0}',
      offsetY: '${map['offsetY'] ?? 0}',
      extra: Map.unmodifiable(
        map..removeWhere(
          (key, _) => const ['source', 'offsetX', 'offsetY'].contains(key),
        ),
      ),
    );
  }

  final bool enabled, fromObs;
  final String source, offsetX, offsetY;
  final JsonMap extra;

  JsonMap? toConfig() => enabled
      ? {
          ...extra,
          'offsetX': num.tryParse(offsetX) ?? 0,
          'offsetY': num.tryParse(offsetY) ?? 0,
          if (fromObs)
            'source': 'obs'
          else if (source.trim().isNotEmpty)
            'source': source.trim(),
        }
      : null;
}

class OverlayPreviewSettingsDialog extends StatefulWidget {
  const OverlayPreviewSettingsDialog({
    super.key,
    required this.initial,
    required this.onChanged,
  });
  final OverlayPreviewSettings initial;
  final ValueChanged<OverlayPreviewSettings> onChanged;

  @override
  State<OverlayPreviewSettingsDialog> createState() =>
      _OverlayPreviewSettingsDialogState();
}

class _OverlayPreviewSettingsDialogState
    extends State<OverlayPreviewSettingsDialog> {
  late final _source = TextEditingController(text: widget.initial.source);
  late final _offsetX = TextEditingController(text: widget.initial.offsetX);
  late final _offsetY = TextEditingController(text: widget.initial.offsetY);
  late bool _enabled = widget.initial.enabled;
  late bool _fromObs = widget.initial.fromObs;

  void _publish() => widget.onChanged(
    OverlayPreviewSettings(
      enabled: _enabled,
      fromObs: _fromObs,
      source: _source.text,
      offsetX: _offsetX.text,
      offsetY: _offsetY.text,
      extra: widget.initial.extra,
    ),
  );

  @override
  void dispose() {
    _source.dispose();
    _offsetX.dispose();
    _offsetY.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Preview settings'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable preview'),
              value: _enabled,
              onChanged: (value) {
                setState(() => _enabled = value);
                _publish();
              },
            ),
            if (_enabled) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Preview OBS output'),
                value: _fromObs,
                onChanged: (value) {
                  setState(() => _fromObs = value);
                  _publish();
                },
              ),
              if (!_fromObs)
                TextField(
                  controller: _source,
                  decoration: const InputDecoration(
                    labelText: 'Preview image',
                    hintText: 'Optional PNG/JPG/BMP/WebP path',
                  ),
                  onChanged: (_) => _publish(),
                ),
              Row(
                children: [
                  Expanded(child: _offsetField(_offsetX, 'Offset X')),
                  const SizedBox(width: 12),
                  Expanded(child: _offsetField(_offsetY, 'Offset Y')),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );

  Widget _offsetField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: const [NumericInputFormatter()],
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => _publish(),
      );
}
