# Full-screen visual parity

The comparator is dependency-free and runs on Node.js. It compares two PNG
captures, checks their dimensions, writes a red-on-grayscale diff image, and
can persist a machine-readable report.

Pixel comparison uses scalar RGBA deltas to avoid per-pixel allocations. The
RGBA regression test checks alpha differences, strict threshold boundaries and
exact diff pixels. The optimization was checked against the complete catalog:
all reports and 29 generated artifact hashes matched the previous comparator;
a local Node 22 run decreased from about 2.04 seconds to 1.53 seconds. Timings
vary by host; CI timeouts and image tolerances are unchanged.

Example:

```powershell
node tools/visual_parity/compare.mjs `
  --reference=test/reference/main/app-empty.png `
  --actual=test/reference/flutter/app-empty.png `
  --region=240,80,1200,820 `
  --diff=.tmp/visual/app-empty.diff.png `
  --report=.tmp/visual/app-empty.json `
  --channel-threshold=2 `
  --max-difference=0.05
```

`--region=x,y,width,height` optionally compares a bounded part of both
captures. The catalog can define a `diagnosticRegion` for a screen; catalog
reports then retain the full-screen result and add a second workspace-only
result. This helps separate application-shell differences from the feature
being reviewed; it does not replace the full-screen parity requirement.

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


The selected overlay inspector and font popup have reviewed Flutter baselines
in `test/reference/flutter/reviewed/`. Run `yarn visual:regression --actual-root=<captures>`
to enforce the regions and tolerances in `test/reference/flutter/regression.json`.
Missing captures and regressions fail the command. Baselines are independent of
the old Electron screenshots; framework differences cannot raise the tolerance.
The port-dependent browser URL is outside the tested regions.

Capture only the frozen overlay without replacing historical references:

```powershell
$env:SHOWRUNNER_REFERENCE_OUTPUT = '.tmp/visual/electron'
yarn visual:main --overlay-only
```

The side-by-side inspector review is saved in
`docs/ui-comparison/overlay-inspector.html` with real images and the
Flutter capture taken before the adjustments.
