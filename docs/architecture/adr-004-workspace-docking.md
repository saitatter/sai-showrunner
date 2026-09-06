# ADR-004: Keep tabs and a resizable project sidebar for the replacement

Status: accepted

## Context

The current ShowRunner workspace has a persistent project sidebar, resizable
workspace area, document tabs, dirty state, and explicit save/close commands.
The target product does not require an independent docking framework to make
the supported workflows usable, and adding one would create a new interaction
surface that has no stable reference behavior.

## Decision

Keep the replacement workspace model as:

```text
resizable project sidebar
+
document/workspace tabs
+
persistent active document and close/save flow
```

Do not add drag-to-dock panes or arbitrary horizontal/vertical split layouts as
part of replacement readiness. They remain optional post-parity work and must
be proposed as a product change if needed later.

## Consequences

- Workspace navigation has one predictable layout on Windows.
- Document lifecycle behavior remains testable through one tab manager.
- The replacement does not inherit a large docking framework without a proven
  product requirement.
- A future docking implementation must preserve tab order, dirty state,
  keyboard commands, and workspace restoration.

## Rejected alternative

Building a general docking framework now would increase interaction complexity
without evidence that the target product requires it. It would also make visual
parity harder to prove while the core replacement workflow is still being
closed.
