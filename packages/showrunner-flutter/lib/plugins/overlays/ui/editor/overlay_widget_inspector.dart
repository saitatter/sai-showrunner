import 'package:showrunner_flutter/components/data_inputs/numeric_input_formatter.dart';
import 'package:flutter/material.dart';

import 'package:showrunner_flutter/schema/json.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_editor.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_model.dart';
import 'package:showrunner_flutter/plugins/overlays/generated_widget_catalog.dart';

import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_widget_config_editor.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_widget_presentation.dart';

class OverlayWidgetInspector extends StatelessWidget {
  const OverlayWidgetInspector({
    super.key,
    required this.widgetConfig,
    required this.onChanged,
    required this.catalog,
    required this.templateSuggestions,
  });

  final JsonMap widgetConfig;
  final void Function(String key, dynamic value) onChanged;
  final List<GeneratedOverlayWidget> catalog;
  final List<String> templateSuggestions;

  @override
  Widget build(BuildContext context) {
    final position = widgetConfig['position'] is Map
        ? Map<String, dynamic>.from(widgetConfig['position'] as Map)
        : const <String, dynamic>{};
    final size = widgetConfig['size'] is Map
        ? Map<String, dynamic>.from(widgetConfig['size'] as Map)
        : const <String, dynamic>{};
    final config = widgetConfig['config'] is Map
        ? Map<String, dynamic>.from(widgetConfig['config'] as Map)
        : const <String, dynamic>{};
    final pluginId = OverlayWidgetPresentation.pluginId(widgetConfig);
    final widgetId = OverlayWidgetPresentation.widgetId(widgetConfig);
    final definition = catalog.cast<GeneratedOverlayWidget?>().firstWhere(
      (candidate) =>
          candidate?.pluginId == pluginId && candidate?.id == widgetId,
      orElse: () => null,
    );
    final resolvedPlugin = definition?.pluginId ?? pluginId;
    final resolvedWidget = definition?.id ?? widgetId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverlayWidgetConfigEditor(
          plugin: resolvedPlugin,
          widget: resolvedWidget,
          config: config,
          onChanged: (value) => onChanged('config', value),
          catalog: catalog,
          templateSuggestions: templateSuggestions,
        ),
        if (resolvedPlugin == 'overlays' && resolvedWidget == 'shaderLayer')
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Open Shader Graph'),
              onPressed: () async {
                final result = await showDialog<ShaderGraphEditorResult>(
                  context: context,
                  builder: (context) => ShaderGraphEditorDialog(config: config),
                );
                if (result == null) return;
                onChanged(
                  'config',
                  applyCompiledShaderGraph(
                    config: config,
                    graph: result.graph,
                    glsl: result.glsl,
                    uniforms: result.uniforms,
                    bindings: result.bindings,
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        _inspectorSection(
          context,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _numberField(
                      'X',
                      position['x'],
                      (value) =>
                          onChanged('position', {...position, 'x': value}),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _numberField(
                      'Y',
                      position['y'],
                      (value) =>
                          onChanged('position', {...position, 'y': value}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _numberField(
                      'Width',
                      size['width'],
                      (value) => onChanged('size', {...size, 'width': value}),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _numberField(
                      'Height',
                      size['height'],
                      (value) => onChanged('size', {...size, 'height': value}),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _inspectorSection(BuildContext context, {required Widget child}) =>
      DecoratedBox(
        key: const ValueKey('overlay-widget-transform'),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child],
          ),
        ),
      );

  Widget _numberField(String label, Object? value, ValueChanged<num> onValue) =>
      _OverlayTransformField(
        label: label,
        value: value is num ? value : 0,
        onChanged: onValue,
      );
}

class _OverlayTransformField extends StatefulWidget {
  const _OverlayTransformField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final num value;
  final ValueChanged<num> onChanged;
  @override
  State<_OverlayTransformField> createState() => _OverlayTransformFieldState();
}

class _OverlayTransformFieldState extends State<_OverlayTransformField> {
  late final TextEditingController _controller = TextEditingController(
    text: _format(widget.value),
  );
  String? _error;
  String _format(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
  @override
  void didUpdateWidget(covariant _OverlayTransformField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        num.tryParse(_controller.text) != widget.value) {
      _controller.text = _format(widget.value);
      _error = null;
    }
  }

  bool _valid(num? value) =>
      value != null &&
      value.isFinite &&
      (!{'Width', 'Height'}.contains(widget.label) || value > 0);
  void _change(String text) {
    final value = num.tryParse(text);
    setState(() => _error = _valid(value) ? null : 'Invalid value');
    if (_valid(value)) widget.onChanged(value!);
  }

  void _step(int amount) {
    final next = (num.tryParse(_controller.text) ?? widget.value) + amount;
    if (!_valid(next)) return;
    _controller.text = _format(next);
    _change(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: ValueKey('overlay-transform-${widget.label.toLowerCase()}'),
    controller: _controller,
    inputFormatters: const [NumericInputFormatter()],
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    decoration: InputDecoration(
      labelText: widget.label,
      suffixText: 'px',
      errorText: _error,
      suffixIconConstraints: const BoxConstraints.tightFor(
        width: 24,
        height: 34,
      ),
      suffixIcon: Column(
        children: [
          SizedBox(
            height: 17,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 14,
              tooltip: 'Increase ${widget.label}',
              onPressed: () => _step(1),
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
          ),
          SizedBox(
            height: 17,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 14,
              tooltip: 'Decrease ${widget.label}',
              onPressed: () => _step(-1),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
        ],
      ),
    ),
    onChanged: _change,
  );
}
