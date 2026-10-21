import 'package:showrunner_flutter/components/data_inputs/numeric_input_formatter.dart';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:showrunner_flutter/schema/json.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';
import 'package:showrunner_flutter/plugins/dashboards/ui/dashboard_widget_config.dart';

class DashboardWidgetDialog extends StatefulWidget {
  const DashboardWidgetDialog({super.key, required this.widget});

  final JsonMap widget;

  @override
  State<DashboardWidgetDialog> createState() => _DashboardWidgetDialogState();
}

class _DashboardWidgetDialogState extends State<DashboardWidgetDialog> {
  late final TextEditingController _plugin;
  late final TextEditingController _widget;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _config;
  late JsonMap _configValue;
  String? _error;

  @override
  void initState() {
    super.initState();
    final size = widget.widget['size'] is Map
        ? Map<String, dynamic>.from(widget.widget['size'] as Map)
        : const <String, dynamic>{};
    _plugin = TextEditingController(
      text: widget.widget['plugin']?.toString() ?? 'dashboards',
    );
    _widget = TextEditingController(
      text: widget.widget['widget']?.toString() ?? 'label',
    );
    _width = TextEditingController(text: '${size['width'] ?? 4}');
    _height = TextEditingController(text: '${size['height'] ?? 1}');
    _configValue = widget.widget['config'] is Map
        ? Map<String, dynamic>.from(widget.widget['config'] as Map)
        : <String, dynamic>{};
    _config = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(_configValue),
    );
  }

  @override
  void dispose() {
    for (final controller in [_plugin, _widget, _width, _height, _config]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit dashboard widget'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _plugin,
              decoration: const InputDecoration(labelText: 'Plugin'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _widget,
              decoration: const InputDecoration(labelText: 'Widget'),
              onChanged: (_) => setState(() {}),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _width,
                    inputFormatters: const [
                      NumericInputFormatter(decimal: false, signed: false),
                    ],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Width'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _height,
                    inputFormatters: const [
                      NumericInputFormatter(decimal: false, signed: false),
                    ],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Height'),
                  ),
                ),
              ],
            ),
            _configEditor(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  void _save() {
    final definition = findDashboardWidgetDefinition(
      _plugin.text.trim(),
      _widget.text.trim(),
    );
    JsonMap config;
    if (definition != null) {
      config = _configValue;
    } else {
      dynamic decoded;
      try {
        decoded = jsonDecode(_config.text);
      } on FormatException {
        setState(() => _error = 'Widget config must be valid JSON.');
        return;
      }
      if (decoded is! Map) {
        setState(() => _error = 'Widget config must be a JSON object.');
        return;
      }
      config = Map<String, dynamic>.from(decoded);
    }
    Navigator.pop(context, {
      ...widget.widget,
      'plugin': _plugin.text.trim(),
      'widget': _widget.text.trim(),
      'size': {
        'width': int.tryParse(_width.text) ?? 4,
        'height': int.tryParse(_height.text) ?? 1,
      },
      'config': config,
    });
  }

  Widget _configEditor() {
    final definition = findDashboardWidgetDefinition(
      _plugin.text.trim(),
      _widget.text.trim(),
    );
    if (definition == null) {
      return TextField(
        controller: _config,
        maxLines: 8,
        decoration: const InputDecoration(labelText: 'Widget config JSON'),
      );
    }
    return DartDataInput(
      key: ValueKey('${definition.plugin}.${definition.widget}'),
      schema: definition.configSchema,
      value: _configValue,
      onChanged: (value) {
        if (value is Map) {
          setState(() => _configValue = Map<String, dynamic>.from(value));
        }
      },
    );
  }
}
