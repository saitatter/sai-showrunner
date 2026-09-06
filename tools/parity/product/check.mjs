import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const manifestPath = join(root, 'docs', 'migration', 'product-surface.json');
const packageRoot = join(root, 'packages', 'showrunner-flutter');
const featureRoot = join(packageRoot, 'lib', 'features');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const allowedStatuses = new Set(manifest.statuses);
const errors = [];

function validateEntries(category, entries) {
  const ids = Object.keys(entries);
  if (new Set(ids).size !== ids.length) {
    errors.push(`${category}: duplicate entry id`);
  }
  for (const [id, entry] of Object.entries(entries)) {
    if (!entry || typeof entry !== 'object') {
      errors.push(`${category}.${id}: entry must be an object`);
      continue;
    }
    if (!allowedStatuses.has(entry.status)) {
      errors.push(`${category}.${id}: unknown status ${entry.status}`);
    }
    if (entry.status === 'intentionally_removed' && !entry.reason) {
      errors.push(`${category}.${id}: intentional removal needs a reason`);
    }
    if (entry.status !== 'intentionally_removed' && entry.main == null) {
      errors.push(`${category}.${id}: non-removed entry needs main evidence`);
    }
    if (entry.status !== 'intentionally_removed' && entry.flutter == null) {
      errors.push(`${category}.${id}: non-removed entry needs Flutter evidence`);
    }
  }
}

for (const category of [
  'workspaces',
  'commands',
  'documents',
  'resources',
  'editorModes',
  'systemMenus',
  'appFeatures',
]) {
  if (!manifest[category] || typeof manifest[category] !== 'object') {
    errors.push(`missing category ${category}`);
  } else {
    validateEntries(category, manifest[category]);
  }
}

const discoveredFeatures = existsSync(featureRoot)
  ? readdirSync(featureRoot, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
      .sort()
  : [];
const declaredFeatures = [...manifest.discovery.flutterFeatureDirectories].sort();
if (JSON.stringify(discoveredFeatures) !== JSON.stringify(declaredFeatures)) {
  errors.push(
    `Flutter feature directories are not registered: discovered=${JSON.stringify(discoveredFeatures)} declared=${JSON.stringify(declaredFeatures)}`,
  );
}

const sourceFiles = [];
function collectDartFiles(directory) {
  if (!existsSync(directory)) return;
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) collectDartFiles(path);
    else if (entry.name.endsWith('.dart')) sourceFiles.push(path);
  }
}
collectDartFiles(join(packageRoot, 'lib'));
collectDartFiles(join(packageRoot, 'test'));
collectDartFiles(join(packageRoot, 'tool'));
collectDartFiles(join(packageRoot, 'windows'));
const source = sourceFiles
  .map((path) => readFileSync(path, 'utf8'))
  .join('\n');
for (const marker of manifest.discovery.forbiddenFlutterMarkers) {
  if (source.includes(marker)) {
    errors.push(`forbidden Flutter product-surface marker found: ${marker}`);
  }
}

if (errors.length > 0) {
  process.stderr.write(`Product parity failed:\n${errors.map((error) => `- ${error}`).join('\n')}\n`);
  process.exitCode = 1;
} else {
  process.stdout.write(
    `Product parity passed (${Object.keys(manifest.workspaces).length} workspaces, ${sourceFiles.length} Dart files checked)\n`,
  );
}
