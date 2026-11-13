import {afterEach, describe, expect, it} from 'vitest';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {resolve, join, sep} from 'node:path';
import {associatedPulls, changeLines, closingIssues, composeNotes, contributorCredits, freezeSummary,
  parseSummaries, publishBanner, rangeCommits, renderBanner, runNotes} from './notes.mjs';

const scratch = resolve(import.meta.dirname, '../../.tmp');
const directories = [];
afterEach(() => { for (const path of directories.splice(0)) {
  if (!path.startsWith(scratch + sep)) throw new Error('Unexpected fixture directory.');
  rmSync(path, {recursive:true, force:true});
} });
const sha = char => char.repeat(40);
const commit = (char, message, author = 'alice', parents = [{}]) => ({sha:sha(char), parents,
  author:author ? {login:author} : null, commit:{message, author:{name:'Local contributor'}}});
const release = (tag, id, draft = false) => ({tag_name:tag, id, draft, created_at:`2026-01-0${id}T00:00:00Z`,
  published_at:draft ? null : `2026-01-0${id}T00:00:00Z`, body:`![ShowRunner](https://raw.githubusercontent.com/o/r/${sha('b')}/${tag}.svg)\nOld notes`});
function fixture() {
  mkdirSync(scratch,{recursive:true});
  const cwd = mkdtempSync(join(scratch,'release-notes-')); directories.push(cwd);
  mkdirSync(join(cwd,'docs'));
  writeFileSync(join(cwd,'docs/release-summaries.json'), JSON.stringify({'v1.0.0':{summary:['First release.'],previousTag:null},'v1.1.0':{summary:['New commands.'],previousTag:'v1.0.0'},'v9.0.0':{summary:['Draft feature.'],previousTag:'v1.1.0'}}));
  writeFileSync(join(cwd,'CHANGELOG.md'),'# Changelog\n\n## 1.1.0 - 2026-01-02\n\n### Features\n- New commands.\n');
  const releases = [release('v1.0.0',1), release('v1.1.0',2), release('v9.0.0',3,true)];
  const calls = [];
  const api = (route, options = {}) => {
    calls.push({route,...options});
    if (route.includes('/releases?')) return [releases];
    if (route.includes('/compare/')) return [{commits:[commit('a','feat: new commands')]}];
    if (route.includes('/commits?')) return [[commit('a','feat: first release')]];
    if (route === 'graphql') return {data:{repository:{c0:{associatedPullRequests:{nodes:[]}}}}};
    if (route.endsWith('/generate-notes')) return {body:"## What's Changed\n* Pull title to replace\n\n## New Contributors\n* @alice made their first contribution\n\n**Full Changelog:** old"};
    if (options.method === 'PATCH' && /\/releases\/\d+$/.test(route)) {
      const current = releases.find(item => item.id === Number(route.split('/').at(-1)));
      current.body = options.body.body;
      return current;
    }
    throw new Error(`Unexpected API request: ${route}`);
  };
  return {cwd,api,calls,releases};
}

describe('release summaries and full history', () => {
  it('freezes editorial text under the chosen tag without rewriting older entries', () => {
    const old = {summary:['Old release.'],previousTag:null};
    const frozen = JSON.parse(freezeSummary(JSON.stringify({'v1.0.0':old,Unreleased:{summary:['New feature.']}}),'v1.1.0','### Features\n- Fallback.','v1.0.0'));
    expect(frozen['v1.0.0']).toEqual(old);
    expect(frozen['v1.1.0']).toEqual({summary:['New feature.'],previousTag:'v1.0.0'});
    expect(frozen.Unreleased.summary).toEqual([]);
    expect(JSON.parse(freezeSummary('{}','v1.0.0','### Features\n- First.'))['v1.0.0'].summary).toEqual(['First.']);
    expect(() => parseSummaries('{"Unreleased":{"summary":["two\\nlines"]}}')).toThrow(/one-line/);
  });
  it('keeps paginated commits oldest first, excludes merges and lists each commit once', () => {
    const a = commit('a','feat: a\n\nFixes #12'), b = commit('b','fix: b'), merge = commit('c','Merge PR title','alice',[{},{}]);
    const ordered = rangeCommits('o/r','v1.0.0','v1.1.0',(_route, options) => {
      expect(options.paginate).toBe(true); return [{commits:[a]},{commits:[b,merge,a]}];
    });
    const pull = {number:8,closingIssuesReferences:{nodes:[{url:'https://github.com/o/r/issues/99'}]}};
    const lines = changeLines('o/r',ordered,{[a.sha]:pull,[b.sha]:pull});
    expect(lines).toHaveLength(2);
    expect(lines[0]).toContain('feat: a by @alice'); expect(lines[1]).toContain('fix: b');
    expect(lines.join('\n').match(/issues\/99/g)).toHaveLength(1);
    expect(lines[0]).toContain('issues/12'); expect(lines.join('\n')).not.toContain('Merge PR title');
    expect(closingIssues('Resolves other/repo#5; fixes https://github.com/third/repo/issues/7','o/r')).toEqual(['https://github.com/other/repo/issues/5','https://github.com/third/repo/issues/7']);
  });
  it('looks up PR metadata in bounded batches and rejects incomplete attribution', () => {
    const commits = Array.from({length:51},(_,i) => ({...commit('a','feat: x'),sha:i.toString(16).padStart(40,'0')}));
    const calls = [];
    expect(associatedPulls('o/r',commits,(_route,options) => { calls.push(options); return {data:{repository:{}}}; })).toEqual({});
    expect(calls).toHaveLength(2);
    expect(() => associatedPulls('o/r',[commits[0]],() => ({errors:[{message:'Denied'}]}))).toThrow(/attribution/);
  });
  it('preserves credits and comparison when a complete history exceeds the description limit', () => {
    const credits = contributorCredits("## What's Changed\r\n* generated pull title\r\n\r\n## New Contributors\r\n* @bob joined\r\n\r\n**Full Changelog:** old");
    const options = {repository:'o/r',tag:'v1.1.0',previousTag:'v1.0.0',summary:['User outcome.'],bannerUrl:'https://example.invalid/banner.svg',credits};
    const changes = Array.from({length:20},(_,i) => `* Commit ${i} ${'x'.repeat(90)}`);
    const notes = composeNotes({...options,changes,limit:900});
    expect(notes.length).toBeLessThanOrEqual(900);
    expect(notes.indexOf('Changes since last release:')).toBeLessThan(notes.indexOf("What's Changed"));
    expect(notes).toContain('@bob joined'); expect(notes).toContain('complete history');
    expect(notes).toContain('compare/v1.0.0...v1.1.0'); expect(notes).not.toContain('generated pull title');
    expect(composeNotes({...options,changes:[] })).not.toContain('remaining commits');
    expect(() => composeNotes({...options,summary:['x'.repeat(2000)],changes,limit:900})).toThrow(/Editorial/);
  });
});

describe('release banner and publication boundaries', () => {
  it('escapes editorial text in a deterministic standalone ShowRunner SVG', () => {
    const options = {tag:'v1.1.0',date:'2026-01-02',summary:['A <script> & "title"'],commits:4,contributors:2};
    const svg = renderBanner(options);
    expect(svg).toContain('ShowRunner'); expect(svg).toContain('&lt;script&gt; &amp; &quot;title&quot;');
    expect(svg).not.toContain('<script>'); expect(svg).toBe(renderBanner(options));
  });
  it('creates an orphan banner history and updates it without force or main writes', () => {
    for (const existing of [false,true]) {
      const calls = [];
      const api = (route,options = {}) => {
        calls.push({route,...options});
        if (route.includes('/git/ref/')) { if (!existing) { const error = new Error('Missing'); error.status=404; throw error; } return {object:{sha:sha('a')}}; }
        if (route.endsWith('/git/commits/' + sha('a'))) return {tree:{sha:sha('b')}};
        return {sha:sha('c')};
      };
      expect(publishBanner('o/r','v1.1.0','<svg/>',api)).toBe(`https://raw.githubusercontent.com/o/r/${sha('c')}/v1.1.0.svg`);
      const saved = calls.find(call => call.route.endsWith('/git/commits'));
      expect(saved.body.parents).toEqual(existing ? [sha('a')] : []);
      expect(calls.at(-1).body).toEqual(existing ? {sha:sha('c'),force:false} : {ref:'refs/heads/release-banners',sha:sha('c')});
      expect(JSON.stringify(calls)).not.toContain('refs/heads/main');
    }
    const denied = new Error('Denied'); denied.status=403;
    expect(() => publishBanner('o/r','v1.1.0','<svg/>',() => { throw denied; })).toThrow('Denied');
  });
  it('previews published releases without persistent GitHub writes and ignores drafts', () => {
    const f = fixture();
    const notes = runNotes(['--repo','o/r'],f);
    expect(notes).toHaveLength(1); expect(notes[0]).toContain('New commands.');
    expect(f.calls.some(call => call.method === 'PATCH' || call.route.includes('/git/'))).toBe(false);
    expect(() => runNotes(['--repo','o/r','--tag','v9.0.0','--write'],f)).toThrow(/drafts require/);
    const source = readFileSync(join(f.cwd,'docs/release-summaries.json'),'utf8');
    expect(source).toContain('Draft feature.');
  });
  it('updates only the body of an explicitly selected draft and is idempotent', () => {
    const f = fixture();
    const args = ['--repo','o/r','--tag','v9.0.0','--include-draft','--write'];
    runNotes(args,f); runNotes(args,f);
    const writes = f.calls.filter(call => call.method === 'PATCH');
    expect(writes).toHaveLength(1); expect(Object.keys(writes[0].body)).toEqual(['body']);
    expect(f.releases[2].draft).toBe(true);
    expect(writes[0].body.body).toContain('compare/v1.1.0...v9.0.0');
  });
});
