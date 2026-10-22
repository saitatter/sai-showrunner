import '../../persistence/document_revision.dart';
import '../../graph/domain/automation_document.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../components/data_inputs/data_input.dart';
import '../../app/name_dialog.dart';
import '../../graph/controller/automation_editor_controller.dart';
import '../../graph/domain/automation_factories.dart';
import 'profile_inline_automation_panel.dart';
import 'profile_trigger_picker.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';

import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/registry/plugin_bootstrap.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../runtime/profile_runtime.dart';
import '../../schema/json.dart';
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
  late final AutomationEditorController _activationEditor;
  late final AutomationEditorController _deactivationEditor;
  late Future<DartPluginRegistry> _triggerRegistryFuture;
  late Future<List<String>> _queueOptionsFuture;
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
  bool _ownsProfileActivation = false;
  Object? _error;
  bool _profileDirty = false;
  bool _synchronizing = false;
  late Future<void> _initialLoad;
  Object _selectionOwner = Object();
  Object _loadOwner = Object();
  String? _selectedFileName;
  bool _isCurrent(Object owner) => mounted && identical(owner, _selectionOwner);

  @override
  void didUpdateWidget(covariant ProfileWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(
        _confirmClose,
        openProfile: _openProfile,
        reloadEntries: _load,
      );
    }
    if (!identical(oldWidget.dataService, widget.dataService) ||
        oldWidget.registryFuture != widget.registryFuture) {
      _selectionOwner = Object();
      _selectedFileName = null;
      _selectedIndex = null;
      _saving = false;
      _profileActive = false;
      _ownsProfileActivation = false;
      _triggerRegistry = null;
      _triggerRegistryFuture =
          widget.registryFuture ?? Future.value(createDefaultPluginRegistry());
      _queueOptionsFuture = _resourceOptions('ActionQueue');
      _initialLoad = _load();
      unawaited(_loadTriggerRegistry());
    }
  }

  @override
  void initState() {
    super.initState();
    _activationEditor = AutomationEditorController(
      document: AutomationDocument.empty(),
    );
    _deactivationEditor = AutomationEditorController(
      document: AutomationDocument.empty(),
    );
    _triggerRegistryFuture =
        widget.registryFuture ?? Future.value(createDefaultPluginRegistry());
    _queueOptionsFuture = _resourceOptions('ActionQueue');
    _nameController.addListener(_markDirty);
    _activationEditor.graph.addDocumentListener(_graphChanged);
    _deactivationEditor.graph.addDocumentListener(_graphChanged);
    _initialLoad = _load();
    unawaited(_loadTriggerRegistry());
    widget.controller?.attach(
      _confirmClose,
      openProfile: _openProfile,
      reloadEntries: _load,
    );
  }

  Future<void> _loadTriggerRegistry() async {
    final future = _triggerRegistryFuture;
    try {
      final registry = await future;
      if (mounted && identical(future, _triggerRegistryFuture)) {
        _activationEditor.bindRegistry(registry);
        _deactivationEditor.bindRegistry(registry);
        setState(() => _triggerRegistry = registry);
      }
    } catch (error) {
      if (mounted && identical(future, _triggerRegistryFuture)) {
        setState(() => _error = error);
      }
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _nameController.removeListener(_markDirty);
    _activationEditor.graph.removeDocumentListener(_graphChanged);
    _deactivationEditor.graph.removeDocumentListener(_graphChanged);
    _nameController.dispose();
    _activationEditor.dispose();
    _deactivationEditor.dispose();
    super.dispose();
  }

  void _graphChanged(GraphDocumentChange change) => _markDirty();

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
    if (!mounted) return;
    final owner = _loadOwner = Object();
    final data = widget.dataService;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await data.storage.listProfiles();
      if (!mounted || !identical(owner, _loadOwner)) return;
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
      if (!mounted || !identical(owner, _loadOwner)) return;
      _error = error;
    }
    if (mounted && identical(owner, _loadOwner)) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openProfile(String fileName) async {
    if (_saving) return;
    final data = widget.dataService;
    if (_loading) await _initialLoad;
    if (!mounted || !identical(data, widget.dataService)) return;
    if (!await _confirmClose()) return;
    if (!mounted || !identical(data, widget.dataService)) return;
    final index = _entries.indexWhere((entry) => entry.fileName == fileName);
    if (index < 0) return;
    setState(() => _selectProfile(index));
  }

  void _selectProfile(int index) {
    _synchronizing = true;
    _selectionOwner = Object();
    _saving = false;
    final changed = _selectedFileName != _entries[index].fileName;
    _selectedFileName = _entries[index].fileName;
    _selectedIndex = index;
    if (changed) {
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
      _activationEditor.load(profile.activationAutomation);
      _deactivationEditor.load(profile.deactivationAutomation);
    } else {
      _nameController.text = entry.fileName;
      _activationCondition = createAlwaysOnCondition();
      _activationMode = 'toggle';
      _triggers = [];
      _activationEditor.load(_emptyAutomation());
      _deactivationEditor.load(_emptyAutomation());
    }
    _invalidTriggerIds.clear();
    _synchronizing = false;
    _markClean();
    unawaited(_syncRuntimeActive(entry.fileName));
  }

  Future<void> _syncRuntimeActive(String fileName) async {
    final runtimeFuture = widget.runtimeFuture;
    if (runtimeFuture == null) return;
    final owner = _selectionOwner;
    DartProfileRuntime runtime;
    try {
      runtime = await runtimeFuture;
    } catch (_) {
      if (_isCurrent(owner)) {
        setState(() => _error = 'Profile runtime is unavailable.');
      }
      return;
    }
    if (!_isCurrent(owner) ||
        _selectedIndex == null ||
        _selectedIndex! >= _entries.length ||
        _entries[_selectedIndex!].fileName != fileName) {
      return;
    }
    if (_profileActive != runtime.isActive(fileName)) {
      setState(() => _profileActive = runtime.isActive(fileName));
    }
  }

  Future<bool> _confirmClose() async {
    final owner = _selectionOwner;
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
    if (!_isCurrent(owner) ||
        decision == null ||
        decision == _ProfileCloseDecision.cancel) {
      return false;
    }
    if (decision == _ProfileCloseDecision.save) {
      await _saveProfile();
      if (!_isCurrent(owner) || _profileDirty) return false;
      return _stopCurrentProfile();
    }
    _markClean();
    return _stopCurrentProfile();
  }

  Future<bool> _stopCurrentProfile() async {
    if (!_ownsProfileActivation || _selectedIndex == null) {
      _profileActive = false;
      _ownsProfileActivation = false;
      return true;
    }
    final owner = _selectionOwner;
    final providerEvents = widget.providerEvents;
    final entry = _entries[_selectedIndex!];
    try {
      final runtime = widget.runtimeFuture == null
          ? null
          : await widget.runtimeFuture;
      if (!_isCurrent(owner)) return false;
      if (runtime != null && entry.profile != null) {
        await runtime.setManagedActive(
          entry.fileName,
          entry.profile!,
          active: false,
        );
      }
      providerEvents.updateProfileActivity(entry.fileName, active: false);
      if (!_isCurrent(owner)) return false;
      _profileActive = false;
      _ownsProfileActivation = false;
      return true;
    } catch (error) {
      if (!_isCurrent(owner)) return false;
      _error = error;
      if (mounted) setState(() {});
      return false;
    }
  }

  Future<void> _createProfile() async {
    if (!await _confirmClose()) return;
    if (!mounted) return;
    final owner = _selectionOwner;
    final data = widget.dataService;
    final name = await showShowRunnerNameDialog(
      context,
      title: 'New profile',
      initialName: 'New Profile',
    );
    if (name == null || !_isCurrent(owner)) return;
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
    final repo = data.storage.profile(fileName);
    await repo.save(profile, requireAbsent: true);
    if (!_isCurrent(owner)) return;
    await _load();
    final index = _entries.indexWhere((entry) => entry.fileName == fileName);
    if (index != -1 && mounted) {
      setState(() => _selectProfile(index));
    }
    widget.onEntriesChanged?.call();
  }

  ShowRunnerProfile _draft(ShowRunnerProfile? original) => ShowRunnerProfile(
    name: _nameController.text.trim(),
    activationMode: _activationMode,
    triggers: [
      for (final trigger in _triggers)
        Map<String, dynamic>.from(jsonDecode(jsonEncode(trigger)) as Map),
    ],
    activationCondition: Map<String, dynamic>.from(
      jsonDecode(jsonEncode(_activationCondition)) as Map,
    ),
    activationAutomation: _activationEditor.document,
    deactivationAutomation: _deactivationEditor.document,
    extra: original?.extra ?? const {},
  );

  Future<void> _saveProfile() async {
    if (_saving ||
        _selectedIndex == null ||
        _selectedIndex! >= _entries.length) {
      return;
    }
    final owner = _selectionOwner;
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
      final updated = _draft(original);
      final repo = widget.dataService.storage.profile(entry.fileName);
      await repo.save(
        updated,
        expectedRevision: original == null
            ? null
            : DocumentRevision.of(original.toJson()),
      );
      if (!_isCurrent(owner)) return;
      _entries[_selectedIndex!] = (
        fileName: entry.fileName,
        profile: updated,
        error: null,
      );
      if (DocumentRevision.of(_draft(original).toJson()) ==
          DocumentRevision.of(updated.toJson())) {
        _markClean();
      }
      widget.onEntriesChanged?.call();
    } catch (error) {
      if (_isCurrent(owner)) _error = error;
    }
    if (_isCurrent(owner)) setState(() => _saving = false);
  }

  Future<void> _toggleProfile() async {
    final index = _selectedIndex;
    if (_saving || index == null || index >= _entries.length) return;
    final entry = _entries[index];
    final profile = entry.profile;
    final runtimeFuture = widget.runtimeFuture;
    if (profile == null || runtimeFuture == null) return;
    final owner = _selectionOwner;
    final providerEvents = widget.providerEvents;
    final active = !_profileActive;
    setState(() => _saving = true);
    try {
      final runtime = await runtimeFuture;
      if (!_isCurrent(owner)) return;
      await runtime.setManagedActive(entry.fileName, profile, active: active);
      providerEvents.updateProfileActivity(
        entry.fileName,
        active: active,
        triggers: active ? profile.triggers : const [],
      );
      if (!_isCurrent(owner)) return;
      _ownsProfileActivation = active;
      setState(() => _profileActive = active);
    } catch (error) {
      if (_isCurrent(owner)) setState(() => _error = error);
    } finally {
      if (_isCurrent(owner)) setState(() => _saving = false);
    }
  }

  Future<void> _deleteProfile(String fileName) async {
    if (_saving) return;
    final owner = _selectionOwner;
    final data = widget.dataService;
    if (_selectedIndex != null &&
        _selectedIndex! < _entries.length &&
        _entries[_selectedIndex!].fileName == fileName &&
        !await _confirmClose()) {
      return;
    }
    if (!_isCurrent(owner)) return;
    final entry = _entries
        .where((entry) => entry.fileName == fileName)
        .firstOrNull;
    final original = entry?.profile;
    if (original == null) {
      throw StateError('Cannot delete an unreadable profile.');
    }
    await data.storage
        .profile(fileName)
        .delete(expectedRevision: DocumentRevision.of(original.toJson()));
    if (!_isCurrent(owner)) return;
    _selectedIndex = null;
    _markClean();
    await _load();
    widget.onEntriesChanged?.call();
  }

  Future<void> _addTrigger() async {
    final owner = _selectionOwner;
    DartPluginRegistry registry;
    try {
      registry = await _triggerRegistryFuture;
    } on Object {
      if (_isCurrent(owner)) {
        setState(() => _error = 'Trigger catalog is unavailable.');
      }
      return;
    }
    if (!mounted || !_isCurrent(owner)) return;
    final selected = await showDialog<TriggerSpec>(
      context: context,
      builder: (context) => ProfileTriggerPickerDialog(registry: registry),
    );
    if (selected == null || !_isCurrent(owner)) return;
    final initialConfig = selected.configSchema == null
        ? <String, dynamic>{}
        : constructDartDataInputDefault(selected.configSchema!);
    final config = initialConfig is Map
        ? Map<String, dynamic>.from(initialConfig)
        : <String, dynamic>{};
    setState(() {
      _triggers.add({
        'id': 'trigger_${DateTime.now().microsecondsSinceEpoch}',
        'description': selected.displayName,
        'automation': createEventAutomation(
          plugin: selected.pluginId.value,
          trigger: selected.triggerId.value,
          config: config,
        ).toJson(),
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

    if (selectedEntry == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.card_membership_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('No profiles yet'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final create = widget.onCreate;
                if (create != null) {
                  await create();
                } else {
                  await _createProfile();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Profile'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Edit Profile${_profileDirty ? ' *' : ''}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: _saving
                    ? null
                    : () => _deleteProfile(selectedEntry.fileName),
                tooltip: 'Delete Profile',
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _saving || widget.runtimeFuture == null
                    ? null
                    : _toggleProfile,
                icon: Icon(_profileActive ? Icons.stop : Icons.play_arrow),
                label: Text(_profileActive ? 'Deactivate' : 'Activate'),
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save Profile'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Profile operation failed. Check the configuration and retry.',
              style: TextStyle(color: Colors.red),
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
              DropdownMenuItem(value: 'toggle', child: Text('Toggle')),
              DropdownMenuItem(value: 'manual', child: Text('Manual')),
              DropdownMenuItem(value: 'automation', child: Text('Automation')),
              DropdownMenuItem(value: 'always', child: Text('Always Active')),
            ],
            onChanged: (value) {
              setState(() => _activationMode = value ?? 'toggle');
              _markDirty();
            },
          ),
          const SizedBox(height: 28),
          Text('Triggers', style: Theme.of(context).textTheme.headlineSmall),
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
                      style: Theme.of(context).textTheme.titleMedium,
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
                  final id = trigger['id']?.toString() ?? 'trigger-$index';
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
          Text('Activation', style: Theme.of(context).textTheme.headlineSmall),
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
          ProfileInlineAutomationPanel(
            label: 'On Activate',
            editor: _activationEditor,
            registryFuture:
                widget.registryFuture ?? Future.value(DartPluginRegistry()),
          ),
          const SizedBox(height: 12),
          ProfileInlineAutomationPanel(
            label: 'On Deactivate',
            editor: _deactivationEditor,
            registryFuture:
                widget.registryFuture ?? Future.value(DartPluginRegistry()),
          ),
        ],
      ),
    );
  }
}

AutomationDocument _emptyAutomation() => AutomationDocument.empty();
