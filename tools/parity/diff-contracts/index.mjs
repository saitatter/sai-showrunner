import { readFileSync } from 'node:fs';

const mainPath = process.argv[process.argv.indexOf('--main') + 1];
const flutterPath = process.argv[process.argv.indexOf('--flutter') + 1];

if (!mainPath || !flutterPath) {
  throw new Error('Usage: node index.mjs --main main.json --flutter flutter.json');
}

const main = JSON.parse(readFileSync(mainPath, 'utf8'));
const flutter = JSON.parse(readFileSync(flutterPath, 'utf8'));
const categories = ['settings', 'actions', 'triggers', 'states', 'resources'];
const flutterById = new Map(flutter.plugins.map((plugin) => [plugin.id, plugin]));

function compareCategory(expected, actual) {
  const idOf = (value) => (typeof value === 'string' ? value : value?.id);
  const expectedSet = new Set((expected || []).map(idOf).filter(Boolean));
  const actualSet = new Set((actual || []).map(idOf).filter(Boolean));
  const missing = [...expectedSet].filter((value) => !actualSet.has(value));
  const extra = [...actualSet].filter((value) => !expectedSet.has(value));
  return {
    expected: [...expectedSet].sort(),
    actual: [...actualSet].sort(),
    missing,
    extra,
    status: missing.length === 0 ? 'equivalent' : actualSet.size === 0 ? 'missing' : 'partial',
  };
}

const plugins = main.plugins.map((expected) => {
  const actual = flutterById.get(expected.id);
  if (!actual) {
    return {
      id: expected.id,
      status: 'missing',
      categories: Object.fromEntries(
        categories.map((category) => [category, compareCategory(expected[category], [])]),
      ),
      ui: { status: 'missing' },
    };
  }
  const categoryResults = Object.fromEntries(
    categories.map((category) => [category, compareCategory(expected[category], actual[category])]),
  );
  const status = Object.values(categoryResults).some((result) => result.status === 'missing')
    ? 'partial'
    : Object.values(categoryResults).some((result) => result.status === 'partial')
      ? 'partial'
      : 'equivalent';
  return {
    id: expected.id,
    status,
    categories: categoryResults,
    ui: {
      expectedSourceFiles: expected.ui?.sourceFiles?.length || 0,
      flutterWorkspace: Boolean(actual.ui?.workspaceBuilder),
      status: actual.ui?.workspaceBuilder ? 'equivalent' : 'partial',
    },
  };
});

const flutterOnly = flutter.plugins
  .filter((plugin) => !main.plugins.some((expected) => expected.id === plugin.id))
  .map((plugin) => plugin.id);

process.stdout.write(`${JSON.stringify({
  reference: main.reference,
  plugins,
  flutterOnly,
}, null, 2)}\n`);
