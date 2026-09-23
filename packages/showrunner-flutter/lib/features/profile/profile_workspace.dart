import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../components/data_inputs/data_input.dart';
import '../../app/name_dialog.dart';
import '../../editor/showrunner_graph_editor.dart';
import '../graph/graph_workspace.dart';
import '../../persistence/profile_repository.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/registry/plugin_bootstrap.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../runtime/profile_runtime.dart';
import '../../schema/automation.dart';
import '../../schema/profile.dart';
import '../../services/showrunner_data_service.dart';
import '../resources/resource_options.dart';
import 'boolean_expression_editor.dart';
import 'profile_trigger_editor_card.dart';

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
  Future<void> Function()? _reloadEntries;
  String? _pendingProfile;
  String? _activeProfileFile;

  String? get activeProfileFile => _activeProfileFile;

  void attach(
    Future<bool> Function() closeGuard, {
    Future<void> Function(String fileName)? openProfile,
    Future<void> Function()? reloadEntries,
  }) {
    _closeGuard = closeGuard;
    _openProfile = openProfile;
    _reloadEntries = reloadEntries;
    final pendingProfile = _pendingProfile;
    if (pendingProfile != null && openProfile != null) {
      _pendingProfile = null;
      unawaited(openProfile(pendingProfile));
    }
  }

  void detach() {
    _closeGuard = null;
    _openProfile = null;
    _reloadEntries = null;
    _activeProfileFile = null;
  }

  Future<bool> confirmClose() => _closeGuard?.call() ?? Future.value(true);

  Future<void> reloadEntries() async {
    await _reloadEntries?.call();
  }

  void setActiveProfileFile(String? fileName) {
    _activeProfileFile = fileName;
  }

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
    this.onCreate,
  });

  final ShowRunnerDataService dataService;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry>? registryFuture;
  final Future<DartProfileRuntime>? runtimeFuture;
  final ProfileWorkspaceController? controller;
  final ValueChanged<bool>? onDirtyChanged;
  final VoidCallback? onEntriesChanged;
  final FutureOr<void> Function()? onCreate;

  @override
  State<ProfileWorkspace> createState() => _ProfileWorkspaceState();
}

class _ProfileWorkspaceState extends State<ProfileWorkspace> {
  final _nameController = TextEditingController();
  late final ShowRunnerGraphEditor _activationEditor;
  late final ShowRunnerGraphEditor _deactivationEditor;
  late final Future<DartPluginRegistry> _triggerRegistryFuture;
  late final Future<List<String>> _queueOptionsFuture;
  DartPluginRegistry? _triggerRegistry;
  List<ProfileEntry> _entries = [];
  int? _selectedIndex;
  String _activationMode = 'toggle';
  List<JsonMap> _triggers = [];
  final Set<String> _invalidTriggerIds = {};
  JsonMap _activationCondition = createAlwaysOnCondition();
  bool _loading = true;
  bool _saving = false;
  bool _profileActive = false;
  DartProfileSession? _profileSession;
  bool _ownsProfileActivation = false;
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
    _triggerRegistryFuture =
        widget.registryFuture ?? Future.value(createDefaultPluginRegistry());
    _queueOptionsFuture = _resourceOptions('ActionQueue');
    _nameController.addListener(_markDirty);
    _activationEditor.documentDirty.addListener(_markDirty);
    _deactivationEditor.documentDirty.addListener(_markDirty);
    _initialLoad = _load();
    unawaited(_loadTriggerRegistry());
    widget.controller?.attach(
      _confirmClose,
      openProfile: _openProfile,
      reloadEntries: _load,
    );
  }

  Future<void> _loadTriggerRegistry() async {
    try {
      final registry = await _triggerRegistryFuture;
      if (mounted) setState(() => _triggerRegistry = registry);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _nameController.removeListener(_markDirty);
    _activationEditor.documentDirty.removeListener(_markDirty);
    _deactivationEditor.documentDirty.removeListener(_markDirty);
    _nameController.dispose();
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
      if (_entries.isEmpty) widget.controller?.setActiveProfileFile(null);
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
      _ownsProfileActivation = false;
    }
    final entry = _entries[index];
    widget.controller?.setActiveProfileFile(entry.fileName);
    final profile = entry.profile;
    if (profile != null) {
      _nameController.text = profile.name;
      _activationCondition = normalizeActivationCondition(
        profile.activationCondition,
      );
      _activationMode = profile.activationMode;
      _triggers = profile.triggers
          .map((trigger) => Map<String, dynamic>.from(trigger))
          .toList();
      _activationEditor.loadAutomation(profile.activationAutomation);
      _deactivationEditor.loadAutomation(profile.deactivationAutomation);
    } else {
      _nameController.text = entry.fileName;
      _activationCondition = createAlwaysOnCondition();
      _activationMode = 'toggle';
      _triggers = [];
      _activationEditor.loadAutomation(_emptyAutomation());
      _deactivationEditor.loadAutomation(_emptyAutomation());
    }
    _invalidTriggerIds.clear();
    _synchronizing = false;
    _markClean();
    unawaited(_syncRuntimeActive(entry.fileName));
  }

  Future<void> _syncRuntimeActive(String fileName) async {
    final runtimeFuture = widget.runtimeFuture;
    if (runtimeFuture == null) return;
    final runtime = await runtimeFuture;
    if (!mounted ||
        _selectedIndex == null ||
        _selectedIndex! >= _entries.length ||
        _entries[_selectedIndex!].fileName != fileName) {
      return;
    }
    if (_profileActive != runtime.isActive(fileName)) {
      setState(() => _profileActive = runtime.isActive(fileName));
    }
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
    if (!_ownsProfileActivation || _selectedIndex == null) {
      await _profileSession?.dispose();
      _profileSession = null;
      _profileActive = false;
      _ownsProfileActivation = false;
      return true;
    }
    final entry = _entries[_selectedIndex!];
    try {
      final runtime = widget.runtimeFuture == null
          ? null
          : await widget.runtimeFuture;
      await _profileSession?.dispose();
      _profileSession = null;
      if (runtime != null && entry.profile != null) {
        await runtime.setManagedActive(
          entry.fileName,
          entry.profile!,
          active: false,
        );
      }
      widget.providerEvents.updateProfileActivity(
        entry.fileName,
        active: false,
      );
      _profileActive = false;
      _ownsProfileActivation = false;
      return true;
    } catch (error) {
      _error = error;
      if (mounted) setState(() {});
      return false;
    }
  }

  Future<void> _createProfile() async {
    if (!await _confirmClose()) return;
    if (!mounted) return;
    final name = await showShowRunnerNameDialog(
      context,
      title: 'New profile',
      initialName: 'New Profile',
    );
    if (name == null || !mounted) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'profile_$timestamp.yaml';
    final profile = ShowRunnerProfile(
      name: name,
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
    if (_invalidTriggerIds.isNotEmpty) {
      setState(
        () => _error = 'Fix invalid trigger configuration before saving.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final entry = _entries[_selectedIndex!];
      final original = entry.profile;
      final updated = ShowRunnerProfile(
        name: _nameController.text.trim(),
        activationMode: _activationMode,
        triggers: _triggers,
        activationCondition: _activationCondition,
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
      final active = !_profileActive;
      await runtime.setManagedActive(entry.fileName, profile, active: active);
      widget.providerEvents.updateProfileActivity(
        entry.fileName,
        active: active,
        triggers: active ? profile.triggers : const [],
      );
      _ownsProfileActivation = true;
      if (mounted) setState(() => _profileActive = active);
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
    final registry = await _triggerRegistryFuture;
    if (!mounted) return;
    final selected = await showDialog<TriggerSpec>(
      context: context,
      builder: (context) => _TriggerPickerDialog(registry: registry),
    );
    if (selected == null || !mounted) return;
    final initialConfig = selected.configSchema == null
        ? <String, dynamic>{}
        : constructDartDataInputDefault(selected.configSchema!);
    final config = initialConfig is Map
        ? Map<String, dynamic>.from(initialConfig)
        : <String, dynamic>{};
    setState(() {
      _triggers.add({
        'id': 'trigger_${DateTime.now().microsecondsSinceEpoch}',
        'plugin': selected.pluginId.value,
        'trigger': selected.triggerId.value,
        'config': config,
        'description': selected.displayName,
        'automation': _emptyAutomation().toJson(),
      });
      _markDirty();
    });
  }

  Future<List<String>> _resourceOptions(String resourceType) async {
    return loadResourceOptions(widget.dataService, resourceType);
  }

  void _removeTrigger(int index) {
    final id = _triggers[index]['id']?.toString();
    setState(() {
      _triggers.removeAt(index);
      if (id != null) _invalidTriggerIds.remove(id);
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
                    onPressed: widget.onCreate ?? _createProfile,
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
                            onPressed: _saving || _invalidTriggerIds.isNotEmpty
                                ? null
                                : _saveProfile,
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
                      const SizedBox(height: 28),
                      Text(
                        'Triggers',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      if (_triggers.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'Triggers are how ShowRunner responds to events.',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _addTrigger,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Trigger'),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _addTrigger,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Trigger'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_triggerRegistry == null)
                          const LinearProgressIndicator()
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: _triggers.length,
                            onReorderItem: (oldIndex, newIndex) {
                              setState(() {
                                final item = _triggers.removeAt(oldIndex);
                                _triggers.insert(newIndex, item);
                              });
                              _markDirty();
                            },
                            itemBuilder: (context, index) {
                              final trigger = _triggers[index];
                              final id =
                                  trigger['id']?.toString() ?? 'trigger-$index';
                              return ProfileTriggerEditorCard(
                                key: ValueKey(id),
                                trigger: trigger,
                                registry: _triggerRegistry!,
                                registryFuture: _triggerRegistryFuture,
                                resourceOptionsLoader: _resourceOptions,
                                queueOptionsFuture: _queueOptionsFuture,
                                dragHandle: ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(Icons.drag_indicator),
                                ),
                                onChanged: (updated) {
                                  _triggers[index] = updated;
                                  _markDirty();
                                },
                                onValidityChanged: (valid) {
                                  final changed = valid
                                      ? _invalidTriggerIds.remove(id)
                                      : _invalidTriggerIds.add(id);
                                  if (changed && mounted) setState(() {});
                                },
                                onDelete: () => _removeTrigger(index),
                              );
                            },
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _addTrigger,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Trigger'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      Text(
                        'Activation',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      BooleanExpressionEditor(
                        value: _activationCondition,
                        registryFuture: widget.registryFuture,
                        onChanged: (condition) {
                          setState(() => _activationCondition = condition);
                          _markDirty();
                        },
                      ),
                      const SizedBox(height: 16),
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
                    ],
                  ),
                ),
        ),
      ],
    );
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
