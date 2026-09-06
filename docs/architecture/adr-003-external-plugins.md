# ADR-003: Defer third-party plugin loading until after replacement parity

Status: accepted

## Context

`main` contains `plugin-template` and `plugin-native-template` repositories for
authoring integrations. They are scaffolding projects, not runtime features
used by the desktop product. The Flutter replacement currently contains the
first-party integrations as built-in Dart modules with typed manifests,
settings, resources, actions, triggers and health boundaries.

Loading arbitrary third-party code inside the desktop process would create a
new crash, security and version-compatibility boundary before first-party
replacement parity is closed.

## Decision

Do not port the template projects or add an in-process third-party plugin SDK
to the replacement candidate. First-party parity and release hardening take
priority.

If external plugins become a product requirement, the follow-up design is an
out-of-process, versioned protocol with manifest, action, trigger, state,
resource, health and shutdown messages. The host process remains responsible
for lifecycle ownership and failure isolation.

## Consequences

- Existing built-in integrations remain supported and parity-checked.
- The template projects remain reference scaffolding, not Flutter runtime
  dependencies.
- No arbitrary Dart, JavaScript, Python or native code is loaded into the
  desktop process.
- An external plugin SDK is explicitly post-parity work and must have a
  versioned protocol and security review before implementation.

## Rejected alternative

Embedding third-party plugin code directly into the Flutter process would
duplicate the old runtime coupling and make failures difficult to isolate.
