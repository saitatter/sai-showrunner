import 'package:flutter/material.dart';
import '../../../../components/data_inputs/numeric_input_formatter.dart';
import '../../../../design_system/tokens/tokens.dart';
import '../../../obs/overlay_source_service.dart';

class OverlayEditorToolbar extends StatelessWidget {
  const OverlayEditorToolbar({
    super.key,
    required this.nameController,
    required this.widthController,
    required this.heightController,
    required this.snapEnabled,
    required this.onSnapToggle,
    required this.onNameChanged,
    required this.onSizeChanged,
    required this.onSizePreset,
    required this.onPreviewSettings,
    required this.obsConnections,
    required this.obsConnectionsLoading,
    required this.selectedObsConnectionId,
    required this.onSelectObsConnection,
    this.obsSourceControl,
  });
  final TextEditingController nameController, widthController, heightController;
  final bool snapEnabled, obsConnectionsLoading;
  final VoidCallback onSnapToggle,
      onNameChanged,
      onSizeChanged,
      onPreviewSettings;
  final void Function(int width, int height) onSizePreset;
  final List<ObsConnectionChoice> obsConnections;
  final String? selectedObsConnectionId;
  final ValueChanged<String?> onSelectObsConnection;
  final Widget? obsSourceControl;
  Widget _preset(String label, int width, int height) => OutlinedButton(
    onPressed: () => onSizePreset(width, height),
    child: Text(label),
  );
  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('overlay-editor-toolbar'),
    color: ShowRunnerColors.surfaceB,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.layers_outlined),
          IconButton(
            key: const ValueKey('overlay-snap-toggle'),
            tooltip: 'Snap to guides (hold Shift to bypass)',
            isSelected: snapEnabled,
            selectedIcon: const Icon(Icons.grid_on),
            icon: const Icon(Icons.grid_off),
            onPressed: onSnapToggle,
          ),
          const Text(
            'Edit overlay',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Overlay name',
                isDense: true,
              ),
              onChanged: (_) => onNameChanged(),
            ),
          ),
          if (obsSourceControl != null) ...[
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                key: const ValueKey('overlay-obs-connection-selector'),
                initialValue:
                    obsConnections.any(
                      (connection) => connection.id == selectedObsConnectionId,
                    )
                    ? selectedObsConnectionId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'OBS Connection',
                  isDense: true,
                  suffixIcon: obsConnectionsLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                hint: const Text('Select OBS Connection'),
                items: [
                  for (final connection in obsConnections)
                    DropdownMenuItem(
                      value: connection.id,
                      child: Text(
                        connection.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: obsConnectionsLoading ? null : onSelectObsConnection,
              ),
            ),
            obsSourceControl!,
          ],
          SizedBox(
            width: 86,
            child: TextField(
              controller: widthController,
              inputFormatters: const [
                NumericInputFormatter(decimal: false, signed: false),
              ],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Width',
                suffixText: 'px',
                isDense: true,
              ),
              onChanged: (_) => onSizeChanged(),
            ),
          ),
          SizedBox(
            width: 86,
            child: TextField(
              controller: heightController,
              inputFormatters: const [
                NumericInputFormatter(decimal: false, signed: false),
              ],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Height',
                suffixText: 'px',
                isDense: true,
              ),
              onChanged: (_) => onSizeChanged(),
            ),
          ),
          _preset('1080p', 1920, 1080),
          _preset('1440p', 2560, 1440),
          _preset('4K', 3840, 2160),
          _preset('Vertical', 1080, 1920),
          IconButton(
            tooltip: 'Preview settings',
            onPressed: onPreviewSettings,
            icon: const Icon(Icons.image_outlined),
          ),
        ],
      ),
    ),
  );
}
