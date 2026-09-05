import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const temporaryDirectory = mkdtempSync(join(tmpdir(), 'showrunner-parity-'));
const mainPath = join(temporaryDirectory, 'main.json');
const flutterPath = join(temporaryDirectory, 'flutter.json');
const reportPath = join(root, 'docs', 'parity.json');

try {
  const main = execFileSync(
    process.execPath,
    [join(root, 'tools/parity/extract-main-contracts/index.mjs'), '--ref', 'main'],
    { cwd: root, encoding: 'utf8' },
  );
  const flutter = execFileSync(
    process.execPath,
    [join(root, 'tools/parity/extract-flutter-contracts/index.mjs')],
    { cwd: root, encoding: 'utf8' },
  );
  writeFileSync(mainPath, main);
  writeFileSync(flutterPath, flutter);
  const report = execFileSync(
    process.execPath,
    [
      join(root, 'tools/parity/diff-contracts/index.mjs'),
      '--main',
      mainPath,
      '--flutter',
      flutterPath,
    ],
    { cwd: root, encoding: 'utf8' },
  );
  writeFileSync(reportPath, report);
  const parsed = JSON.parse(report);
  const counts = parsed.plugins.reduce((summary, plugin) => {
    summary[plugin.status] = (summary[plugin.status] || 0) + 1;
    return summary;
  }, {});
  process.stdout.write(`Parity report written to docs/parity.json (${JSON.stringify(counts)})\n`);
} finally {
  rmSync(temporaryDirectory, { recursive: true, force: true });
}
