import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../components/data_inputs/data_input.dart';
import '../../editor/showrunner_graph_editor.dart';
import '../graph/graph_workspace.dart';
import '../../persistence/profile_repository.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../runtime/profile_runtime.dart';
import '../../schema/automation.dart';
import '../../schema/profile.dart';
import '../../services/showrunner_data_service.dart';
import '../resources/resource_options.dart';

typedef ProfileEntry = ({
  String fileName,
  ShowRunnerProfile? profile,
  Object? error,
});

enum _ProfileCloseDecision { save, discard, cancel }

/// Lets the application close lifecycle ask the profile editor to resolve
/// unsaved changes without reaching into its widget state.
final class ProfileWorkspaceController {
  Future<bool> Function()? _closeGuard;
  Future<void> Function(String fileName)? _openProfile;
  String? _pendingProfile;

  void attach(
    Future<bool> Function() closeGuard, {
    Future<void> Function(String fileName)? openProfile,
  }) {
    _closeGuard = closeGuard;
    _openProfile = openProfile;
    final pendingProfile = _pendingProfile;
    if (pendingProfile != null && openProfile != null) {
      _pendingProfile = null;
      unawaited(openProfile(pendingProfile));
    }
  }

  void detach() {
    _closeGuard = null;
    _openProfile = null;
  }

  Future<bool> confirmClose() => _closeGuard?.call() ?? Future.value(true);

  Future<void> openProfile(String fileName) async {
    final opener = _openProfile;
    if (opener == null) {
      _pendingProfile = fileName;
      return;
    }
    await opener(fileName);
  }
}

class ProfileWorkspace extends StatefulWidget {
  const ProfileWorkspace({
    super.key,
    required this.dataService,
    required this.providerEvents,
    this.registryFuture,
    this.runtimeFuture,
    this.controller,
    this.onDirtyChanged,
    this.onEntriesChanged,
  });

  final ShowRunnerDataService dataService;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry>? registryFuture;
  final Future<DartProfileRuntime>? runtimeFuture;
  final ProfileWorkspaceController? controller;
  final ValueChanged<bool>? onDirtyChanged;
  final VoidCallback? onEntriesChanged;

  @override
  State<ProfileWorkspace> createState() => _ProfileWorkspaceState();
}

class _ProfileWorkspaceState extends State<ProfileWorkspace> {
  final _nameController = TextEditingController();
  final _conditionController = TextEditingController();
  late final ShowRunnerGraphEditor _activationEditor;
  late final ShowRunnerGraphEditor _deactivationEditor;
  List<ProfileEntry> _entries = [];
  int? _selectedIndex;
  String _activationMode = 'toggle';
  List<JsonMap> _triggers = [];
  bool _loading = true;
  bool _saving = false;
  bool _profileActive = false;
  DartProfileSession? _profileSession;
  Object? _error;
  bool _profileDirty = false;
  bool _synchronizing = false;
  late Future<void> _initialLoad;

  @override
  void initState() {
    super.initState();
    _activationEditor = ShowRunnerGraphEditor(
      resourceOptionsLoader: _resourceOptions,
    );
    _deactivationEditor = ShowRunnerGraphEditor(
      resourceOptionsLoader: _resourceOptions,
    );
    _nameController.addListener(_markDirty);
    _conditionController.addListener(_markDirty);
    _activationEditor.documentDirty.addListener(_markDirty);
    _deactivationEditor.documentDirty.addListener(_markDirty);
    _initialLoad = _load();
    widget.controller?.attach(_confirmClose, openProfile: _openProfile);
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _nameController.removeListener(_markDirty);
    _conditionController.removeListener(_markDirty);
    _activationEditor.documentDirty.removeListener(_markDirty);
    _deactivationEditor.documentDirty.removeListener(_markDirty);
    _nameController.dispose();
    _conditionController.dispose();
    unawaited(_profileSession?.dispose());
    _activationEditor.dispose();
    _deactivationEditor.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_synchronizing || _selectedIndex == null || _loading) return;
    if (_profileDirty) return;
    _profileDirty = true;
    widget.onDirtyChanged?.call(true);
    if (mounted) setState(() {});
  }

  void _markClean() {
    if (!_profileDirty) return;
    _profileDirty = false;
    widget.onDirtyChanged?.call(false);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries = await ProfileRepository.loadDirectory(
        Directory('${widget.dataService.userDirectory.path}/profiles'),
      );
      _entries = [
        for (final entry in entries)
          (
            fileName: entry.fileName,
            profile: entry.profile,
            error: entry.error,
          ),
      ];
      if (_entries.isNotEmpty &&
          (_selectedIndex == null || _selectedIndex! >= _entries.length)) {
        _selectProfile(0);
      } else if (_selectedIndex != null && _selectedIndex! < _entries.length) {
        _selectProfile(_selectedIndex!);
      }
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openProfile(String fileName) async {
    if (_loading) await _initialLoad;
    final index = _entries.indexWhere((entry) => entry.fileName == fileName);
    if (index < 0 || !await _confirmClose()) return;
    if (!mounted) return;
    setState(() => _selectProfile(index));
  }

  void _selectProfile(int index) {
    _synchronizing = true;
    final changed = _selectedIndex != index;
    _selectedIndex = index;
    if (changed) {
      unawaited(_profileSession?.dispose());
      _profileSession = null;
      _profileActive = false;
    }
    final entry = _entries[index];
    final profile = entry.profile;
    if (profile != null) {
      _nameController.text = profile.name;
      _conditionController.text = const JsonEncoder.withIndent(
        '  ',
      ).convert(profile.activationCondition);
      _activationMode = profile.activationMode;
      _triggers = profile.triggers
          .map((trigger) => Map<String, dynamic>.from(trigger))
          .toList();
      _activationEditor.loadAutomation(profile.activationAutomation);
      _deactivationEditor.loadAutomation(profile.deactivationAutomation);
    } else {
      _nameController.text = entry.fileName;
      _conditionController.text = '{}';
      _activationMode = 'toggle';
      _triggers = [];
      _activationEditor.loadAutomation(_emptyAutomation());
      _deactivationEditor.loadAutomation(_emptyAutomation());
    }
    _synchronizing = false;
    _markClean();
  }

  Future<void> _requestSelectProfile(int index) async {
    if (index == _selectedIndex || !await _confirmClose()) return;
    if (!mounted || index < 0 || index >= _entries.length) return;
    setState(() => _selectProfile(index));
  }

  Future<bool> _confirmClose() async {
    if (!_profileDirty || _selectedIndex == null) {
      return _stopCurrentProfile();
    }
    final fileName = _entries[_selectedIndex!].fileName;
    final decision = await showDialog<_ProfileCloseDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved profile changes'),
        content: Text('Save changes to $fileName before closing?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_ProfileCloseDecision.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_ProfileCloseDecision.discard),
            child: const Text("Don't Save"),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_ProfileCloseDecision.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted ||
        decision == null ||
        decision == _ProfileCloseDecision.cancel) {
      return false;
    }
    if (decision == _ProfileCloseDecision.save) {
      await _saveProfile();
      if (!mounted || _profileDirty) return false;
      return _stopCurrentProfile();
    }
    _markClean();
    return _stopCurrentProfile();
  }

  Future<bool> _stopCurrentProfile() async {
    if (!_profileActive || _selectedIndex == null) return true;
    final entry = _entries[_selectedIndex!];
    try {
      final runtime = widget.runtimeFuture == null
          ? null
          : await widget.runtimeFuture;
      await _profileSession?.dispose();
      _profileSession = null;
      if (runtime != null && entry.profile != null) {
        await runtime.deactivate(entry.fileName, entry.profile!);
      }
      widget.providerEvents.updateProfileActivity(
        entry.fileName,
        active: false,
      );
      _profileActive = false;
      return true;
    } catch (error) {
      _error = error;
      if (mounted) setState(() {});
      return false;
    }
  }

  Future<void> _createProfile() async {
    if (!await _confirmClose()) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'profile_$timestamp.yaml';
    final profile = ShowRunnerProfile(
      name: 'New Profile',
      activationMode: 'toggle',
      triggers: const [],
      activationCondition: const {},
      activationAutomation: _emptyAutomation(),
      deactivationAutomation: _emptyAutomation(),
    );
    final repo = ProfileRepository(
      File('${widget.dataService.userDirectory.path}/profiles/$fileName'),
    );
    await repo.save(profile);
    await _load();
    final index = _entries.indexWhere((entry) => entry.fileName == fileName);
    if (index != -1 && mounted) {
      setState(() => _selectProfile(index));
    }
    widget.onEntriesChanged?.call();
  }

  Future<void> _saveProfile() async {
    if (_selectedIndex == null || _selectedIndex! >= _entries.length) return;
    setState(() => _saving = true);
    try {
      final entry = _entries[_selectedIndex!];
      final original = entry.profile;
      final condition = _parseCondition(_conditionController.text);
      final updated = ShowRunnerProfile(
        name: _nameController.text.trim(),
        activationMode: _activationMode,
        triggers: _triggers,
        activationCondition: condition,
        activationAutomation: _activationEditor.toAutomation(
          original?.activationAutomation ?? _emptyAutomation(),
        ),
        deactivationAutomation: _deactivationEditor.toAutomation(
          original?.deactivationAutomation ?? _emptyAutomation(),
        ),
        extra: original?.extra ?? const {},
      );
      final repo = ProfileRepository(
        File(
          '${widget.dataService.userDirectory.path}/profiles/${entry.fileName}',
        ),
      );
      await repo.save(updated);
      await _load();
      widget.onEntriesChanged?.call();
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _toggleProfile() async {
    final index = _selectedIndex;
    if (index == null || index >= _entries.length) return;
    final entry = _entries[index];
    final profile = entry.profile;
    final runtimeFuture = widget.runtimeFuture;
    if (profile == null || runtimeFuture == null) return;
    setState(() => _saving = true);
    try {
      final runtime = await runtimeFuture;
      if (_profileActive) {
        await _profileSession?.dispose();
        _profileSession = null;
        await runtime.deactivate(entry.fileName, profile);
        widget.providerEvents.updateProfileActivity(
          entry.fileName,
          active: false,
        );
      } else {
        await runtime.activate(entry.fileName, profile);
        _profileSession = runtime.watch(entry.fileName, profile);
        widget.providerEvents.updateProfileActivity(
          entry.fileName,
          active: true,
          triggers: profile.triggers,
        );
      }
      if (mounted) setState(() => _profileActive = !_profileActive);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteProfile(String fileName) async {
    if (_selectedIndex != null &&
        _selectedIndex! < _entries.length &&
        _entries[_selectedIndex!].fileName == fileName &&
        !await _confirmClose()) {
      return;
    }
    final file = File(
      '${widget.dataService.userDirectory.path}/profiles/$fileName',
    );
    if (await file.exists()) {
      await file.delete();
    }
    _selectedIndex = null;
    _markClean();
    await _load();
    widget.onEntriesChanged?.call();
  }

  Future<void> _addTrigger() async {
    final registry = widget.registryFuture == null
        ? null
        : await widget.registryFuture;
    if (!mounted) return;
    final selected = await showDialog<DartTriggerDefinition>(
      context: context,
      builder: (context) => _TriggerPickerDialog(registry: registry),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _triggers.add({
        'id': 'trigger_${DateTime.now().millisecondsSinceEpoch}',
        'plugin': selected.pluginId,
        'trigger': selected.triggerId,
        'config': <String, dynamic>{},
        'description': selected.displayName,
        'automation': _emptyAutomation().toJson(),
      });
      _markDirty();
    });
  }

  Future<void> _editTrigger(int index) async {
    final trigger = _triggers[index];
    final registry = widget.registryFuture == null
        ? null
        : await widget.registryFuture;
    if (!mounted) return;
    final result = await showDialog<JsonMap>(
      context: context,
      builder: (context) => _TriggerEditDialog(
        trigger: trigger,
        registry: registry,
        resourceOptionsLoader: _resourceOptions,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _triggers[index] = result;
      _markDirty();
    });
  }

  Future<List<String>> _resourceOptions(String resourceType) async {
    return loadResourceOptions(widget.dataService, resourceType);
  }

  void _removeTrigger(int index) {
    setState(() {
      _triggers.removeAt(index);
      _markDirty();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final selectedEntry =
        (_selectedIndex != null && _selectedIndex! < _entries.length)
        ? _entries[_selectedIndex!]
        : null;

    return Row(
      children: [
        SizedBox(
          width: 300,
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Column(
              children: [
                ListTile(
                  title: const Text(
                    'Profiles',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _createProfile,
                    tooltip: 'Create Profile',
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _entries.isEmpty
                      ? const Center(child: Text('No saved profiles'))
                      : ListView.builder(
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            final isSelected = index == _selectedIndex;
                            return ListTile(
                              selected: isSelected,
                              leading: Icon(
                                entry.profile == null
                                    ? Icons.error_outline
                                    : Icons.person,
                              ),
                              title: Text(
                                entry.profile?.name.isNotEmpty == true
                                    ? entry.profile!.name
                                    : entry.fileName,
                              ),
                              subtitle: Text(
                                entry.profile?.activationMode ?? 'Invalid',
                              ),
                              onTap: () =>
                                  unawaited(_requestSelectProfile(index)),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: selectedEntry == null
              ? const Center(child: Text('Select or create a profile to edit'))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: ListView(
                    children: [
                      Row(
                        children: [
                          Text(
                            'Edit Profile${_profileDirty ? ' *' : ''}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                _deleteProfile(selectedEntry.fileName),
                            tooltip: 'Delete Profile',
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _saving || widget.runtimeFuture == null
                                ? null
                                : _toggleProfile,
                            icon: Icon(
                              _profileActive ? Icons.stop : Icons.play_arrow,
                            ),
                            label: Text(
                              _profileActive ? 'Deactivate' : 'Activate',
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _saving ? null : _saveProfile,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: const Text('Save Profile'),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Error: $_error',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Profile Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _conditionController,
                        minLines: 2,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Activation condition (JSON)',
                          helperText:
                              'Use a group expression with operator and operands.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue:
                            [
                              'toggle',
                              'manual',
                              'automation',
                              'always',
                            ].contains(_activationMode)
                            ? _activationMode
                            : 'toggle',
                        decoration: const InputDecoration(
                          labelText: 'Activation Mode',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'toggle',
                            child: Text('Toggle'),
                          ),
                          DropdownMenuItem(
                            value: 'manual',
                            child: Text('Manual'),
                          ),
                          DropdownMenuItem(
                            value: 'automation',
                            child: Text('Automation'),
                          ),
                          DropdownMenuItem(
                            value: 'always',
                            child: Text('Always Active'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _activationMode = value ?? 'toggle');
                          _markDirty();
                        },
                      ),
                      const SizedBox(height: 24),
                      _InlineAutomationPanel(
                        label: 'On Activate',
                        editor: _activationEditor,
                        registryFuture:
                            widget.registryFuture ??
                            Future.value(DartPluginRegistry()),
                      ),
                      const SizedBox(height: 12),
                      _InlineAutomationPanel(
                        label: 'On Deactivate',
                        editor: _deactivationEditor,
                        registryFuture:
                            widget.registryFuture ??
                            Future.value(DartPluginRegistry()),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            'Triggers (${_triggers.length})',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: _addTrigger,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Trigger'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_triggers.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No triggers configured for this profile.',
                            ),
                          ),
                        )
                      else
                        ..._triggers.asMap().entries.map((entry) {
                          final index = entry.key;
                          final trigger = entry.value;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.bolt),
                              title: Text(
                                trigger['description']?.toString() ??
                                    'Trigger ${index + 1}',
                              ),
                              subtitle: Text(
                                '${trigger['plugin'] ?? 'unassigned'}:${trigger['trigger'] ?? 'event'} | '
                                'Queue: ${trigger['queue'] ?? 'default'}',
                              ),
                              trailing: Wrap(
                                children: [
                                  IconButton(
                                    tooltip: 'Edit trigger',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _editTrigger(index),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete trigger',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _removeTrigger(index),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

JsonMap _parseCondition(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const {};
  return _tryParseJsonObject(trimmed) ?? const {};
}

JsonMap? _tryParseJsonObject(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

class _TriggerPickerDialog extends StatelessWidget {
  const _TriggerPickerDialog({required this.registry});

  final DartPluginRegistry? registry;

  @override
  Widget build(BuildContext context) {
    final triggers = [
      for (final plugin in registry?.plugins ?? const <DartPluginManifest>[])
        for (final trigger in plugin.triggers) trigger,
    ];
    return AlertDialog(
      title: const Text('Add profile trigger'),
      content: SizedBox(
        width: 420,
        child: triggers.isEmpty
            ? const Text('No registered triggers are available.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final trigger in triggers)
                    ListTile(
                      leading: const Icon(Icons.bolt),
                      title: Text(trigger.displayName),
                      subtitle: Text(
                        '${trigger.pluginId}:${trigger.triggerId}',
                      ),
                      onTap: () => Navigator.of(context).pop(trigger),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _TriggerEditDialog extends StatefulWidget {
  const _TriggerEditDialog({
    required this.trigger,
    required this.registry,
    this.resourceOptionsLoader,
  });

  final JsonMap trigger;
  final DartPluginRegistry? registry;
  final GraphResourceOptionsLoader? resourceOptionsLoader;

  @override
  State<_TriggerEditDialog> createState() => _TriggerEditDialogState();
}

class _TriggerEditDialogState extends State<_TriggerEditDialog> {
  late final TextEditingController _description;
  late final TextEditingController _queue;
  late final TextEditingController _config;
  late bool _stop;
  late String? _selectedTriggerId;
  late dynamic _configValue;
  String? _error;

  List<DartTriggerDefinition> get _availableTriggers => [
    for (final plugin
        in widget.registry?.plugins ?? const <DartPluginManifest>[])
      ...plugin.triggers,
  ];

  DartTriggerDefinition? get _selectedTrigger => _availableTriggers
      .where(
        (trigger) =>
            '${trigger.pluginId}:${trigger.triggerId}' == _selectedTriggerId,
      )
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _description = TextEditingController(
      text: widget.trigger['description']?.toString() ?? '',
    );
    _queue = TextEditingController(
      text: widget.trigger['queue']?.toString() ?? '',
    );
    _config = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(
        widget.trigger['config'] is Map ? widget.trigger['config'] : const {},
      ),
    );
    _stop = widget.trigger['stop'] == true;
    _selectedTriggerId =
        widget.trigger['plugin'] is String &&
            widget.trigger['trigger'] is String
        ? '${widget.trigger['plugin']}:${widget.trigger['trigger']}'
        : null;
    _configValue = widget.trigger['config'] is Map
        ? Map<String, dynamic>.from(widget.trigger['config'] as Map)
        : <String, dynamic>{};
  }

  @override
  void dispose() {
    _description.dispose();
    _queue.dispose();
    _config.dispose();
    super.dispose();
  }

  void _save() {
    final text = _config.text.trim();
    final decoded = _selectedTrigger?.configSchema != null
        ? (_configValue is Map
              ? Map<String, dynamic>.from(_configValue as Map)
              : <String, dynamic>{})
        : text.isEmpty
        ? <String, dynamic>{}
        : _tryParseJsonObject(text);
    if (decoded == null) {
      setState(() => _error = 'Config must be a JSON object.');
      return;
    }
    final selectedTrigger = _selectedTrigger;
    Navigator.of(context).pop({
      ...widget.trigger,
      if (selectedTrigger != null) ...{
        'plugin': selectedTrigger.pluginId,
        'trigger': selectedTrigger.triggerId,
      },
      'description': _description.text.trim(),
      'config': decoded,
      if (_queue.text.trim().isNotEmpty) 'queue': _queue.text.trim(),
      if (_queue.text.trim().isEmpty) 'queue': null,
      'stop': _stop,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit trigger'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: _queue,
              decoration: const InputDecoration(labelText: 'Queue resource'),
            ),
            if (_availableTriggers.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue:
                    _availableTriggers.any(
                      (trigger) =>
                          '${trigger.pluginId}:${trigger.triggerId}' ==
                          _selectedTriggerId,
                    )
                    ? _selectedTriggerId
                    : null,
                decoration: const InputDecoration(labelText: 'Trigger'),
                items: [
                  for (final trigger in _availableTriggers)
                    DropdownMenuItem(
                      value: '${trigger.pluginId}:${trigger.triggerId}',
                      child: Text(
                        '${trigger.displayName} (${trigger.pluginId})',
                      ),
                    ),
                ],
                onChanged: (value) {
                  final trigger = _availableTriggers
                      .where(
                        (candidate) =>
                            '${candidate.pluginId}:${candidate.triggerId}' ==
                            value,
                      )
                      .firstOrNull;
                  setState(() {
                    _selectedTriggerId = value;
                    _configValue =
                        trigger == null || trigger.configSchema == null
                        ? <String, dynamic>{}
                        : constructDartDataInputDefault(trigger.configSchema!);
                    _config.text = const JsonEncoder.withIndent(
                      '  ',
                    ).convert(_configValue);
                  });
                },
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Stop propagation'),
              value: _stop,
              onChanged: (value) => setState(() => _stop = value),
            ),
            _buildConfigurationInput(),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  Widget _buildConfigurationInput() {
    final rawSchema = _selectedTrigger?.configSchema;
    if (rawSchema == null) {
      return TextField(
        controller: _config,
        minLines: 8,
        maxLines: 14,
        decoration: InputDecoration(
          labelText: 'Trigger config (JSON)',
          border: const OutlineInputBorder(),
          errorText: _error,
        ),
      );
    }
    return FutureBuilder<DartDataInputSchema>(
      future: _hydrateResourceInputSchema(
        rawSchema,
        widget.resourceOptionsLoader,
      ),
      builder: (context, snapshot) => snapshot.hasData
          ? DartDataInput(
              schema: snapshot.data!,
              value: _configValue,
              onChanged: (value) => setState(() => _configValue = value),
            )
          : const LinearProgressIndicator(),
    );
  }
}

Future<DartDataInputSchema> _hydrateResourceInputSchema(
  DartDataInputSchema schema,
  GraphResourceOptionsLoader? loader,
) async {
  final fields = schema.fields.isEmpty
      ? schema.fields
      : await Future.wait(
          schema.fields.map(
            (field) => _hydrateResourceInputSchema(field, loader),
          ),
        );
  var options = schema.options;
  if (schema.kind == DartDataInputKind.resource &&
      options.isEmpty &&
      schema.resourceType != null &&
      loader != null) {
    options = await loader(schema.resourceType!);
  }
  return DartDataInputSchema(
    label: schema.label,
    kind: schema.kind,
    key: schema.key,
    options: options,
    required: schema.required,
    secret: schema.secret,
    multiline: schema.multiline,
    defaultValue: schema.defaultValue,
    resourceType: schema.resourceType,
    fields: fields,
    itemKind: schema.itemKind,
  );
}

class _InlineAutomationPanel extends StatelessWidget {
  const _InlineAutomationPanel({
    required this.label,
    required this.editor,
    required this.registryFuture,
  });

  final String label;
  final ShowRunnerGraphEditor editor;
  final Future<DartPluginRegistry> registryFuture;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      leading: const Icon(Icons.account_tree_outlined),
      title: Text(label),
      subtitle: Text('${editor.controller.nodes.length} nodes'),
      children: [
        ShowRunnerInlineGraphEditor(
          editor: editor,
          registryFuture: registryFuture,
        ),
      ],
    ),
  );
}

AutomationData _emptyAutomation() => AutomationData(
  schemaVersion: 2,
  graph: AutomationGraph(nodes: const [], edges: const [], entryNodeId: ''),
);
