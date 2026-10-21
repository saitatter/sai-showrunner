import 'dart:async';
import 'package:flutter/material.dart';

import 'package:showrunner_flutter/schema/resource.dart';

import 'package:showrunner_flutter/components/data_inputs/resource_form.dart';
import 'package:showrunner_flutter/components/data_inputs/resource_field_values.dart';

class SpellcastEditor extends StatefulWidget {
  const SpellcastEditor({
    super.key,
    required this.resource,
    required this.onSave,
  });

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<SpellcastEditor> createState() => _SpellcastEditorState();
}

class _SpellcastEditorState extends State<SpellcastEditor> {
  static const _bitAmounts = <int>[
    10,
    20,
    30,
    40,
    50,
    100,
    150,
    200,
    250,
    300,
    350,
    400,
    450,
    500,
    550,
    600,
    650,
    700,
    750,
    800,
    850,
    900,
    950,
    1000,
    1050,
    1100,
    1150,
    1200,
    1250,
    1300,
    1350,
    1400,
    1450,
    1500,
    1550,
    1600,
    1650,
    1700,
    1750,
    1800,
    1850,
    1900,
    1950,
    2000,
  ];
  static const _colors = <String>[
    '#719ece',
    '#803FCC',
    '#CC3F9A',
    '#CCB23F',
    '#7ECC3F',
    '#CC4141',
    '#CC691E',
  ];

  late final TextEditingController _name;
  late final TextEditingController _spellId;
  late final TextEditingController _description;
  late bool _enabled;
  late int _bits;
  late String _color;

  Map<String, dynamic> get _spellData =>
      widget.resource.config['spellData'] is Map
      ? Map<String, dynamic>.from(widget.resource.config['spellData'] as Map)
      : <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    final spellData = _spellData;
    _name = TextEditingController(
      text: ResourceFieldValues.display(widget.resource.config['name']),
    );
    _spellId = TextEditingController(
      text: ResourceFieldValues.display(widget.resource.config['spellId']),
    );
    _description = TextEditingController(
      text: ResourceFieldValues.display(spellData['description']),
    );
    _enabled = spellData['enabled'] == true;
    _bits = _nearestBitAmount((spellData['bits'] as num?)?.toInt() ?? 10);
    final configuredColor = spellData['color']?.toString();
    _color = _colors.contains(configuredColor)
        ? configuredColor!
        : _colors.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _spellId.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResourceForm(
    title: 'Edit Spellcast spell',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Title'),
      ),
      TextField(
        controller: _spellId,
        decoration: const InputDecoration(labelText: 'Spell ID'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enabled'),
        value: _enabled,
        onChanged: (value) => setState(() => _enabled = value),
      ),
      TextField(
        controller: _description,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Description'),
      ),
      DropdownButtonFormField<int>(
        initialValue: _bits,
        decoration: const InputDecoration(labelText: 'Bits'),
        items: [
          for (final amount in _bitAmounts)
            DropdownMenuItem(value: amount, child: Text('$amount bits')),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _bits = value);
        },
      ),
      DropdownButtonFormField<String>(
        initialValue: _color,
        decoration: const InputDecoration(labelText: 'Color'),
        items: [
          for (final color in _colors)
            DropdownMenuItem(value: color, child: Text(color)),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _color = value);
        },
      ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'spellId': _spellId.text.trim(),
          'spellData': {
            ..._spellData,
            'enabled': _enabled,
            'description': _description.text,
            'bits': _bits,
            'color': _color,
          },
        },
        state: widget.resource.state,
      ),
    ),
  );

  int _nearestBitAmount(int value) => _bitAmounts.reduce(
    (left, right) =>
        (value - left).abs() <= (value - right).abs() ? left : right,
  );
}
