import { execFileSync } from 'node:child_process';

const ref = process.argv[process.argv.indexOf('--ref') + 1] || 'main';

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8' });
}

function allPluginFiles() {
  return git('ls-tree', '-r', '--name-only', ref, '--', 'plugins')
    .split(/\r?\n/)
    .filter((file) => /\.(css|json|md|ts|vue)$/.test(file));
}

function sourceFor(file) {
  return git('show', `${ref}:${file}`);
}

const pluginFilesByPlugin = new Map();

function filesForPlugin(pluginId) {
  if (!pluginFilesByPlugin.has(pluginId)) {
    pluginFilesByPlugin.set(
      pluginId,
      allFiles.filter((file) => file.startsWith(`plugins/${pluginId}/`)),
    );
  }
  return pluginFilesByPlugin.get(pluginId);
}

function builtInPlugin() {
  const sourceFile = 'packages/showrunner/src/main/builtin-plugin.ts';
  const source = sourceFor(sourceFile);
  return {
    id: 'ShowRunner',
    name: 'ShowRunner',
    sourceFiles: [sourceFile],
    actions: literalIds(source, 'defineAction'),
    triggers: literalIds(source, 'defineTrigger'),
    settings: literalIds(source, 'defineSetting'),
    states: literalIds(source, 'defineState'),
    resources: [],
    ui: { sourceFiles: [] },
  };
}

function findBalancedObject(source, openIndex) {
  let depth = 0;
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;

  for (let index = openIndex; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];

    if (lineComment) {
      if (character === '\n') lineComment = false;
      continue;
    }
    if (blockComment) {
      if (character === '*' && next === '/') {
        blockComment = false;
        index += 1;
      }
      continue;
    }
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
      continue;
    }
    if (character === '/' && next === '/') {
      lineComment = true;
      index += 1;
      continue;
    }
    if (character === '/' && next === '*') {
      blockComment = true;
      index += 1;
      continue;
    }
    if (character === '"' || character === "'" || character === '`') {
      quote = character;
      continue;
    }
    if (character === '{') depth += 1;
    if (character === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(openIndex, index + 1);
    }
  }
  return '';
}

function literalIds(source, callName) {
  const ids = [];
  let cursor = 0;
  const token = `${callName}(`;
  while (cursor < source.length) {
    const callIndex = source.indexOf(token, cursor);
    if (callIndex < 0) break;
    let argumentIndex = callIndex + token.length;
    while (/\s/.test(source[argumentIndex] || '')) argumentIndex += 1;
    if (source[argumentIndex] === '{') {
      const block = findBalancedObject(source, argumentIndex);
      const match = block.match(/\bid\s*:\s*["'`]([^"'`]+)["'`]/);
      if (match) ids.push(match[1]);
      cursor = argumentIndex + Math.max(block.length, 1);
      continue;
    }
    const match = source.slice(argumentIndex).match(/^["']([^"']+)["']/);
    if (match) ids.push(match[1]);
    cursor = argumentIndex + 1;
  }
  return [...new Set(ids)].sort();
}

function resourceIds(source) {
  return [
    ...source.matchAll(/new\s+ResourceStorage(?:<[^>]+>)?\(\s*["']([^"']+)["']/g),
  ].map((match) => match[1]).sort();
}

const allFiles = allPluginFiles();
const files = allFiles.filter(
  (file) => file.endsWith('.ts') && file.includes('/main/src/'),
);
const pluginIds = [...new Set(
  files.map((file) => file.match(/^plugins\/([^/]+)\/main\/src\//)?.[1]),
)].filter(Boolean).sort();

const plugins = [
  ...pluginIds.map((pluginId) => {
  const pluginFiles = filesForPlugin(pluginId);
  const sources = pluginFiles.map(sourceFor).join('\n');
  const contractFiles = files.filter((file) => file.startsWith(`plugins/${pluginId}/`));
  const entry = sourceFor(
    contractFiles.find((file) => file.endsWith('/main.ts')) || contractFiles[0],
  );
  const metadata = entry.match(
    /define(?:Satellite)?Plugin\(\s*\{([\s\S]*?)\}\s*,/,
  )?.[1] || '';
  const readMetadata = (key) =>
    metadata.match(new RegExp(`\\b${key}\\s*:\\s*["']([^"']+)["']`))?.[1] ||
    null;

  return {
    id: readMetadata('id') || pluginId,
    name: readMetadata('name') || pluginId,
    sourceFiles: contractFiles.sort(),
    actions: literalIds(sources, 'defineAction'),
    triggers: literalIds(sources, 'defineTrigger'),
    settings: literalIds(sources, 'defineSetting'),
    states: literalIds(sources, 'defineState'),
    resources: resourceIds(sources),
    ui: { sourceFiles: pluginFiles.filter((file) => file.includes('/renderer/')) },
  };
  }),
  builtInPlugin(),
].sort((left, right) => left.id.localeCompare(right.id));

process.stdout.write(`${JSON.stringify({ reference: ref, plugins }, null, 2)}\n`);
