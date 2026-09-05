# ADR-001: Keep Remote as a Versioned Agent Boundary

Status: accepted

## Decision

The remote/satellite capability remains available as a separate agent boundary.
The Flutter desktop application owns the local plugin runtime and exposes the
remote dashboard/resource protocol through the existing versioned connection
layer. Remote clients do not load Flutter widgets or the desktop plugin graph
inside their process.

## Consequences

- The `remote` plugin remains a supported product capability.
- The desktop and remote client communicate through explicit connection and
  resource contracts.
- Remote widget kinds without a Flutter renderer remain visible as an explicit
  placeholder instead of being silently dropped.
- A future standalone agent can be extracted behind the same protocol without
  duplicating the desktop runtime.

## Rejected alternative

Removing remote support would break dashboard and remote-resource workflows,
so it is not a valid cleanup operation for the Flutter cutover.
