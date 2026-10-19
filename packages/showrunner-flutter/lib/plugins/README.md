# Flutter plugin layout

Each plugin owns a directory with an explicit contract, runtime, and UI boundary:

```text
plugins/<plugin>/
  <plugin>.dart       public barrel
  manifest.dart       settings, actions, triggers, state
  runtime.dart        workers and provider services
  ui/                 bespoke Flutter pages
  resources/          plugin resource editors
```

Resource types are registered through `resource_editor_registry.dart`. A
plugin can provide a typed editor builder for its resource type without
coupling the plugin manifest to Flutter widget classes.

Shared plugin infrastructure lives outside the concrete plugin directories:

```text
plugins/registry/   plugin registry and application bootstrap
plugins/runtime/    provider event runtime
services/            provider transports, OAuth, validation, and event hub
features/resources/ resource editor registry
```

New plugin code should use its directory barrel and should not add a new
top-level file under `plugins/`.
