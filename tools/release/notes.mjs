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
    if (entry.highlights !== undefined && (!Array.isArray(entry.highlights) || entry.highlights.length > 6 || entry.highlights.some(line => typeof line !== 'string' || !line.trim() || /[\r\n]/.test(line) || line.length > 48))) throw new Error(`Expected up to six short banner highlights for ${tag}.`);
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
  const editorial = data[tag]?.summary.length ? data[tag] : data.Unreleased?.summary.length ? data.Unreleased : undefined;
  const summary = editorial?.summary || fallbackSummary(changelog);
  data[tag] = {summary, ...(editorial?.highlights ? {highlights:editorial.highlights} : {}), previousTag: previousTag ?? null};
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
    if (pull && !creditedPulls.has(pull.id || pull.number)) {
      creditedPulls.add(pull.id || pull.number);
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

export function isBotIdentity(identity) {
  if (typeof identity === 'string') identity = {login:identity.replace(/^@/, '')};
  if (identity?.type?.toLowerCase() === 'bot') return true;
  const candidates = identity?.login ? [identity.login] : [identity?.name, identity?.email?.split('@')[0]?.replace(/^\d+\+/, '')];
  return candidates.some(value => value && (/\[bot\]$/i.test(value.trim()) || /^(?:github-actions|dependabot(?:-preview)?|renovate(?:-bot)?|greenkeeper(?:-bot)?|codecov(?:-io)?|snyk-bot)$/i.test(value.trim().replace(/\s+/g, '-'))));
}

export function humanContributorNames(commits) {
  const names = new Set();
  for (const commit of commits) {
    if (commit.parents.length > 1 || isBotIdentity({...commit.commit.author, ...commit.author})) continue;
    names.add(commit.author?.login ? `@${commit.author.login}` : commit.commit.author?.name || 'Unknown contributor');
  }
  return [...names].sort();
}

export function contributorCredits(generated, botLogins = []) {
  const section = /(?:^|\n)## New Contributors\n([\s\S]*?)(?=\n## |\n\*\*Full Changelog|$)/.exec(generated.replaceAll('\r\n','\n'))?.[1] || '';
  const knownBots = new Set(botLogins.map(login => login.toLowerCase()));
  const lines = section.split('\n').filter(line => ![...line.matchAll(/@([\w-]+(?:\[bot\])?)/g)].some(match => knownBots.has(match[1].toLowerCase()) || isBotIdentity(match[1])));
  const text = lines.join('\n').trim();
  return /^\s*[-*] /m.test(text) ? `## New Contributors\n${text}` : '';
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

const studioImage = readFileSync(new URL('../../docs/branding/release-banner/studio.jpg', import.meta.url)).toString('base64');
const applicationIcon = readFileSync(new URL('../../packages/showrunner-flutter/assets/app_icon.png', import.meta.url)).toString('base64');
const emojiRules = [
  [/shader|biome|terrain|raymarch/i, 'palette'], [/graph|subgraph|node|wire|conversion/i, 'puzzle'],
  [/command/i, 'robot'], [/emote|highlight|provider event/i, 'sparkles'],
  [/chat/i, 'chat'], [/moderation|permission/i, 'shield'],
  [/queue|trace|counter/i, 'chart'], [/audio|sound/i, 'headphones'],
  [/remote|twitch|youtube|integration|provider|obs/i, 'satellite'], [/documentation|release.note/i, 'memo'],
  [/dependency|configuration|compatibility|reset|settings|preferences/i, 'wrench'],
  [/flutter|workspace|desktop/i, 'desktop'], [/update|release/i, 'rocket'], [/starter|automation|keyboard/i, 'bolt'],
];
const emojiImages = Object.fromEntries([...new Set([...emojiRules.map(([,name]) => name), 'clapper'])].map(name => [name,
  readFileSync(new URL(`../../docs/branding/release-banner/emoji/${name}.png`, import.meta.url)).toString('base64')]));
export const bannerEmoji = label => emojiRules.find(([pattern]) => pattern.test(label))?.[1] || 'clapper';
const plainText = value => value.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1').replace(/[`*_]/g, '');
const shorten = (value, length) => value.length > length ? value.slice(0, length - 3) + '...' : value;

export function renderBanner({tag, date, summary, highlights, commits, contributorNames = [], mergedPulls = 0, previousTag}) {
  const humans = [...new Set(contributorNames.filter(name => !isBotIdentity(name)))];
  const contributors = humans.length;
  const rows = (highlights || summary).slice(0, 6).map((line, index) => {
    const y = 259 + index * 36;
    const emoji = bannerEmoji(plainText(line));
    return `<image data-emoji="${emoji}" href="data:image/png;base64,${emojiImages[emoji]}" x="504" y="${y - 25}" width="30" height="30"/><text x="548" y="${y}" font-size="21">${xml(shorten(plainText(line), 48))}</text>`;
  }).join('\n');
  const people = humans.slice(0, 4).map((name, index) => `<text x="1164" y="${691 + index * 32}" font-size="${name.length > 18 ? 18 : 22}">${xml(shorten(name, 26))}</text>`).join('\n');
  const month = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'][Number(date.slice(5,7)) - 1];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1672" height="941" viewBox="0 0 1672 941" role="img" aria-label="ShowRunner ${xml(tag)} release highlights">
<title>ShowRunner ${xml(tag)} ? ${xml(date)}</title>
<image href="data:image/jpeg;base64,${studioImage}" width="1672" height="941"/>
<rect x="36" y="8" width="144" height="130" rx="22" fill="#111118"/>
<image data-brand="application-icon" href="data:image/png;base64,${applicationIcon}" x="44" y="12" width="124" height="124"/>
<g font-family="monospace" fill="#EEEDE6">
<text x="511" y="211" font-size="43" fill="#A2EA80">${xml(tag)}</text>
<text x="1160" y="204" text-anchor="end" font-size="17" fill="#62D5CF">RELEASE NOTES</text>
${rows}
<text x="412" y="669" text-anchor="middle" font-size="14" fill="#E7D471">VERSION HISTORY</text>
<text x="412" y="704" text-anchor="middle" font-size="20">${xml(previousTag || 'FIRST RELEASE')}</text>
<text x="412" y="739" text-anchor="middle" font-size="21" fill="#A2EA80">${xml(tag)}</text>
</g>
<g font-family="sans-serif" fill="#222332">
<text x="1321" y="169" text-anchor="middle" font-size="24">${xml(date.slice(8,10))} ${month}</text>
<text x="1321" y="207" text-anchor="middle" font-size="26">${xml(date.slice(0,4))}</text>
<text x="618" y="685" font-size="24" font-weight="600">Commits</text><text x="1046" y="685" text-anchor="end" font-size="26">${commits}</text>
<text x="618" y="733" font-size="24" font-weight="600">Merged PRs</text><text x="1046" y="733" text-anchor="end" font-size="26">${mergedPulls}</text>
<text x="618" y="781" font-size="24" font-weight="600">Contributors</text><text x="1046" y="781" text-anchor="end" font-size="26">${contributors}</text>
${people}
${contributors > 4 ? `<text x="1164" y="819" font-size="18">+ ${contributors - 4} more in history</text>` : ''}
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
    const fields = chunk.map((sha, i) => `c${i}: object(oid: "${sha}") { ... on Commit { associatedPullRequests(first: 5) { nodes { id number merged baseRefName } } } }`).join(' ');
    const response = api('graphql', {method:'POST', body:{query:`query { repository(owner: "${owner}", name: "${name}") { ${fields} } }`}});
    if (response.errors || !response.data?.repository) throw new Error('Unable to read pull request attribution.');
    chunk.forEach((sha, i) => {
      const pulls = response.data.repository[`c${i}`]?.associatedPullRequests.nodes || [];
      const merged = pulls.filter(pull => pull.merged).sort((a,b) => Number(b.baseRefName === 'main') - Number(a.baseRefName === 'main'));
      if (merged[0]) result[sha] = merged[0];
    });
  }
  // Fetch issue connections once per unique PR, rather than for every commit/PR
  // combination. Initial releases can contain thousands of inherited commits.
  const ids = [...new Set(Object.values(result).map(pull => pull.id))];
  const metadata = new Map();
  for (let offset = 0; offset < ids.length; offset += 50) {
    const group = ids.slice(offset, offset + 50);
    const response = api('graphql', {method:'POST', body:{query:`query { nodes(ids: ${JSON.stringify(group)}) { ... on PullRequest { id closingIssuesReferences(first: 100) { nodes { url } pageInfo { hasNextPage } } } } }`}});
    if (response.errors || response.data?.nodes?.length !== group.length) throw new Error('Unable to read pull request issue credits.');
    for (const node of response.data.nodes) {
      if (!node?.id || !node.closingIssuesReferences || node.closingIssuesReferences.pageInfo?.hasNextPage) throw new Error('Incomplete pull request issue credits; paginate before publishing.');
      metadata.set(node.id, node.closingIssuesReferences);
    }
  }
  for (const pull of Object.values(result)) {
    if (!metadata.has(pull.id)) throw new Error('Missing pull request issue credits.');
    pull.closingIssuesReferences = metadata.get(pull.id);
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
  const pulls = associatedPulls(repository, commits, api);
  const changes = changeLines(repository, commits, pulls);
  const generated = api(`repos/${repository}/releases/generate-notes`, {method:'POST', body:{tag_name:tag, ...(previousTag ? {previous_tag_name:previousTag} : {})}});
  let bannerUrl = /^!\[[^\]]*\]\((https:\/\/\S+)\)/.exec(release.body || '')?.[1];
  if (!bannerUrl || refreshBanner) {
    const uniqueCommits = [...new Map(commits.filter(commit => commit.parents.length < 2).map(commit => [commit.sha, commit])).values()];
    const contributorNames = humanContributorNames(uniqueCommits);
    const svg = renderBanner({tag, date:(release.published_at || release.created_at).slice(0,10), summary,
      highlights:entry?.highlights, previousTag, commits:changes.length,
      contributorNames, mergedPulls:new Set(Object.values(pulls).map(pull => pull.id || pull.number)).size});
    if (write) bannerUrl = publishBanner(repository, tag, svg, api);
    else {
      const directory = resolve(cwd,'.tmp/release-notes'); mkdirSync(directory,{recursive:true});
      const file = resolve(directory,`${tag}.svg`); writeFileSync(file,svg); bannerUrl = pathToFileURL(file).href;
    }
  }
  const botLogins = commits.filter(commit => isBotIdentity({...commit.commit.author, ...commit.author})).map(commit => commit.author?.login).filter(Boolean);
  const body = composeNotes({repository, tag, previousTag, summary, bannerUrl, changes, credits:contributorCredits(generated.body, botLogins)});
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
