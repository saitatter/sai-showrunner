import 'dart:collection';

/// Deterministic slot allocation and aliases for one compilation.
final class CompilerSlots {
  final Map<String, int> _bindings = {};
  Map<String, int> get bindings => UnmodifiableMapView(_bindings);
  final Map<String, int> _aliases = {};
  int _count = 0;
  int get count => _count;

  void reset() {
    _bindings.clear();
    _aliases.clear();
    _count = 0;
  }

  int allocate(String key) {
    final existing = _bindings[key];
    if (existing != null) return existing;
    final slot = _count++;
    _bindings[key] = slot;
    _aliases[key] = slot;
    return slot;
  }

  void bind(String name, int slot) {
    _bindings[name] = slot;
    _aliases[name] = slot;
  }

  List<String> get names {
    final names = List<String>.filled(_count, '');
    for (final entry in [..._aliases.entries, ..._bindings.entries]) {
      final current = names[entry.value];
      if (current.isEmpty || current.contains(':')) {
        names[entry.value] = entry.key;
      }
    }
    return names;
  }
}
