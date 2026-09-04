import 'package:flutter/material.dart';

import '../transform.dart';

final class ObsTransformInput extends StatefulWidget {
  const ObsTransformInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<ObsTransformInput> createState() => _ObsTransformInputState();
}

class _ObsTransformInputState extends State<ObsTransformInput> {
  late Map<String, dynamic> _value;
  var _linkScale = false;
  double? _scaleRatio;

  @override
  void initState() {
    super.initState();
    _value = normalizeObsTransform(widget.value);
  }

  @override
  void didUpdateWidget(covariant ObsTransformInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _value = normalizeObsTransform(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.label.isNotEmpty)
        Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
      _section(
        context,
        'Position',
        Row(
          children: [
            Expanded(child: _numberField('X', 'position', 'x')),
            const SizedBox(width: 8),
            Expanded(child: _numberField('Y', 'position', 'y')),
          ],
        ),
      ),
      _numberField('Rotation', null, 'rotation'),
      _enumField(
        'Alignment',
        'alignment',
        _alignmentOptions,
      ),
      _section(
        context,
        'Size',
        Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Link scale axes'),
              value: _linkScale,
              onChanged: (value) {
                setState(() {
                  _linkScale = value;
                  _scaleRatio = _readScaleRatio();
                });
              },
            ),
            Row(
              children: [
                Expanded(child: _numberField('X', 'scale', 'x')),
                const SizedBox(width: 8),
                Expanded(child: _numberField('Y', 'scale', 'y')),
              ],
            ),
          ],
        ),
      ),
      _section(
        context,
        'Crop',
        Column(
          children: [
            _numberField('Top', 'crop', 'top'),
            Row(
              children: [
                Expanded(child: _numberField('Left', 'crop', 'left')),
                const SizedBox(width: 8),
                Expanded(child: _numberField('Right', 'crop', 'right')),
              ],
            ),
            _numberField('Bottom', 'crop', 'bottom'),
          ],
        ),
      ),
      _section(
        context,
        'Bounds',
        Column(
          children: [
            _enumField(
              'Alignment',
              'boundingBox.alignment',
              _alignmentOptions,
            ),
            _enumField(
              'Bounds type',
              'boundingBox.boxType',
              _boundsTypeOptions,
            ),
            Row(
              children: [
                Expanded(child: _numberField('Width', 'boundingBox', 'width')),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField('Height', 'boundingBox', 'height'),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Widget _section(BuildContext context, String title, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    ),
  );

  Widget _numberField(String label, String? group, String field) {
    final value = group == null
        ? _value[field]
        : _readGroupValue(group, field);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        key: ValueKey('$group.$field.$value'),
        initialValue: value?.toString() ?? '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
        onChanged: (text) => _updateNumber(group, field, text),
      ),
    );
  }

  Widget _enumField(
    String label,
    String path,
    List<DropdownMenuItem<Object>> options,
  ) {
    final value = _readPath(path);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<Object>(
        initialValue: options.any((option) => option.value == value)
            ? value
            : null,
        decoration: InputDecoration(labelText: label),
        items: options,
        onChanged: (next) {
          if (next != null) _setPath(path, next);
        },
      ),
    );
  }

  dynamic _readGroupValue(String group, String field) {
    final parts = group.split('.');
    dynamic current = _value;
    for (final part in parts) {
      current = current is Map ? current[part] : null;
    }
    return current is Map ? current[field] : null;
  }

  dynamic _readPath(String path) {
    dynamic current = _value;
    for (final part in path.split('.')) {
      current = current is Map ? current[part] : null;
    }
    return current;
  }

  void _updateNumber(String? group, String field, String text) {
    final number = num.tryParse(text.trim());
    if (group == 'scale' && _linkScale && number != null) {
      final ratio = _scaleRatio ?? 1;
      final scale = _groupValue('scale');
      final next = {
        ..._value,
        'scale': {
          ...scale,
          field: number,
          field == 'x' ? 'y' : 'x': field == 'x' ? number / ratio : number * ratio,
        },
      };
      _emit(next);
      return;
    }
    if (group == null) {
      _emit({..._value, field: number});
      return;
    }
    _setGroupValue(group, field, number);
  }

  void _setPath(String path, dynamic value) {
    final parts = path.split('.');
    if (parts.length == 1) {
      _emit({..._value, path: value});
      return;
    }
    final group = _groupValue(parts.first);
    _emit({
      ..._value,
      parts.first: {...group, parts[1]: value},
    });
  }

  void _setGroupValue(String group, String field, dynamic value) => _emit({
    ..._value,
    group: {..._groupValue(group), field: value},
  });

  Map<String, dynamic> _groupValue(String group) {
    dynamic current = _value;
    for (final part in group.split('.')) {
      current = current is Map ? current[part] : null;
    }
    return current is Map ? Map<String, dynamic>.from(current) : {};
  }

  void _emit(Map<String, dynamic> next) {
    final normalized = normalizeObsTransform(next);
    setState(() => _value = normalized);
    widget.onChanged(normalized);
  }

  double? _readScaleRatio() {
    final scale = _groupValue('scale');
    final x = scale['x'];
    final y = scale['y'];
    if (x is num && y is num && y != 0) return x / y;
    return null;
  }
}

const _alignmentOptions = <DropdownMenuItem<Object>>[
  DropdownMenuItem(value: 0, child: Text('Center')),
  DropdownMenuItem(value: 1, child: Text('Left')),
  DropdownMenuItem(value: 2, child: Text('Right')),
  DropdownMenuItem(value: 4, child: Text('Top')),
  DropdownMenuItem(value: 8, child: Text('Bottom')),
  DropdownMenuItem(value: 5, child: Text('Top left')),
  DropdownMenuItem(value: 6, child: Text('Top right')),
  DropdownMenuItem(value: 9, child: Text('Bottom left')),
  DropdownMenuItem(value: 10, child: Text('Bottom right')),
];

const _boundsTypeOptions = <DropdownMenuItem<Object>>[
  DropdownMenuItem(value: 'OBS_BOUNDS_NONE', child: Text('None')),
  DropdownMenuItem(value: 'OBS_BOUNDS_STRETCH', child: Text('Stretch')),
  DropdownMenuItem(
    value: 'OBS_BOUNDS_SCALE_INNER',
    child: Text('Scale inner'),
  ),
  DropdownMenuItem(
    value: 'OBS_BOUNDS_SCALE_OUTER',
    child: Text('Scale outer'),
  ),
  DropdownMenuItem(
    value: 'OBS_BOUNDS_SCALE_TO_WIDTH',
    child: Text('Scale to width'),
  ),
  DropdownMenuItem(
    value: 'OBS_BOUNDS_SCALE_TO_HEIGHT',
    child: Text('Scale to height'),
  ),
  DropdownMenuItem(value: 'OBS_BOUNDS_MAX_ONLY', child: Text('Max only')),
];