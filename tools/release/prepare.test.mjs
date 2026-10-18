import {afterEach, describe, expect, it} from 'vitest';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {compareVersions, cutChangelog, parseVersion, planRelease, releaseBump, releaseFiles, run} from './prepare.mjs';

const directories = [];
afterEach(() => { for (const directory of directories.splice(0)) rmSync(directory, {recursive: true, force: true}); });
const git = (cwd, ...args) => execFileSync('git', args, {cwd, encoding: 'utf8'}).trim();
function fixture() {
  const cwd = mkdtempSync(join(tmpdir(), 'showrunner-release-')); directories.push(cwd);
  const files = {
    'package.json': '{"name":"showrunner","version":"1.4.0"}\n',
    [releaseFiles[1]]: 'name: app\nversion: 1.4.0+7\n',
    [releaseFiles[2]]: "const version = String.fromEnvironment('SHOWRUNNER_VERSION', defaultValue: '1.4.0');\n",
    'CHANGELOG.md': '# Changelog\n\n## Unreleased\n\n### Features\n- Visual automation editing.\n\n## 1.4.0 - 2026-01-01\n\n- Previous release.\n',
  };
  for (const [file, value] of Object.entries(files)) { mkdirSync(dirname(join(cwd, file)), {recursive: true}); writeFileSync(join(cwd, file), value); }
  git(cwd, 'init', '--initial-branch=main'); git(cwd, 'config', 'core.autocrlf', 'false'); git(cwd, 'config', 'user.name', 'Release test');
  git(cwd, 'config', 'user.email', 'release@example.invalid');
  git(cwd, 'add', '.'); git(cwd, 'commit', '-m', 'chore: baseline'); git(cwd, 'tag', 'v1.4.0');
  return cwd;
}
function commit(cwd, message) { git(cwd, 'commit', '--allow-empty', '-m', message); }

describe('release planning', () => {
  it('uses breaking changes, features and fixes; maintenance alone does not publish', () => {
    expect(releaseBump(['docs: guide', 'chore: tooling', 'ci: runner', 'docs: example\n\nfeat: example only'])).toBeNull();
    expect(releaseBump(['fix(obs): reconnect', 'perf: compile'])).toBe('patch');
    expect(releaseBump(['fix: repair', 'feat: commands'])).toBe('minor');
    expect(releaseBump(['feat: graph\n\nBREAKING CHANGE: strict documents'])).toBe('major');
    expect(releaseBump(['refactor(graph)!: replace format'])).toBe('major');
  });
  it('orders prereleases correctly and rejects unsafe versions', () => {
    for (const version of ['2.0.0', '2.0.0-beta.1']) expect(parseVersion(version)).toBeTruthy();
    for (const version of ['v2.0.0', '01.0.0', '2.0.0-beta.01', '2.0.0+4', '../../main', '2.0.0\nother', '2.0.0\n']) expect(() => parseVersion(version)).toThrow();
    expect(compareVersions('2.0.0', '2.0.0-beta.9')).toBeGreaterThan(0);
    expect(compareVersions('2.0.0-beta.10', '2.0.0-beta.2')).toBeGreaterThan(0);
  });
  it('plans without changing inputs, then updates all versions and only Unreleased notes', () => {
    const cwd = fixture(); commit(cwd, 'feat: new editor');
    const before = releaseFiles.map(file => readFileSync(join(cwd, file), 'utf8'));
    const plan = run(['--check'], cwd, {});
    expect(plan.version).toBe('1.5.0'); expect(plan.build).toBe(8);
    expect(() => run(['--check', '--notes', join(cwd, 'package.json')], cwd, {})).toThrow(/overwrite/);
    expect(releaseFiles.map(file => readFileSync(join(cwd, file), 'utf8'))).toEqual(before);
    const notes = join(cwd, 'notes.md');
    run(['--notes', notes], cwd, {});
    expect(JSON.parse(readFileSync(join(cwd, 'package.json'), 'utf8')).version).toBe('1.5.0');
    expect(readFileSync(join(cwd, releaseFiles[1]), 'utf8')).toContain('1.5.0+8');
    expect(readFileSync(join(cwd, releaseFiles[2]), 'utf8')).toContain("defaultValue: '1.5.0'");
    expect(readFileSync(notes, 'utf8')).toContain('compare/v1.4.0...v1.5.0');
    expect(readFileSync(notes, 'utf8')).not.toContain('Previous release.');
    expect(readFileSync(join(cwd, 'CHANGELOG.md'), 'utf8')).toContain('Previous release.');
    expect(git(cwd, 'tag', '--list')).toBe('v1.4.0');
  });
  it('ignores unrelated tags and refuses old versions, existing tags or inconsistent inputs', () => {
    const cwd = fixture(); commit(cwd, 'feat!: strict new format');
    git(cwd, 'tag', 'parity-reference/main-2026-09-05');
    expect(planRelease({cwd}).version).toBe('2.0.0');
    expect(() => planRelease({cwd, version: '1.3.0'})).toThrow(/newer/);
    expect(() => planRelease({cwd, version: '2.70000.0'})).toThrow(/Windows/);
    git(cwd, 'tag', 'v2.0.0-beta.2');
    expect(() => planRelease({cwd, version: '2.0.0-beta.2'})).toThrow(/exists/);
    expect(() => planRelease({cwd, version: '2.0.0-beta.1'})).toThrow(/advance/);
    writeFileSync(join(cwd, releaseFiles[1]), 'version: 9.0.0+1\n');
    expect(() => planRelease({cwd, version: '2.1.0'})).toThrow(/agree/);
  });
  it('allows prereleases of the unreleased source milestone and increments their build', () => {
    const cwd = fixture(); commit(cwd, 'feat!: new product');
    const plan = planRelease({cwd, version: '2.0.0-beta.1'});
    expect(plan.version).toBe('2.0.0-beta.1'); expect(plan.build).toBe(8);
  });
  it('does not publish maintenance-only history, and requires meaningful release notes', () => {
    const cwd = fixture(); commit(cwd, 'docs: update manual');
    expect(planRelease({cwd}).publish).toBe(false);
    expect(() => cutChangelog('# Changelog\n\n## Unreleased\n\n### Features\n', '2.0.0', '2026-10-19')).toThrow(/user-facing/);
  });
  it('validates backfill tags without changing versions or history', () => {
    const cwd = fixture(); commit(cwd, 'fix: later');
    const plan = planRelease({cwd, backfill: '1.4.0'});
    expect(plan.commit).toBe(git(cwd, 'rev-parse', 'v1.4.0'));
    expect(plan.files).toEqual({}); expect(plan.build).toBe(7);
    expect(() => planRelease({cwd, backfill: '9.0.0'})).toThrow();
    expect(() => planRelease({cwd, backfill: '1.4.0', version: '2.0.0'})).toThrow(/exclusive/);
    git(cwd, 'tag', 'v1.5.0');
    expect(() => planRelease({cwd, backfill: '1.5.0'})).toThrow(/matching/);
  });
  it('refuses writes from a dirty tree and malformed CLI arguments', () => {
    const cwd = fixture(); commit(cwd, 'fix: repair');
    writeFileSync(join(cwd, 'package.json'), '{"version":"1.4.0","dirty":true}');
    expect(() => run(['--notes', join(cwd, 'notes.md')], cwd, {})).toThrow(/clean/);
    expect(() => run(['--version'], cwd, {})).toThrow(/incomplete/);
    expect(() => run(['--unknown'], cwd, {})).toThrow(/Unknown/);
  });
});
