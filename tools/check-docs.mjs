import {existsSync, readFileSync, readdirSync} from 'node:fs';
import {resolve, dirname, extname, relative} from 'node:path';

const root = resolve(import.meta.dirname, '..');
const files = ['README.md', 'AGENTS.md', 'CHANGELOG.md'];
function walk(directory) {
  for (const entry of readdirSync(resolve(root, directory), {withFileTypes: true})) {
    const path = `${directory}/${entry.name}`;
    if (entry.isDirectory()) walk(path);
    else if (['.md', '.html'].includes(extname(path))) files.push(path);
  }
}
walk('docs');
const failures = [];
for (const file of files) {
  if (!existsSync(resolve(root, file))) { failures.push(`Missing document: ${file}`); continue; }
  const content = readFileSync(resolve(root, file), 'utf8');
  const links = [...content.matchAll(/!?\[[^\]]*\]\((?:<([^>]+)>|([^\s)]+))(?:\s+"[^"]*")?\)/g)].map(match => match[1] ?? match[2]);
  if (file.endsWith('.html')) links.push(...[...content.matchAll(/(?:href|src)="([^"]+)"/g)].map(match => match[1]));
  for (const link of links) {
    if (/^(?:[a-z][a-z\d+.-]*:|\/\/|#)/i.test(link)) continue;
    const target = decodeURIComponent(link.split(/[?#]/)[0]);
    const path = resolve(target.startsWith('/') ? root : dirname(resolve(root, file)), target.replace(/^\//, ''));
    if (!existsSync(path)) failures.push(`${file}: broken link ${link} (${relative(root, path)})`);
  }
}
if (failures.length) { console.error(failures.join('\n')); process.exitCode = 1; }
else console.log(`Documentation links passed (${files.length} documents).`);
