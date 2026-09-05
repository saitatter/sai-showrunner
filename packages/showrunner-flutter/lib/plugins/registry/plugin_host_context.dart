/// Dependencies exposed to plugin modules at lifecycle boundaries.
///
/// The registry deliberately does not know concrete service types. Built-in
/// plugins receive their typed dependencies through their factories, while
/// future modules can request an explicitly registered host service by key.
final class DartPluginHostContext {
  const DartPluginHostContext({this.services = const <String, Object?>{}});

  final Map<String, Object?> services;

  T? service<T>(String key) {
    final value = services[key];
    return value is T ? value : null;
  }
}
