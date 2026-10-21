import 'dart:async';
import 'package:flutter/material.dart';

import 'package:showrunner_flutter/schema/resource.dart';

import 'package:showrunner_flutter/components/data_inputs/resource_form.dart';
import 'package:showrunner_flutter/components/data_inputs/resource_field_values.dart';

class ViewerGroupEditor extends StatefulWidget {
  const ViewerGroupEditor({
    super.key,
    required this.resource,
    required this.onSave,
  });

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;

  @override
  State<ViewerGroupEditor> createState() => _ViewerGroupEditorState();
}

class _ViewerGroupEditorState extends State<ViewerGroupEditor> {
  late final TextEditingController _name;
  late final TextEditingController _userId;
  late final Set<String> _userIds;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: ResourceFieldValues.display(widget.resource.config['name']),
    );
    _userId = TextEditingController();
    _userIds = {
      ...(widget.resource.config['userIds'] as List<dynamic>? ?? const []).map(
        (value) => value.toString(),
      ),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _userId.dispose();
    super.dispose();
  }

  void _addUser() {
    final userId = _userId.text.trim();
    if (userId.isEmpty) return;
    setState(() {
      _userIds.add(userId);
      _userId.clear();
    });
  }

  @override
  Widget build(BuildContext context) => ResourceForm(
    title: 'Edit Twitch viewer group',
    fields: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _userId,
              decoration: const InputDecoration(labelText: 'Add user ID'),
            ),
          ),
          IconButton(
            onPressed: _addUser,
            tooltip: 'Add user',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final userId in _userIds)
            InputChip(
              label: Text(userId),
              onDeleted: () => setState(() => _userIds.remove(userId)),
            ),
        ],
      ),
    ],
    onSave: () => widget.onSave(
      ResourceData(
        id: widget.resource.id,
        config: {
          ...widget.resource.config,
          'name': _name.text.trim(),
          'userIds': _userIds.toList()..sort(),
        },
        state: widget.resource.state,
      ),
    ),
  );
}
