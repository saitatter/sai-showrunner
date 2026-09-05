# Contract parity checks

The parity check compares the frozen `main` plugin surface with the Flutter
registry. It reports IDs for settings, actions, triggers, states, resources,
and workspace contributions; it does not infer runtime equivalence from a
folder name.

The reference is frozen at the local tag
`migration-reference/main-2026-09-05`; update that tag deliberately when a new
product baseline is approved.

Run from the repository root:

```powershell
corepack yarn parity:check
```

The generated report is `docs/parity.json`. Temporary extraction files are
created outside the repository and removed after the report is written.

The `main` extractor is deliberately conservative: dynamic or computed IDs
are omitted instead of being guessed. Such omissions remain visible in the
report and require an explicit contract test in Flutter.
