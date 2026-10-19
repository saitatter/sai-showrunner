import { describe, expect, it } from 'vitest';
import { findMainCi, verifiedMainCi } from './ci-proof.mjs';

const commit = 'a'.repeat(40);
const repository = 'owner/showrunner';
const run = { id: 12, status: 'completed', conclusion: 'success', event: 'push', head_branch: 'main', head_sha: commit, path: '.github/workflows/ci.yml', repository: { full_name: repository }, head_repository: { full_name: repository } };
const jobs = ['test-windows', 'windows-build', 'windows-integration', 'scripts-ubuntu', 'release-dry-run'].map(name => ({ name, status: 'completed', conclusion: 'success' }));

describe('trusted main CI proof', () => {
  it('reuses only the exact successful main commit with all gates passed', () => {
    const routes = [];
    expect(findMainCi(commit, repository, route => {
      routes.push(route);
      return route.includes('/jobs?') ? { jobs } : { workflow_runs: [run] };
    })).toBe(12);
    expect(routes[0]).toContain(`head_sha=${commit}`);
    expect(routes[1]).toContain('filter=latest');
  });
  it.each([
    { event: 'pull_request' }, { event: 'workflow_call' }, { head_branch: 'feature' },
    { head_sha: 'b'.repeat(40) }, { path: '.github/workflows/other.yml' },
    { status: 'in_progress' }, { conclusion: 'failure' }, { conclusion: 'cancelled' },
    { repository: { full_name: 'fork/showrunner' } }, { head_repository: { full_name: 'fork/showrunner' } },
    { id: -1 },
  ])('rejects untrusted or incomplete run metadata: %j', changes => {
    expect(verifiedMainCi({ ...run, ...changes }, jobs, commit, repository)).toBe(false);
  });
  it('requires every gate even when the summary reports success', () => {
    for (const name of jobs.map(job => job.name)) {
      expect(verifiedMainCi(run, jobs.filter(job => job.name !== name), commit, repository)).toBe(false);
      for (const conclusion of ['failure', 'cancelled', 'skipped', 'neutral']) {
        expect(verifiedMainCi(run, jobs.map(job => job.name === name ? { ...job, conclusion } : job), commit, repository)).toBe(false);
      }
    }
  });
  it('requires fresh CI when no successful main run exists', () => {
    expect(findMainCi(commit, repository, () => ({ workflow_runs: [] }))).toBeNull();
  });
  it('rejects malformed API inputs before requesting anything', () => {
    for (const [sha, repo] of [['main', repository], [commit, '../other?repo']]) {
      expect(() => findMainCi(sha, repo, () => { throw new Error('Unexpected API request'); })).toThrow('Expected a full planned commit');
    }
  });
});
