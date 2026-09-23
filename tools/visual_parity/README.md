# Full-screen visual parity

The comparator is dependency-free and runs on Node.js. It compares two PNG
captures, checks their dimensions, writes a red-on-grayscale diff image, and
can persist a machine-readable report.

Example:

```powershell
node tools/visual_parity/compare.mjs `
  --reference=test/reference/main/app-empty.png `
  --actual=test/reference/flutter/app-empty.png `
  --diff=.tmp/visual/app-empty.diff.png `
  --report=.tmp/visual/app-empty.json `
  --channel-threshold=2 `
  --max-difference=0.05
```

The default threshold is strict (`0` channel difference and `0%` differing
pixels). Any allowance for font rasterization or native chrome must be passed
explicitly and recorded with the report.

Reference captures use the deterministic fixture and window contract below:

```text
1440x900
100% scaling
Inter variable font
same selected workspace and fixture content
```

The Flutter capture harness is run with:

```powershell
corepack yarn visual:flutter
```

It writes captures to `test/reference/flutter/` by default. CI captures the
current Windows build into `.tmp/visual/flutter/` and compares those files
against the frozen `main` references:

```powershell
.\scripts\capture-flutter-visual.ps1 -OutputDirectory '.tmp/visual/flutter'
corepack yarn visual:compare:catalog --actual-root=.tmp/visual/flutter
```

The report and difference images are uploaded as the `visual-parity-Windows`
CI artifact. Until each screen has a reviewed, matching fixture and an explicit
acceptance threshold, CI treats the comparison as evidence only: a passing
capture does not mean pixel parity. Use `--fail-above=<percent>` only for
screens whose fixture and intentional visual differences have been reviewed.
