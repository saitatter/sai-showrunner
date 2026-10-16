import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
const directory = resolve(process.argv[2] ?? '.tmp/benchmarks');
const report = {};
for (const [file, prefix] of [['editor.log', 'SHOWRUNNER_GRAPH_BENCHMARK'], ['execution.log', 'SHOWRUNNER_GRAPH_EXECUTION_BENCHMARK']]) {
  const raw = readFileSync(join(directory, file));
  const content = raw.toString(raw[0] === 0xff && raw[1] === 0xfe ? 'utf16le' : 'utf8');
  const samples = content.split(/\r?\n/)
    .filter(line => line.includes(prefix + ' '))
    .flatMap(line => JSON.parse(line.slice(line.indexOf(prefix) + prefix.length).trim()));
  if (!samples.length) throw new Error(`No measurements in ${file}`);
  const groups = {};
  for (const sample of samples) {
    const count = `${sample.scenario ?? 'editor'}:${sample.requestedNodes ?? sample.nodes ?? sample.iterations ?? sample.subgraphs}`;
    (groups[count] ??= []).push(sample);
  }
  report[file] = Object.fromEntries(Object.entries(groups).map(([count, values]) => {
    const metrics = {};
    for (const key of Object.keys(values[0]).filter(key => typeof values[0][key] === 'number')) {
      const ordered = values.map(value => value[key]).sort((a,b) => a-b);
      const middle = Math.floor(ordered.length / 2);
      metrics[key] = {median: ordered.length % 2 ? ordered[middle] : (ordered[middle-1] + ordered[middle])/2,
        p95: ordered[Math.ceil(ordered.length * 0.95) - 1]};
    }
    return [count, {samples: values.length, metrics}];
  }));
}
mkdirSync(directory, {recursive: true});
writeFileSync(join(directory, 'summary.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report));
