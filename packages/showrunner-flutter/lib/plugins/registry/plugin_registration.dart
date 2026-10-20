import 'plugin_contract.dart';
import 'plugin_module.dart';

/// One compile-time factory contribution. Context is a concrete, typed set of
/// ports chosen by the provider; it is never a dynamic service lookup map.
final class FirstPartyPluginContribution<Context> {
  FirstPartyPluginContribution({
    required this.id,
    required this.createModule,
    Iterable<PluginId> dependencies = const [],
    Iterable<PluginId> optionalDependencies = const [],
    this.contractVersion = 1,
  }) : dependencies = Set.unmodifiable(dependencies),
       optionalDependencies = Set.unmodifiable(optionalDependencies);

  final PluginId id;
  final DartPluginModule Function(Context context) createModule;
  final Set<PluginId> dependencies;
  final Set<PluginId> optionalDependencies;
  final int contractVersion;

  /// The composing caller owns constructed resources until registration succeeds.
  PluginModuleRegistration create(Context context) => PluginModuleRegistration(
    id: id,
    module: createModule(context),
    dependencies: dependencies,
    optionalDependencies: optionalDependencies,
    contractVersion: contractVersion,
  );
}

/// Runtime contracts have no Flutter UI import. UI/editor assembly supplies
/// editor type IDs separately when validating the complete first-party pack.
final class PluginModuleRegistration {
  PluginModuleRegistration({
    required this.id,
    required this.module,
    Iterable<PluginId> dependencies = const [],
    Iterable<PluginId> optionalDependencies = const [],
    this.contractVersion = 1,
  }) : dependencies = Set.unmodifiable(dependencies),
       optionalDependencies = Set.unmodifiable(optionalDependencies);

  final PluginId id;
  final DartPluginModule module;
  final Set<PluginId> dependencies;
  final Set<PluginId> optionalDependencies;
  final int contractVersion;
}

/// Stable dependency ordering: independent modules retain declaration order.
/// All validation precedes registry mutation or lifecycle callbacks.
List<PluginModuleRegistration> orderPluginRegistrations(
  Iterable<PluginModuleRegistration> registrations,
) {
  final entries = <PluginId, PluginModuleRegistration>{};
  for (final entry in registrations) {
    if (entry.id.value.trim().isEmpty) {
      throw ArgumentError.value(entry.id, 'plugin.id');
    }
    if (entries.containsKey(entry.id)) {
      throw ArgumentError('Plugin is registered more than once: ${entry.id}');
    }
    if (entry.module.manifest.id != entry.id) {
      throw ArgumentError(
        'Factory ${entry.id} returned ${entry.module.manifest.id}.',
      );
    }
    if (entry.contractVersion != 1) {
      throw ArgumentError(
        'Unsupported plugin contract version: ${entry.contractVersion}.',
      );
    }
    entries[entry.id] = entry;
  }
  final ordered = <PluginModuleRegistration>[];
  final visited = <PluginId>{};
  final visiting = <PluginId>[];
  void visit(PluginId id) {
    if (visited.contains(id)) return;
    if (visiting.contains(id)) {
      throw ArgumentError(
        'Plugin dependency cycle: ${[...visiting, id].map((id) => id.value).join(' -> ')}',
      );
    }
    final entry = entries[id]!;
    visiting.add(id);
    for (final dependency in entry.dependencies) {
      if (!entries.containsKey(dependency)) {
        throw ArgumentError('Plugin $id requires missing plugin $dependency.');
      }
      visit(dependency);
    }
    for (final dependency in entry.optionalDependencies) {
      if (entries.containsKey(dependency)) visit(dependency);
    }
    visiting.removeLast();
    visited.add(id);
    ordered.add(entry);
  }

  for (final id in entries.keys) {
    visit(id);
  }
  return List.unmodifiable(ordered);
}
