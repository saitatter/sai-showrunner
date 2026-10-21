import 'dart:async';
import 'package:flutter/material.dart';

import 'package:showrunner_flutter/schema/json.dart';
import 'package:showrunner_flutter/schema/resource.dart';

import 'package:showrunner_flutter/components/data_inputs/resource_form.dart';
import 'package:showrunner_flutter/components/data_inputs/resource_field_values.dart';

int _audioSplitIdCounter = 0;
String _audioSplitId(Object? value) {
  final id = value?.toString().trim();
  return id == null || id.isEmpty
      ? 'split-${DateTime.now().microsecondsSinceEpoch}-${_audioSplitIdCounter++}'
      : id;
}

JsonMap _audioSplit(Map value) => {
  ...Map<String, dynamic>.from(value),
  'id': _audioSplitId(value['id']),
  'mute': value['mute'] == true,
  'volume': ((value['volume'] as num?)?.toDouble() ?? 100).clamp(0, 100),
};

class AudioSplitterEditor extends StatefulWidget {
  const AudioSplitterEditor({
    super.key,
    required this.resource,
    required this.onSave,
  });

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<AudioSplitterEditor> createState() => _AudioSplitterEditorState();
}

class _AudioSplitterEditorState extends State<AudioSplitterEditor> {
  late final TextEditingController _name;
  late List<JsonMap> _redirects;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: ResourceFieldValues.display(widget.resource.config['name']),
    );
    _redirects = ResourceFieldValues.maps(
      widget.resource.config['redirects'],
    ).map(_audioSplit).toList();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResourceForm(
    title: 'Edit audio splitter',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Audio outputs',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Add audio output',
            onPressed: () => setState(() => _redirects.insert(0, _newSplit())),
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      if (_redirects.isEmpty)
        const Text('No audio outputs defined.')
      else
        for (var index = 0; index < _redirects.length; index++)
          _AudioSplitCard(
            key: ValueKey(_redirects[index]['id']),
            index: index,
            split: _redirects[index],
            onChanged: (split) => setState(() => _redirects[index] = split),
            onDelete: () => setState(() => _redirects.removeAt(index)),
          ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'type': 'splitter',
          'redirects': [
            for (final redirect in _redirects) _savedAudioSplit(redirect),
          ],
        },
        state: widget.resource.state,
      ),
    ),
  );

  JsonMap _newSplit() => {
    'id': _audioSplitId(null),
    'mute': false,
    'volume': 100,
  };
}

JsonMap _savedAudioSplit(JsonMap split) {
  final saved = <String, dynamic>{...split};
  final output = saved['output']?.toString().trim();
  if (output == null || output.isEmpty) {
    saved.remove('output');
  } else {
    saved['output'] = output;
  }
  saved['id'] = _audioSplitId(saved['id']);
  saved['mute'] = saved['mute'] == true;
  saved['volume'] = ((saved['volume'] as num?)?.toDouble() ?? 100).clamp(
    0,
    100,
  );
  return saved;
}

class _AudioSplitCard extends StatelessWidget {
  const _AudioSplitCard({
    super.key,
    required this.index,
    required this.split,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final JsonMap split;
  final ValueChanged<JsonMap> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = split['mute'] == true;
    final volume = ((split['volume'] as num?)?.toDouble() ?? 100)
        .clamp(0, 100)
        .toDouble();
    return Card(
      color: muted ? Theme.of(context).colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Audio output ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Tooltip(
                  message: muted ? 'Unmute audio output' : 'Mute audio output',
                  child: Switch(
                    value: muted,
                    onChanged: (value) => onChanged({...split, 'mute': value}),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete audio output',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextFormField(
              key: ValueKey('audio-split-output-${split['id']}'),
              initialValue: split['output']?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'Output resource ID',
              ),
              onChanged: (value) => onChanged({...split, 'output': value}),
            ),
            Row(
              children: [
                const SizedBox(width: 64, child: Text('Volume')),
                Expanded(
                  child: Slider(
                    value: volume,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${volume.round()}',
                    onChanged: (value) =>
                        onChanged({...split, 'volume': value}),
                  ),
                ),
                SizedBox(width: 42, child: Text('${volume.round()}%')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
