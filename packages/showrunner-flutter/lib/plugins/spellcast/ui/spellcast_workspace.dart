import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../persistence/resource_repository.dart';
import '../../../schema/automation.dart';
import '../../../schema/resource.dart';
import '../../../plugins/runtime/provider_event_workers.dart';
import '../../../services/plugin_event_hub.dart';
import '../../../services/showrunner_data_service.dart';
import '../cloud_pubsub.dart';
import '../runtime.dart';

class SpellcastWorkspace extends StatefulWidget {
  const SpellcastWorkspace({
    super.key,
    required this.dataService,
    required this.eventHub,
    required this.providerEvents,
  });

  final ShowRunnerDataService dataService;
  final DartPluginEventHub eventHub;
  final ProviderEventRuntime providerEvents;

  @override
  State<SpellcastWorkspace> createState() => _SpellcastWorkspaceState();
}

class _SpellcastWorkspaceState extends State<SpellcastWorkspace> {
  late final ResourceRepository _repository;
  late final SpellcastService _service;
  late final SpellcastCloudPubSubController _cloudPubSub;
  List<ResourceData> _spells = const [];
  List<SpellcastRemoteSpell> _remoteSpells = const [];
  Object? _error;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _repository = ResourceRepository(
      Directory('${widget.dataService.userDirectory.path}/spellcast/spells'),
    );
    _service = SpellcastService(dataService: widget.dataService);
    _cloudPubSub = SpellcastCloudPubSubController(
      dataService: widget.dataService,
      eventHub: widget.eventHub,
    );
    _cloudPubSub.addListener(_onCloudPubSubChanged);
    widget.providerEvents.addListener(_onProfileActivityChanged);
    _loadLocal();
  }

  void _onCloudPubSubChanged() {
    if (mounted) setState(() {});
  }

  void _onProfileActivityChanged() {
    unawaited(_syncCloudSpells(_spells));
  }

  @override
  void dispose() {
    _cloudPubSub.removeListener(_onCloudPubSubChanged);
    widget.providerEvents.removeListener(_onProfileActivityChanged);
    unawaited(_cloudPubSub.stop());
    super.dispose();
  }

  Future<void> _loadLocal({bool clearError = true}) async {
    try {
      final spells = await _repository.list();
      if (!mounted) return;
      setState(() {
        _spells = spells;
        _loading = false;
        if (clearError) _error = null;
      });
      await _syncCloudSpells(spells);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _syncRemote() async {
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final remote = await _service.listSpells();
      final local = [..._spells];
      for (final spell in remote) {
        final index = local.indexWhere(
          (resource) => resource.config['spellId']?.toString() == spell.id,
        );
        final resource = ResourceData(
          id: index < 0 ? _newResourceId(spell.id) : local[index].id,
          config: {
            if (index >= 0) ...local[index].config,
            'name': spell.name,
            'spellId': spell.id,
            'spellData': {
              if (index >= 0 && local[index].config['spellData'] is Map)
                ...Map<String, dynamic>.from(
                  local[index].config['spellData'] as Map,
                ),
              'enabled': spell.enabled,
              'description': spell.description,
              'bits': spell.bits,
              'color': spell.color,
            },
          },
        );
        if (index < 0) {
          local.add(resource);
        } else {
          local[index] = resource;
        }
        await _repository.save(resource);
      }
      if (!mounted) return;
      setState(() {
        _spells = local;
        _remoteSpells = remote;
        _syncing = false;
      });
      await _syncCloudSpells(local);
    } catch (error) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _create() async {
    final values = await showDialog<_SpellcastFormValue>(
      context: context,
      builder: (context) => const _SpellcastFormDialog(),
    );
    if (values == null) return;
    final resource = ResourceData(
      id: _newResourceId(values.name),
      config: _config(values),
    );
    await _repository.save(resource);
    try {
      final remote = await _service.createSpell(
        name: values.name,
        description: values.description,
        bits: values.bits,
        color: values.color,
        enabled: values.enabled,
      );
      await _repository.save(
        ResourceData(
          id: resource.id,
          config: {...resource.config, 'spellId': remote.id},
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
    await _loadLocal(clearError: false);
  }

  Future<void> _edit(ResourceData resource) async {
    final values = await showDialog<_SpellcastFormValue>(
      context: context,
      builder: (context) => _SpellcastFormDialog(resource: resource),
    );
    if (values == null) return;
    final updated = ResourceData(
      id: resource.id,
      config: {
        ...resource.config,
        ..._config(values),
        if (resource.config['spellData'] is Map)
          'spellData': {
            ...Map<String, dynamic>.from(resource.config['spellData'] as Map),
            ..._config(values)['spellData'] as Map<String, dynamic>,
          },
      },
    );
    await _repository.save(updated);
    final remoteId = updated.config['spellId']?.toString() ?? '';
    if (remoteId.isNotEmpty) {
      try {
        await _service.updateSpell(
          remoteId,
          name: values.name,
          description: values.description,
          bits: values.bits,
          color: values.color,
          enabled: values.enabled,
        );
      } catch (error) {
        if (mounted) setState(() => _error = error);
      }
    }
    await _loadLocal(clearError: false);
  }

  Future<void> _toggle(ResourceData resource, bool enabled) async {
    final spellData = resource.config['spellData'] is Map
        ? Map<String, dynamic>.from(resource.config['spellData'] as Map)
        : <String, dynamic>{};
    final updated = ResourceData(
      id: resource.id,
      config: {
        ...resource.config,
        'spellData': {...spellData, 'enabled': enabled},
      },
    );
    await _repository.save(updated);
    final remoteId = updated.config['spellId']?.toString() ?? '';
    if (remoteId.isNotEmpty) {
      try {
        await _service.updateSpell(remoteId, enabled: enabled);
      } catch (error) {
        if (mounted) setState(() => _error = error);
      }
    }
    await _loadLocal(clearError: false);
  }

  Future<void> _delete(ResourceData resource) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete spell?'),
        content: Text('Delete ${resource.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final remoteId = resource.config['spellId']?.toString() ?? '';
    try {
      if (remoteId.isNotEmpty) await _service.deleteSpell(remoteId);
    } catch (error) {
      if (mounted) setState(() => _error = error);
      return;
    }
    await _repository.delete(resource.id);
    await _loadLocal();
  }

  Future<void> _syncCloudSpells(Iterable<ResourceData> spells) async {
    final active = resolveActiveSpellcastIds(
      widget.providerEvents.activeProfileTriggers,
      spells,
    );
    if (active.isNotEmpty) {
      if (_cloudPubSub.shouldRun) {
        await _cloudPubSub.setActiveSpellIds(active);
      } else {
        await _cloudPubSub.start(activeSpellIds: active);
      }
    } else if (_cloudPubSub.shouldRun) {
      await _cloudPubSub.stop();
    }
  }

  Future<void> _connectCloudPubSub() =>
      _cloudPubSub.start(activeSpellIds: _activeSpellIds(_spells));

  Future<void> _disconnectCloudPubSub() => _cloudPubSub.stop();

  Iterable<String> _activeSpellIds(Iterable<ResourceData> spells) {
    return resolveActiveSpellcastIds(
      widget.providerEvents.activeProfileTriggers,
      spells,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Spellcast',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _syncing ? null : _syncRemote,
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: const Text('Sync remote'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Create spell'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Manage local Spellcast resources and synchronize them with the connected Twitch channel.',
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(
              _cloudPubSub.isConnected
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              color: _cloudPubSub.isConnected ? Colors.green : null,
            ),
            title: const Text('Cloud PubSub'),
            subtitle: Text(
              _cloudPubSub.isConnected
                  ? 'Connected; active Spellcast hooks are synchronized.'
                  : _cloudPubSub.isConnecting
                  ? 'Connecting...'
                  : _cloudPubSub.lastError == null
                  ? 'Disconnected.'
                  : 'Disconnected: ${_cloudPubSub.lastError}',
            ),
            trailing: _cloudPubSub.isConnected || _cloudPubSub.isConnecting
                ? OutlinedButton.icon(
                    onPressed: _cloudPubSub.isConnecting
                        ? null
                        : _disconnectCloudPubSub,
                    icon: const Icon(Icons.cloud_off_outlined),
                    label: const Text('Disconnect'),
                  )
                : OutlinedButton.icon(
                    onPressed: _connectCloudPubSub,
                    icon: const Icon(Icons.cloud_outlined),
                    label: const Text('Connect'),
                  ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            'Spellcast error: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        if (_spells.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.auto_awesome),
              title: Text('No spells defined'),
              subtitle: Text('Create a spell or synchronize the remote list.'),
            ),
          )
        else
          for (final spell in _spells)
            _SpellListTile(
              resource: spell,
              onChanged: (enabled) => _toggle(spell, enabled),
              onEdit: () => _edit(spell),
              onDelete: () => _delete(spell),
            ),
        if (_remoteSpells.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '${_remoteSpells.length} remote spells synchronized',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _SpellListTile extends StatelessWidget {
  const _SpellListTile({
    required this.resource,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final ResourceData resource;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final data = resource.config['spellData'] is Map
        ? Map<String, dynamic>.from(resource.config['spellData'] as Map)
        : const <String, dynamic>{};
    final color = _parseColor(data['color']?.toString());
    return Card(
      child: ListTile(
        leading: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${data['bits'] ?? 10}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(resource.name),
        subtitle: Text(
          '${resource.config['spellId'] ?? 'local'} · ${data['description'] ?? ''}',
        ),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Switch(value: data['enabled'] == true, onChanged: onChanged),
            IconButton(
              tooltip: 'Edit spell',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete spell',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SpellcastFormValue {
  const _SpellcastFormValue({
    required this.name,
    required this.description,
    required this.bits,
    required this.color,
    required this.enabled,
  });

  final String name;
  final String description;
  final int bits;
  final String color;
  final bool enabled;
}

class _SpellcastFormDialog extends StatefulWidget {
  const _SpellcastFormDialog({this.resource});

  final ResourceData? resource;

  @override
  State<_SpellcastFormDialog> createState() => _SpellcastFormDialogState();
}

class _SpellcastFormDialogState extends State<_SpellcastFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late int _bits;
  late String _color;
  late bool _enabled;

  static const _bitsOptions = [
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
  static const _colors = [
    '#719ece',
    '#803FCC',
    '#CC3F9A',
    '#CCB23F',
    '#7ECC3F',
    '#CC4141',
    '#CC691E',
  ];

  @override
  void initState() {
    super.initState();
    final resource = widget.resource;
    final data = resource?.config['spellData'] is Map
        ? Map<String, dynamic>.from(resource!.config['spellData'] as Map)
        : const <String, dynamic>{};
    _name = TextEditingController(text: resource?.name ?? '');
    _description = TextEditingController(
      text: data['description']?.toString() ?? '',
    );
    _bits = _nearestBits((data['bits'] as num?)?.round() ?? 10);
    _color = _colors.contains(data['color'])
        ? data['color'] as String
        : _colors.first;
    _enabled = data['enabled'] == true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.resource == null ? 'Create spell' : 'Edit spell'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            DropdownButtonFormField<int>(
              initialValue: _bits,
              decoration: const InputDecoration(labelText: 'Bits'),
              items: [
                for (final value in _bitsOptions)
                  DropdownMenuItem(value: value, child: Text('$value')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _bits = value);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _color,
              decoration: const InputDecoration(labelText: 'Color'),
              items: [
                for (final value in _colors)
                  DropdownMenuItem(
                    value: value,
                    child: Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          color: _parseColor(value),
                        ),
                        const SizedBox(width: 8),
                        Text(value),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _color = value);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
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
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      _SpellcastFormValue(
        name: name,
        description: _description.text.trim(),
        bits: _bits,
        color: _color,
        enabled: _enabled,
      ),
    );
  }
}

JsonMap _config(_SpellcastFormValue values) => {
  'name': values.name,
  'spellData': {
    'enabled': values.enabled,
    'description': values.description,
    'bits': values.bits,
    'color': values.color,
  },
};

int _nearestBits(int value) {
  const options = _SpellcastFormDialogState._bitsOptions;
  return options.reduce(
    (previous, current) =>
        (current - value).abs() < (previous - value).abs() ? current : previous,
  );
}

String _newResourceId(String remoteId) =>
    'spell-${remoteId.isEmpty ? DateTime.now().microsecondsSinceEpoch : remoteId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

Color _parseColor(String? value) {
  final normalized = value?.replaceFirst('#', '') ?? '719ece';
  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  return Color(int.tryParse(hex, radix: 16) ?? 0xFF719ECE);
}
