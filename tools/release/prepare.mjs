import {appendFileSync, readFileSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

export const root = resolve(import.meta.dirname, '../..');
export const releaseFiles = ['package.json', 'packages/showrunner-flutter/pubspec.yaml',
  'packages/showrunner-flutter/lib/services/update_check_service.dart', 'CHANGELOG.md'];
const read = (file, cwd) => readFileSync(resolve(cwd, file), 'utf8');
const git = (args, cwd) => execFileSync('git', args, {cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}).trim();

export function parseVersion(value) {
  if (typeof value !== 'string' || value.trim() !== value) throw new Error('Version must not contain surrounding whitespace.');
  const match = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/.exec(value);
  if (!match || match[4]?.split('.').some(part => /^\d+$/.test(part) && part.length > 1 && part.startsWith('0'))) {
    throw new Error(`Invalid version: ${value}. Use X.Y.Z or X.Y.Z-beta.N, without v or build metadata.`);
  }
  const numbers = match.slice(1, 4).map(Number);
  if (numbers.some(number => !Number.isSafeInteger(number))) throw new Error('Version component is too large.');
  return {numbers, prerelease: match[4]?.split('.') ?? []};
}

export function compareVersions(left, right) {
  const a = parseVersion(left), b = parseVersion(right);
  for (let i = 0; i < 3; i++) if (a.numbers[i] !== b.numbers[i]) return Math.sign(a.numbers[i] - b.numbers[i]);
  if (!a.prerelease.length || !b.prerelease.length) return Math.sign(b.prerelease.length - a.prerelease.length);
  for (let i = 0; i < Math.max(a.prerelease.length, b.prerelease.length); i++) {
    const x = a.prerelease[i], y = b.prerelease[i];
    if (x === y) continue;
    if (x === undefined || y === undefined) return x === undefined ? -1 : 1;
    const xn = /^\d+$/.test(x), yn = /^\d+$/.test(y);
    if (xn && yn) return Math.sign(Number(x) - Number(y));
    if (xn !== yn) return xn ? -1 : 1;
    return x < y ? -1 : 1;
  }
  return 0;
}

export function releaseBump(messages) {
  let bump = null;
  for (const message of messages) {
    const subject = message.trim().split(/\r?\n/, 1)[0];
    if (/^[a-z]+(?:\([^\n)]+\))?!:/.test(subject) || /^BREAKING[ -]CHANGE:\s*\S/m.test(message)) return 'major';
    if (/^feat(?:\([^\n)]+\))?:/.test(subject)) bump = 'minor';
    else if (!bump && /^(fix|perf)(?:\([^\n)]+\))?:/.test(subject)) bump = 'patch';
  }
  return bump;
}

export function nextVersion(previous, bump) {
  const [major, minor, patch] = parseVersion(previous).numbers;
  return bump === 'major' ? `${major + 1}.0.0` : bump === 'minor' ? `${major}.${minor + 1}.0` : `${major}.${minor}.${patch + 1}`;
}

export function cutChangelog(source, version, date) {
  const match = /^## Unreleased\s*\r?\n([\s\S]*?)(?=^## |$(?![\s\S]))/m.exec(source);
  if (!match) throw new Error('CHANGELOG.md must contain ## Unreleased.');
  const entries = match[1].trim().split(/(?=^### )/m)
    .filter(section => !section.startsWith('### ') || /^[-*] \S/m.test(section)).join('').trim();
  if (!/^[-*] \S/m.test(entries)) throw new Error('Add user-facing entries under Unreleased before publishing.');
  const replacement = `## Unreleased\n\n### Features\n\n### Fixes\n\n### Refactors\n\n### Docs\n\n### CI & Build\n\n## ${version} - ${date}\n\n${entries}\n\n`;
  return {entries, changelog: source.slice(0, match.index) + replacement + source.slice(match.index + match[0].length)};
}

export function planRelease({cwd = root, version, backfill, date = new Date().toISOString().slice(0, 10)} = {}) {
  if (version && backfill) throw new Error('Version and backfill are mutually exclusive.');
  const commit = git(['rev-parse', 'HEAD'], cwd);
  if (backfill) {
    parseVersion(backfill);
    const tag = `v${backfill}`;
    const target = git(['rev-parse', '--verify', `refs/tags/${tag}^{commit}`], cwd);
    git(['merge-base', '--is-ancestor', target, commit], cwd);
    const pkg = JSON.parse(git(['show', `${tag}:package.json`], cwd));
    const pubspec = git(['show', `${tag}:packages/showrunner-flutter/pubspec.yaml`], cwd);
    const match = /^version:\s*(\S+)\+(\d+)\s*$/m.exec(pubspec);
    if (!match || pkg.version !== backfill || match[1] !== backfill) throw new Error('Backfill tag must contain matching Flutter and package versions. Legacy tags cannot be repackaged as Flutter releases.');
    return {version: backfill, tag, commit: target, build: Number(match[2]), publish: true, backfill: true,
      notes: `Rebuild assets from existing immutable tag ${tag}.`, files: {}};
  }
  const tags = git(['tag', '--merged', 'HEAD', '--list', 'v*'], cwd).split('\n')
    .filter(tag => /^v\d+\.\d+\.\d+$/.test(tag)).sort((a, b) => compareVersions(b.slice(1), a.slice(1)));
  const previousTag = tags[0];
  const messages = git(['log', '--format=%B%x00', ...(previousTag ? [`${previousTag}..HEAD`] : ['HEAD'])], cwd).split('\0');
  const bump = releaseBump(messages);
  if (!version && !bump) return {publish: false, commit, notes: 'No feat, fix, perf or breaking commits to release.', files: {}};
  const pkg = JSON.parse(read('package.json', cwd));
  const base = previousTag?.slice(1) ?? pkg.version;
  version ??= nextVersion(base, bump);
  if (parseVersion(version).numbers.some(number => number > 65535)) throw new Error('Version exceeds Windows numeric version limits.');
  if (previousTag && compareVersions(version, base) <= 0) throw new Error(`Version must be newer than ${previousTag}.`);
  if (compareVersions(parseVersion(version).numbers.join('.'), parseVersion(pkg.version).numbers.join('.')) < 0) throw new Error(`Version must not downgrade the source version ${pkg.version}.`);
  // Reject an existing stable or prerelease tag; never rewrite published history.
  if (git(['tag', '--list', `v${version}`], cwd)) throw new Error(`Tag v${version} already exists. Use backfill to rebuild its assets.`);
  const releasedVersions = git(['tag', '--merged', 'HEAD', '--list', 'v*'], cwd).split('\n')
    .map(tag => tag.slice(1)).filter(value => { try { parseVersion(value); return true; } catch { return false; } });
  if (releasedVersions.some(value => compareVersions(version, value) <= 0)) throw new Error('Version must advance the latest reachable release, including prereleases.');
  const pubspec = read(releaseFiles[1], cwd);
  const old = /^version:\s*(\S+)\+(\d+)\s*$/m.exec(pubspec);
  const updater = read(releaseFiles[2], cwd);
  const updaterVersion = /SHOWRUNNER_VERSION'[\s\S]*?defaultValue:\s*'([^']+)'/.exec(updater);
  if (!old || old[1] !== pkg.version || updaterVersion?.[1] !== pkg.version) throw new Error('Package, Flutter and updater versions must agree before preparing a release.');
  const build = Number(old[2]) + 1;
  if (!Number.isSafeInteger(build) || build > 65535) throw new Error('Windows build number exceeds the supported range.');
  const cut = cutChangelog(read('CHANGELOG.md', cwd), version, date);
  const notes = `# ShowRunner ${version}\n\n${cut.entries}\n\n${previousTag ? `**Full comparison:** https://github.com/saitatter/sai-showrunner/compare/${previousTag}...v${version}\n` : ''}`;
  pkg.version = version;
  return {version, tag: `v${version}`, build, commit, previousTag, publish: true, backfill: false, notes,
    files: {
      [releaseFiles[0]]: JSON.stringify(pkg, null, 2) + '\n',
      [releaseFiles[1]]: pubspec.replace(/^version:.*$/m, `version: ${version}+${build}`),
      [releaseFiles[2]]: updater.replace(/(SHOWRUNNER_VERSION'[\s\S]*?defaultValue:\s*')[^']+(')/, (_, prefix, suffix) => prefix + version + suffix),
      [releaseFiles[3]]: cut.changelog,
    }};
}

export function run(args = process.argv.slice(2), cwd = root, env = process.env) {
  let check = false, version, notesPath, backfill;
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    if (flag === '--check') { check = true; continue; }
    if (!['--version', '--notes', '--backfill'].includes(flag) || !args[i + 1] || args[i + 1].startsWith('--')) throw new Error(`Unknown or incomplete argument: ${flag}`);
    const value = args[++i];
    if (flag === '--version') version = value;
    else if (flag === '--notes') notesPath = value;
    else backfill = value;
  }
  if (!check && (!notesPath || backfill)) throw new Error('Use --check for previews/backfills, or --notes <file> to prepare release files.');
  if (!check && git(['status', '--porcelain', '--untracked-files=no'], cwd)) throw new Error('Prepare releases from a clean tracked working tree.');
  if (notesPath && releaseFiles.some(file => resolve(cwd, file) === resolve(notesPath))) throw new Error('Notes must not overwrite release inputs.');
  const plan = planRelease({cwd, version, backfill});
  if (!check && plan.publish) {
    for (const [file, value] of Object.entries(plan.files)) writeFileSync(resolve(cwd, file), value);
  }
  if (notesPath) writeFileSync(notesPath, plan.notes);
  if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT,
    `version=${plan.version ?? ''}\ntag=${plan.tag ?? ''}\ncommit=${plan.commit}\nbuild=${plan.build ?? ''}\npublish=${plan.publish}\n`);
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, plan.notes + '\n');
  console.log(JSON.stringify({...plan, files: Object.keys(plan.files)}, null, 2));
  return plan;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { run(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
