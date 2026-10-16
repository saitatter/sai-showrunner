import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { spawnSync } from 'node:child_process';
const root = resolve(import.meta.dirname, '../..');
const actualRoot = resolve(root, process.argv.find(a => a.startsWith('--actual-root='))?.split('=').slice(1).join('=') ?? '.tmp/visual/flutter');
const manifest = JSON.parse(readFileSync(join(root, 'test/reference/flutter/regression.json'), 'utf8'));
let failed = false;
const output = join(root, '.tmp/visual/regression');
mkdirSync(output, {recursive: true});
for (const screen of manifest.screens) {
  const baseline = join(root, manifest.baselineRoot, screen.file);
  const actual = join(actualRoot, screen.file);
  if (!existsSync(baseline) || !existsSync(actual)) {
    console.error(`Missing capture for ${screen.file}`); failed = true; continue;
  }
  const args = [join(root, 'tools/visual_parity/compare.mjs'),
    `--reference=${baseline}`, `--actual=${actual}`, `--channel-threshold=${screen.channelThreshold}`,
    `--max-difference=${screen.maxDifference}`, `--report=${join(output, screen.file + '.json')}`,
    `--diff=${join(output, screen.file)}`, ...(screen.region ? [`--region=${screen.region.join(',')}`] : [])];
  const result = spawnSync(process.execPath, args, {stdio: 'inherit'});
  if (result.error || result.status !== 0) failed = true;
}
if (failed) process.exitCode = 1;
