/// Stable identifiers used at plugin contract boundaries.
///
/// Manifest factories expose string IDs at the plugin boundary. Registry
/// lookups use these value objects so an action or trigger cannot accidentally
/// be addressed by an unrelated concatenated string.
sealed class _ContractId {
  const _ContractId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is _ContractId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

final class PluginId extends _ContractId {
  const PluginId(super.value);
}

final class ActionId extends _ContractId {
  const ActionId(super.value);
}

final class TriggerId extends _ContractId {
  const TriggerId(super.value);
}

final class SettingId extends _ContractId {
  const SettingId(super.value);
}

final class StateId extends _ContractId {
  const StateId(super.value);
}

final class ResourceTypeId extends _ContractId {
  const ResourceTypeId(super.value);
}

final class ActionKey {
  const ActionKey({required this.plugin, required this.action});

  final PluginId plugin;
  final ActionId action;

  @override
  bool operator ==(Object other) =>
      other is ActionKey && other.plugin == plugin && other.action == action;

  @override
  int get hashCode => Object.hash(plugin, action);

  @override
  String toString() => '$plugin:$action';
}

final class TriggerKey {
  const TriggerKey({required this.plugin, required this.trigger});

  final PluginId plugin;
  final TriggerId trigger;

  @override
  bool operator ==(Object other) =>
      other is TriggerKey && other.plugin == plugin && other.trigger == trigger;

  @override
  int get hashCode => Object.hash(plugin, trigger);

  @override
  String toString() => '$plugin:$trigger';
}
