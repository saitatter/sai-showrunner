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

It writes captures to `test/reference/flutter/`. The `main` captures are kept
separately because they must be produced from the frozen reference build. Once
both sides exist, compare a pair with `corepack yarn visual:compare`.
