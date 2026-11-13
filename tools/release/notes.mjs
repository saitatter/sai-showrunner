import {execFileSync} from 'node:child_process';
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

// Release layout follows Collectarr App's editorial summary/full-history model.
// This implementation uses the existing Node toolchain and ShowRunner artwork.
export const summariesFile = 'docs/release-summaries.json';
export const bodyLimit = 120_000;
const tagPattern = /^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;
const bannerBranch = 'release-banners';
const markdown = value => String(value).replace(/[\\`*_[\]<>]/g, '\\$&');
const xml = value => String(value).replace(/[&<>"']/g, char => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&apos;'}[char]));

export function parseSummaries(source) {
  const data = JSON.parse(source);
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('Release summaries must be an object.');
  for (const [tag, entry] of Object.entries(data)) {
    if (tag !== 'Unreleased' && !tagPattern.test(tag)) throw new Error(`Invalid summary tag: ${tag}`);
    if (!entry || !Array.isArray(entry.summary) || entry.summary.some(line => typeof line !== 'string' || !line.trim() || /[\r\n]/.test(line))) {
      throw new Error(`Expected one-line summary entries for ${tag}.`);
    }
    if (entry.previousTag != null && !tagPattern.test(entry.previousTag)) throw new Error(`Invalid previous tag for ${tag}.`);
  }
  return data;
}

export function fallbackSummary(changelog) {
  for (const group of changelog.split(/^### /m)) {
    const rows = [...group.matchAll(/^[-*] (.+)$/gm)].map(match => match[1]);
    if (rows.length) return rows.slice(0, 10);
  }
  throw new Error('Release notes need an editorial summary or changelog entries.');
}

export function freezeSummary(source, tag, changelog, previousTag) {
  const data = parseSummaries(source);
  const summary = data[tag]?.summary.length ? data[tag].summary
    : data.Unreleased?.summary.length ? data.Unreleased.summary : fallbackSummary(changelog);
  data[tag] = {summary, previousTag: previousTag ?? null};
  data.Unreleased = {summary: []};
  return JSON.stringify(data, null, 2) + '\n';
}

export function closingIssues(message, repository) {
  const found = [];
  const pattern = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+(?:(?:https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/issues\/)|(?:([\w.-]+\/[\w.-]+)?#))(\d+)/gi;
  for (const match of message.matchAll(pattern)) found.push(`https://github.com/${match[1] || match[2] || repository}/issues/${match[3]}`);
  return found;
}

export function changeLines(repository, commits, pulls = {}) {
  const seen = new Set(), creditedPulls = new Set();
  const lines = [];
  for (const commit of commits) {
    if (seen.has(commit.sha) || commit.parents.length > 1) continue;
    seen.add(commit.sha);
    const message = commit.commit.message;
    const issues = closingIssues(message, repository);
    const pull = pulls[commit.sha];
    if (pull && !creditedPulls.has(pull.number)) {
      creditedPulls.add(pull.number);
      issues.push(...pull.closingIssuesReferences.nodes.map(issue => issue.url));
    }
    const closed = [...new Set(issues)];
    const title = message.split(/\r?\n/, 1)[0];
    const subject = markdown(title.length > 500 ? title.slice(0, 497) + '...' : title);
    const author = commit.author?.login ? `@${commit.author.login}` : markdown(commit.commit.author?.name || 'Unknown contributor');
    lines.push(`* ${subject} by ${author} in [${commit.sha.slice(0, 7)}](https://github.com/${repository}/commit/${commit.sha})${closed.length ? ` (closes ${closed.join(', ')})` : ''}`);
  }
  return lines;
}

export function contributorCredits(generated) {
  return /(?:^|\n)## New Contributors\n([\s\S]*?)(?=\n## |\n\*\*Full Changelog|$)/.exec(generated.replaceAll('\r\n','\n'))?.[0].trim() || '';
}

export function composeNotes({repository, tag, previousTag, summary, bannerUrl, changes, credits = '', limit = bodyLimit}) {
  const history = previousTag ? `https://github.com/${repository}/compare/${previousTag}...${tag}` : `https://github.com/${repository}/commits/${tag}`;
  const header = `![ShowRunner ${tag}](${bannerUrl})\n\n## Changes since last release:\n\n${summary.map(line => `- ${line}`).join('\n')}\n\n---\n\n## What's Changed\n\n`;
  const footer = `${credits ? '\n' + credits + '\n' : ''}\n**Full Changelog:** ${history}\n`;
  const omitted = `\n*The remaining commits are available in the [complete history](${history}).*\n`;
  const complete = header + changes.join('\n') + '\n' + footer;
  if (complete.length <= limit) return complete;
  if (header.length + footer.length + omitted.length > limit) throw new Error('Editorial summary exceeds the release description limit.');
  const selected = [];
  let size = header.length + footer.length;
  for (const line of changes) {
    if (size + line.length + 1 + omitted.length > limit) break;
    selected.push(line); size += line.length + 1;
  }
  return header + selected.join('\n') + '\n' + (selected.length < changes.length ? omitted : '') + footer;
}

export function renderBanner({tag, date, summary, commits, contributors}) {
  const rows = summary.slice(0, 6).map((line, index) => {
    const plain = line.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1').replace(/[`*_]/g, '');
    const text = plain.length > 112 ? plain.slice(0, 109) + '...' : plain;
    return `<circle cx="65" cy="${216 + index * 47}" r="5" fill="#20D6B5"/><text x="88" y="${223 + index * 47}" font-size="18">${xml(text)}</text>`;
  }).join('\n');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="600" viewBox="0 0 1200 600">
<rect width="1200" height="600" rx="26" fill="#111118"/>
<rect x="2" y="2" width="1196" height="596" rx="25" fill="none" stroke="#8A5CFF" stroke-width="4"/>
<g font-family="system-ui, sans-serif" fill="#F4F0FF">
<text x="54" y="83" font-size="38" font-weight="700">ShowRunner</text>
<text x="54" y="123" font-size="20" fill="#B8B1CC">AUTOMATION · CHAT · OVERLAYS</text>
<rect x="912" y="44" width="232" height="58" rx="14" fill="#302045"/>
<text x="1028" y="82" text-anchor="middle" font-size="25" font-weight="700">${xml(tag)}</text>
<path d="M54 159 H1145" stroke="#343044"/>
${rows}
<path d="M54 520 H1145" stroke="#343044"/>
<text x="54" y="562" font-size="18" fill="#B8B1CC">${xml(date)} · ${commits} commits · ${contributors} contributors</text>
</g></svg>\n`;
}

export function githubApi(route, {method = 'GET', body, paginate = false} = {}) {
  const args = ['api', '--method', method, route];
  if (paginate) args.push('--paginate', '--slurp');
  if (body !== undefined) args.push('--input', '-');
  try {
    return JSON.parse(execFileSync('gh', args, {input: body === undefined ? undefined : JSON.stringify(body), encoding:'utf8', maxBuffer:32 * 1024 * 1024, stdio:['pipe','pipe','pipe']}));
  } catch (error) {
    const status = Number(/HTTP (\d{3})/.exec(String(error.stderr))?.[1]);
    const failure = new Error(`GitHub API request failed: ${method} ${route}${status ? ` (HTTP ${status})` : error.code ? ` (${error.code})` : ''}`);
    failure.status = status;
    throw failure;
  }
}

export function rangeCommits(repository, previousTag, tag, api = githubApi) {
  const route = previousTag ? `repos/${repository}/compare/${previousTag}...${tag}?per_page=100` : `repos/${repository}/commits?sha=${tag}&per_page=100`;
  const pages = api(route, {paginate: true});
  const commits = pages.flatMap(page => previousTag ? page.commits : page);
  return previousTag ? commits : commits.reverse();
}

export function associatedPulls(repository, commits, api = githubApi) {
  const [owner, name] = repository.split('/');
  const result = {};
  const shas = [...new Set(commits.filter(commit => commit.parents.length < 2).map(commit => commit.sha))];
  for (let offset = 0; offset < shas.length; offset += 50) {
    const chunk = shas.slice(offset, offset + 50);
    if (chunk.some(sha => !/^[a-f0-9]{40}$/i.test(sha))) throw new Error('Expected full commit identifiers.');
    const fields = chunk.map((sha, i) => `c${i}: object(oid: "${sha}") { ... on Commit { associatedPullRequests(first: 5) { nodes { number merged baseRefName closingIssuesReferences(first: 100) { nodes { url } pageInfo { hasNextPage endCursor } } } } } }`).join(' ');
    const response = api('graphql', {method:'POST', body:{query:`query { repository(owner: "${owner}", name: "${name}") { ${fields} } }`}});
    if (response.errors || !response.data?.repository) throw new Error('Unable to read pull request attribution.');
    chunk.forEach((sha, i) => {
      const pulls = response.data.repository[`c${i}`]?.associatedPullRequests.nodes || [];
      const merged = pulls.filter(pull => pull.merged).sort((a,b) => Number(b.baseRefName === 'main') - Number(a.baseRefName === 'main'));
      if (merged[0]?.closingIssuesReferences.pageInfo?.hasNextPage) throw new Error('A pull request closes more than 100 issues; paginate its credits before publishing.');
      if (merged[0]) result[sha] = merged[0];
    });
  }
  return result;
}

export function publishBanner(repository, tag, svg, api = githubApi) {
  let parent;
  try { parent = api(`repos/${repository}/git/ref/heads/${bannerBranch}`).object.sha; }
  catch (error) { if (error.status !== 404) throw error; }
  const baseTree = parent ? api(`repos/${repository}/git/commits/${parent}`).tree.sha : undefined;
  const blob = api(`repos/${repository}/git/blobs`, {method:'POST', body:{content:Buffer.from(svg).toString('base64'), encoding:'base64'}});
  const tree = api(`repos/${repository}/git/trees`, {method:'POST', body:{...(baseTree ? {base_tree:baseTree} : {}), tree:[{path:`${tag}.svg`, mode:'100644', type:'blob', sha:blob.sha}]}});
  const commit = api(`repos/${repository}/git/commits`, {method:'POST', body:{message:`chore(release): add ${tag} banner`, tree:tree.sha, parents:parent ? [parent] : []}});
  api(`repos/${repository}/git/${parent ? 'refs/heads/' + bannerBranch : 'refs'}`, {method:parent ? 'PATCH':'POST', body:parent ? {sha:commit.sha, force:false} : {ref:`refs/heads/${bannerBranch}`, sha:commit.sha}});
  return `https://raw.githubusercontent.com/${repository}/${commit.sha}/${tag}.svg`;
}

export function formatRelease({repository, release, previousTag, summaries, cwd, write = false, refreshBanner = false, api = githubApi}) {
  const tag = release.tag_name;
  if (!tagPattern.test(tag)) throw new Error(`Unsupported release tag: ${tag}`);
  const section = new RegExp(`^## ${tag.slice(1).replaceAll('.', '\\.')}[^\\n]*\\n([\\s\\S]*?)(?=^## |$(?![\\s\\S]))`, 'm').exec(readFileSync(resolve(cwd,'CHANGELOG.md'),'utf8'))?.[1] || '';
  const entry = summaries[tag];
  const summary = entry?.summary.length ? entry.summary : fallbackSummary(section);
  if (entry && Object.hasOwn(entry, 'previousTag')) previousTag = entry.previousTag;
  const commits = rangeCommits(repository, previousTag, tag, api);
  const changes = changeLines(repository, commits, associatedPulls(repository, commits, api));
  const generated = api(`repos/${repository}/releases/generate-notes`, {method:'POST', body:{tag_name:tag, ...(previousTag ? {previous_tag_name:previousTag} : {})}});
  let bannerUrl = /^!\[[^\]]*\]\((https:\/\/\S+)\)/.exec(release.body || '')?.[1];
  if (!bannerUrl || refreshBanner) {
    const svg = renderBanner({tag, date:(release.published_at || release.created_at).slice(0,10), summary,
      commits:changes.length, contributors:new Set(commits.filter(commit => commit.parents.length < 2).map(commit => commit.author?.login || commit.commit.author?.name)).size});
    if (write) bannerUrl = publishBanner(repository, tag, svg, api);
    else {
      const directory = resolve(cwd,'.tmp/release-notes'); mkdirSync(directory,{recursive:true});
      const file = resolve(directory,`${tag}.svg`); writeFileSync(file,svg); bannerUrl = pathToFileURL(file).href;
    }
  }
  const body = composeNotes({repository, tag, previousTag, summary, bannerUrl, changes, credits:contributorCredits(generated.body)});
  if (write && body.trim() !== (release.body || '').replaceAll('\r\n','\n').trim()) api(`repos/${repository}/releases/${release.id}`, {method:'PATCH', body:{body}});
  return body;
}

export function runNotes(args = process.argv.slice(2), {cwd = resolve(import.meta.dirname,'../..'), api = githubApi, env = process.env} = {}) {
  let repository = env.GITHUB_REPOSITORY || 'saitatter/sai-showrunner', tag, all = false, write = false, includeDraft = false, refreshBanner = false;
  for (let i=0;i<args.length;i++) {
    const flag = args[i];
    if (flag === '--write') write = true;
    else if (flag === '--all') all = true;
    else if (flag === '--include-draft') includeDraft = true;
    else if (flag === '--refresh-banner') refreshBanner = true;
    else if (['--repo','--tag'].includes(flag) && args[i+1] && !args[i+1].startsWith('--')) {
      if (flag === '--repo') repository = args[++i]; else tag = args[++i];
    } else throw new Error(`Unknown or incomplete argument: ${flag}`);
  }
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) throw new Error('Expected owner/repository.');
  if ((tag && !tagPattern.test(tag)) || (all && tag) || (includeDraft && (!tag || all))) throw new Error('Use one tag or --all; draft formatting requires an explicit tag.');
  const path = resolve(cwd,summariesFile);
  const summaries = parseSummaries(existsSync(path) ? readFileSync(path,'utf8') : '{}');
  const releases = api(`repos/${repository}/releases?per_page=100`, {paginate:true}).flat()
    .sort((a,b) => (a.published_at || a.created_at).localeCompare(b.published_at || b.created_at));
  const eligible = releases.filter(release => !release.draft || (includeDraft && release.tag_name === tag));
  const selected = all ? eligible : [eligible.find(release => release.tag_name === (tag || eligible.at(-1)?.tag_name))].filter(Boolean);
  if (!selected.length) throw new Error('No selected published release; drafts require --tag and --include-draft.');
  return selected.map(release => {
    const previous = eligible.slice(0, eligible.indexOf(release)).filter(candidate => !candidate.draft).at(-1)?.tag_name;
    return formatRelease({repository, release, previousTag:previous, summaries, cwd, write, refreshBanner, api});
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { for (const notes of runNotes()) process.stdout.write(notes + '\n'); }
  catch (error) { process.stderr.write(error.message + '\n'); process.exitCode = 1; }
}
