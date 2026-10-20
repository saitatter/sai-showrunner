# Flutter plugin layout

Each plugin owns a directory with an explicit contract, runtime, and UI boundary:

```text
plugins/<plugin>/
  <plugin>.dart       public barrel
  manifest.dart       settings, actions, triggers, state
  resources.dart      canonical resource IDs, storage and defaults without Flutter UI
  bootstrap.dart      typed default/configured first-party factory
  runtime.dart        workers and provider services
  ui/                 bespoke Flutter pages
  resources/          plugin resource editors
```

Resource types are registered through `resource_editor_registry.dart`. A
plugin can provide a typed editor builder for its resource type without
coupling the plugin manifest to Flutter widget classes.

Shared plugin infrastructure lives outside the concrete plugin directories:

```text
plugins/registry/   atomic composition contracts, static assembly and Flutter UI assembly
plugins/runtime/    provider event runtime
services/            provider transports, OAuth, validation, and event hub
features/resources/ resource editor registry
```

New plugin code should use its directory barrel and should not add a new
top-level file under `plugins/`.

The composition facade delegates to default/configured registrars, which import
provider factories explicitly. A provider factory resolves its own settings,
accounts and transport; it must not import the application bootstrap. OBS, Aitum
and ADVSS form one pack sharing the OBS connection. Shared settings/OAuth helpers
preserve provider-specific refresh rules. Flutter contributions remain separate
from manifests and module contracts. Source architecture fixtures enforce these
boundaries; generated contract parity protects saved action/trigger/resource IDs.
