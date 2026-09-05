import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const packageDirectory = fileURLToPath(
  new URL('../../../packages/showrunner-flutter/', import.meta.url),
);
const temporaryDirectory = mkdtempSync(join(tmpdir(), 'showrunner-flutter-contracts-'));
const outputPath = join(temporaryDirectory, 'flutter.json');

try {
  execFileSync(
    process.platform === 'win32' ? 'flutter.bat' : 'flutter',
    ['test', 'tool/contract_snapshot_test.dart', '--no-pub'],
    {
      cwd: packageDirectory,
      encoding: 'utf8',
      env: { ...process.env, SHOWRUNNER_PARITY_OUTPUT: outputPath },
      shell: process.platform === 'win32',
    },
  );

  process.stdout.write(readFileSync(outputPath, 'utf8'));
} finally {
  rmSync(temporaryDirectory, { recursive: true, force: true });
}
