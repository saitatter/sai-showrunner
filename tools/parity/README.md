# Contract parity checks

The parity check compares the frozen `main` plugin surface with the Flutter
registry. It includes the built-in `ShowRunner` contract as well as external
plugins and reports IDs for settings, actions, triggers, states, resources,
and workspace contributions; it does not infer runtime equivalence from a
folder name.

The reference is frozen at commit
`890ee2c9cc0522f2d8c747612920c6d12a1cb716`, the historical Electron main.
Use a full-history checkout (`fetch-depth: 0` in GitHub Actions). The check does
not depend on local-only tags or the changing main branch. Change the pinned
commit deliberately only when a new product baseline is approved.

Run from the repository root:

```powershell
corepack yarn parity:check
```

The generated report is `docs/parity.json`. Temporary extraction files are
created outside the repository and removed after the report is written.

The `main` extractor is deliberately conservative: dynamic or computed IDs
are omitted instead of being guessed. Such omissions remain visible in the
report and require an explicit contract test in Flutter. Renderer source files
are also catalogued so a contract match cannot be mistaken for visual parity.
