import 'package:flutter/material.dart';

import '../../plugins/registry/plugin_registry.dart';
import '../../schema/automation.dart';

int _conditionIdCounter = 0;

/// Normalizes expression shapes accepted by the profile runtime into the
/// Boolean-group root expected by the visual editor without discarding data.
JsonMap normalizeActivationCondition(JsonMap source) {
  final condition = _deepMap(source);
  if (condition.isEmpty ||
      (condition['type'] == 'literal' && condition['value'] == true)) {
    return createAlwaysOnCondition();
  }
  if (condition['type'] == 'literal' && condition['value'] == false) {
    return {
      'type': 'group',
      'operator': 'and',
      'operands': [
        {
          'type': 'value',
          'id': 'literal-false',
          'lhs': {'type': 'value', 'schemaType': 'Boolean', 'value': false},
          'operator': 'equal',
          'rhs': {'type': 'value', 'schemaType': 'Boolean', 'value': true},
        },
      ],
    };
  }
  if (condition['type'] == 'group') {
    condition['operator'] = condition['operator'] == 'or' ? 'or' : 'and';
    condition['operands'] = (condition['operands'] as List? ?? const [])
        .whereType<Map>()
        .map((operand) => _deepMap(operand))
        .toList();
    return condition;
  }
  if (condition['type'] == 'value' || condition['type'] == 'range') {
    return {
      'type': 'group',
      'operator': 'and',
      'operands': [condition],
    };
  }
  return condition;
}

JsonMap createAlwaysOnCondition() => {
  'type': 'group',
  'operator': 'and',
  'operands': <JsonMap>[],
};

JsonMap _deepMap(Map source) => {
  for (final entry in source.entries)
    entry.key.toString(): entry.value is Map
        ? _deepMap(entry.value as Map)
        : entry.value is List
        ? (entry.value as List)
              .map((item) => item is Map ? _deepMap(item) : item)
              .toList()
        : entry.value,
};

/// Flutter counterpart of the profile activation Boolean Expression editor.
/// The persisted representation intentionally stays the same map shape used
/// by profile files and by the runtime evaluator.
class BooleanExpressionEditor extends StatelessWidget {
  const BooleanExpressionEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.registryFuture,
  });

  final JsonMap value;
  final ValueChanged<JsonMap> onChanged;
  final Future<DartPluginRegistry>? registryFuture;

  @override
  Widget build(BuildContext context) {
    if (value['type'] != 'group') {
      return _UnsupportedCondition(
        value: value,
        onReset: () => onChanged(_emptyGroup()),
      );
    }
    return _BooleanGroupEditor(
      group: value,
      onChanged: onChanged,
      registryFuture: registryFuture,
      root: true,
    );
  }
}

class _BooleanGroupEditor extends StatelessWidget {
  const _BooleanGroupEditor({
    required this.group,
    required this.onChanged,
    required this.registryFuture,
    this.root = false,
  });

  final JsonMap group;
  final ValueChanged<JsonMap> onChanged;
  final Future<DartPluginRegistry>? registryFuture;
  final bool root;

  List<JsonMap> get _operands => (group['operands'] as List? ?? const [])
      .whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value))
      .toList();

  void _update({String? operator, List<JsonMap>? operands}) {
    onChanged({
      ...group,
      'type': 'group',
      'operator': operator ?? (group['operator'] == 'and' ? 'and' : 'or'),
      'operands': operands ?? _operands,
    });
  }

  void _addValue() {
    _update(
      operands: [
        ..._operands,
        {
          'type': 'value',
          'id': _newConditionId(),
          'lhs': {'type': 'state', 'plugin': null, 'state': null},
          'operator': 'equal',
          'rhs': {'type': 'value', 'schemaType': 'String', 'value': ''},
        },
      ],
    );
  }

  void _addGroup() {
    _update(
      operands: [
        ..._operands,
        {
          'type': 'group',
          'id': _newConditionId(),
          'operator': 'or',
          'operands': <JsonMap>[],
        },
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final operands = _operands;
    final isAnd = group['operator'] == 'and';
    final colorScheme = Theme.of(context).colorScheme;
    final accent = operands.length > 1
        ? (isAnd ? const Color(0xff49a46a) : const Color(0xff4e8de6))
        : colorScheme.outlineVariant;

    return Container(
      margin: EdgeInsets.only(bottom: root ? 0 : 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: accent, width: 2),
        borderRadius: BorderRadius.circular(7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: operands.length > 1
                ? (isAnd ? const Color(0xff244733) : const Color(0xff233d63))
                : colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                if (!root) ...[
                  Icon(
                    Icons.drag_indicator,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                ],
                SizedBox(
                  width: 94,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(group['operator'] == 'and' ? 'and' : 'or'),
                    initialValue: group['operator'] == 'and' ? 'and' : 'or',
                    isDense: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'and', child: Text('All')),
                      DropdownMenuItem(value: 'or', child: Text('Any')),
                    ],
                    onChanged: (value) {
                      if (value != null) _update(operator: value);
                    },
                  ),
                ),
                const Spacer(),
                _GroupActionButton(
                  icon: Icons.add,
                  label: 'Value',
                  onPressed: _addValue,
                ),
                const SizedBox(width: 4),
                _GroupActionButton(
                  icon: Icons.add,
                  label: 'Group',
                  onPressed: _addGroup,
                ),
                if (!root && group['id'] != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Delete group',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onChanged(<String, dynamic>{}),
                    icon: const Icon(Icons.delete_outline, size: 19),
                  ),
                ],
              ],
            ),
          ),
          Container(
            color: colorScheme.surface,
            padding: const EdgeInsets.all(8),
            child: operands.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('No Conditions (Always On)'),
                    ),
                  )
                : ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: operands.length,
                    onReorderItem: (oldIndex, newIndex) {
                      final reordered = [...operands];
                      final item = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, item);
                      _update(operands: reordered);
                    },
                    itemBuilder: (context, index) {
                      final condition = operands[index];
                      final id =
                          condition['id']?.toString() ?? 'condition-$index';
                      return Padding(
                        key: ValueKey(id),
                        padding: const EdgeInsets.only(bottom: 5),
                        child: _ConditionEditor(
                          condition: condition,
                          registryFuture: registryFuture,
                          onChanged: (updated) {
                            if (updated.isEmpty) {
                              final remaining = [...operands]..removeAt(index);
                              _update(operands: remaining);
                            } else {
                              final updatedOperands = [...operands];
                              updatedOperands[index] = updated;
                              _update(operands: updatedOperands);
                            }
                          },
                          dragHandle: ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_indicator),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConditionEditor extends StatelessWidget {
  const _ConditionEditor({
    required this.condition,
    required this.registryFuture,
    required this.onChanged,
    required this.dragHandle,
  });

  final JsonMap condition;
  final Future<DartPluginRegistry>? registryFuture;
  final ValueChanged<JsonMap> onChanged;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    if (condition['type'] == 'group') {
      return _BooleanGroupEditor(
        group: condition,
        registryFuture: registryFuture,
        onChanged: (updated) => onChanged(
          updated.isEmpty ? <String, dynamic>{} : {...condition, ...updated},
        ),
      );
    }
    if (condition['type'] == 'value') {
      return _BooleanValueEditor(
        value: condition,
        registryFuture: registryFuture,
        onChanged: onChanged,
        dragHandle: dragHandle,
      );
    }
    return _UnsupportedCondition(
      value: condition,
      compact: true,
      onReset: () => onChanged(<String, dynamic>{}),
      dragHandle: dragHandle,
    );
  }
}

class _BooleanValueEditor extends StatelessWidget {
  const _BooleanValueEditor({
    required this.value,
    required this.registryFuture,
    required this.onChanged,
    required this.dragHandle,
  });

  final JsonMap value;
  final Future<DartPluginRegistry>? registryFuture;
  final ValueChanged<JsonMap> onChanged;
  final Widget dragHandle;

  void _set(String key, Object? next) => onChanged({...value, key: next});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lhs = _map(value['lhs']);
    final rhs = _map(value['rhs']);
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            color: colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: dragHandle,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final vertical = constraints.maxWidth < 560;
                final operator = DropdownButtonFormField<String>(
                  initialValue: _operatorValue(value['operator']),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Compare',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'lessThanEq', child: Text('≤')),
                    DropdownMenuItem(value: 'lessThan', child: Text('<')),
                    DropdownMenuItem(value: 'equal', child: Text('=')),
                    DropdownMenuItem(value: 'notEqual', child: Text('≠')),
                    DropdownMenuItem(value: 'greaterThan', child: Text('>')),
                    DropdownMenuItem(value: 'greaterThanEq', child: Text('≥')),
                  ],
                  onChanged: (next) {
                    if (next != null) _set('operator', next);
                  },
                );
                final left = _ExpressionValueEditor(
                  value: lhs,
                  registryFuture: registryFuture,
                  onChanged: (next) => _set('lhs', next),
                );
                final right = _ExpressionValueEditor(
                  value: rhs,
                  registryFuture: registryFuture,
                  onChanged: (next) => _set('rhs', next),
                );
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: vertical
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            left,
                            const SizedBox(height: 6),
                            operator,
                            const SizedBox(height: 6),
                            right,
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: 8),
                            SizedBox(width: 124, child: operator),
                            const SizedBox(width: 8),
                            Expanded(child: right),
                          ],
                        ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Delete condition',
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(<String, dynamic>{}),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _ExpressionValueEditor extends StatelessWidget {
  const _ExpressionValueEditor({
    required this.value,
    required this.registryFuture,
    required this.onChanged,
  });

  final JsonMap value;
  final Future<DartPluginRegistry>? registryFuture;
  final ValueChanged<JsonMap> onChanged;

  @override
  Widget build(BuildContext context) {
    if (value['type'] != 'state' && value['type'] != 'value') {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Operand', isDense: true),
        child: Text(
          'Operand type "${value['type'] ?? 'unknown'}" is not editable here.',
        ),
      );
    }
    final type = value['type'] == 'value' ? 'value' : 'state';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'state', label: Text('State')),
            ButtonSegment(value: 'value', label: Text('Value')),
          ],
          selected: {type},
          onSelectionChanged: (selection) {
            final selected = selection.first;
            onChanged(
              selected == 'state'
                  ? {'type': 'state', 'plugin': null, 'state': null}
                  : {'type': 'value', 'schemaType': 'String', 'value': ''},
            );
          },
        ),
        const SizedBox(height: 6),
        if (type == 'state')
          _StateValueSelector(
            value: value,
            registryFuture: registryFuture,
            onChanged: onChanged,
          )
        else
          _LiteralValueEditor(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _StateValueSelector extends StatelessWidget {
  const _StateValueSelector({
    required this.value,
    required this.registryFuture,
    required this.onChanged,
  });

  final JsonMap value;
  final Future<DartPluginRegistry>? registryFuture;
  final ValueChanged<JsonMap> onChanged;

  @override
  Widget build(BuildContext context) {
    final future = registryFuture;
    if (future == null) {
      return const InputDecorator(
        decoration: InputDecoration(labelText: 'State', isDense: true),
        child: Text('No plugin states available'),
      );
    }
    return FutureBuilder<DartPluginRegistry>(
      future: future,
      builder: (context, snapshot) {
        final registry = snapshot.data;
        if (registry == null) {
          return InputDecorator(
            decoration: const InputDecoration(
              labelText: 'State',
              isDense: true,
            ),
            child: Text(
              snapshot.connectionState == ConnectionState.waiting
                  ? 'Loading states...'
                  : 'No plugin states available',
            ),
          );
        }
        return AnimatedBuilder(
          animation: registry,
          builder: (context, _) {
            final states = <({String key, String label})>[];
            for (final plugin in registry.plugins) {
              final knownIds = <String>{};
              for (final state in plugin.states) {
                knownIds.add(state.id.value);
                states.add((
                  key: '${plugin.id.value}::${state.id.value}',
                  label: '${plugin.name} - ${state.displayName}',
                ));
              }
              for (final stateId
                  in registry.stateValues(plugin.id.value).keys) {
                if (knownIds.add(stateId)) {
                  states.add((
                    key: '${plugin.id.value}::$stateId',
                    label: '${plugin.name} - $stateId',
                  ));
                }
              }
            }
            final stored = value['plugin'] is String && value['state'] is String
                ? '${value['plugin']}::${value['state']}'
                : null;
            final selected = states.any((state) => state.key == stored)
                ? stored
                : null;
            return DropdownButtonFormField<String>(
              key: ValueKey(selected),
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'State',
                isDense: true,
              ),
              hint: const Text('Select state'),
              items: [
                for (final state in states)
                  DropdownMenuItem(value: state.key, child: Text(state.label)),
                if (stored != null &&
                    !states.any((state) => state.key == stored))
                  DropdownMenuItem(
                    value: stored,
                    child: Text('$stored (unavailable)'),
                  ),
              ],
              onChanged: (next) {
                if (next == null) return;
                final separator = next.indexOf('::');
                if (separator < 0) return;
                onChanged({
                  'type': 'state',
                  'plugin': next.substring(0, separator),
                  'state': next.substring(separator + 2),
                });
              },
            );
          },
        );
      },
    );
  }
}

class _LiteralValueEditor extends StatelessWidget {
  const _LiteralValueEditor({required this.value, required this.onChanged});

  final JsonMap value;
  final ValueChanged<JsonMap> onChanged;

  @override
  Widget build(BuildContext context) {
    final kind = value['schemaType']?.toString() ?? 'String';
    const knownKinds = {'String', 'Number', 'Integer', 'Boolean'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(kind),
          initialValue: kind,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Type', isDense: true),
          items: [
            const DropdownMenuItem(value: 'String', child: Text('Text')),
            const DropdownMenuItem(value: 'Number', child: Text('Number')),
            const DropdownMenuItem(value: 'Integer', child: Text('Integer')),
            const DropdownMenuItem(value: 'Boolean', child: Text('Boolean')),
            if (!knownKinds.contains(kind))
              DropdownMenuItem(value: kind, child: Text('$kind (stored type)')),
          ],
          onChanged: (next) {
            if (next != null) {
              onChanged({
                ...value,
                'schemaType': next,
                'value': _emptyValue(next),
              });
            }
          },
        ),
        const SizedBox(height: 6),
        if (kind == 'Boolean')
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Value'),
            value: value['value'] == true,
            onChanged: (next) => onChanged({...value, 'value': next}),
          )
        else
          TextFormField(
            key: ValueKey('literal:$kind'),
            initialValue: value['value']?.toString() ?? '',
            keyboardType: kind == 'String'
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: kind == 'String' ? 'Value' : 'Value ($kind)',
              isDense: true,
            ),
            onChanged: (text) {
              final parsed = switch (kind) {
                'Number' => num.tryParse(text),
                'Integer' => int.tryParse(text),
                _ => text,
              };
              onChanged({...value, 'value': parsed});
            },
          ),
      ],
    );
  }
}

class _UnsupportedCondition extends StatelessWidget {
  const _UnsupportedCondition({
    required this.value,
    required this.onReset,
    this.compact = false,
    this.dragHandle,
  });

  final JsonMap value;
  final VoidCallback onReset;
  final bool compact;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.error),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          ?dragHandle,
          const Icon(Icons.warning_amber_rounded),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              compact
                  ? 'Condition type "${value['type'] ?? 'unknown'}" cannot be edited visually.'
                  : 'Activation condition type "${value['type'] ?? 'unknown'}" cannot be edited visually.',
            ),
          ),
          TextButton(onPressed: onReset, child: const Text('Use Always On')),
        ],
      ),
    );
  }
}

class _GroupActionButton extends StatelessWidget {
  const _GroupActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 30),
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: Text(label),
  );
}

JsonMap _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

JsonMap _emptyGroup() => {
  'type': 'group',
  'operator': 'and',
  'operands': <JsonMap>[],
};

String _newConditionId() =>
    'condition_${DateTime.now().microsecondsSinceEpoch}_${_conditionIdCounter++}';

String _operatorValue(dynamic value) {
  const supported = {
    'lessThanEq',
    'lessThan',
    'equal',
    'notEqual',
    'greaterThan',
    'greaterThanEq',
  };
  return supported.contains(value) ? value.toString() : 'equal';
}

Object? _emptyValue(String kind) => switch (kind) {
  'Boolean' => false,
  'Number' => null,
  'Integer' => null,
  _ => '',
};
