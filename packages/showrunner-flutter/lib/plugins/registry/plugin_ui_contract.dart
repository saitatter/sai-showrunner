/// UI contribution contract kept separate from the plugin manifest.
///
/// The contract uses opaque values so the manifest layer remains Flutter-free.
/// The Flutter adapter validates and converts these values at the UI boundary.
abstract interface class DartPluginUiContribution {
  Object build({
    required Object context,
    required Object dataService,
    required Object providerEvents,
    required Object registryFuture,
  });
}
