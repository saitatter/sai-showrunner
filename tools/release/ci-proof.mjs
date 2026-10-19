import { execFileSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function verifiedMainCi(run, jobs, commit, repository) {
  const required = ['test-windows', 'windows-build', 'windows-integration', 'scripts-ubuntu', 'release-dry-run'];
  return run.status === 'completed' && run.conclusion === 'success' &&
    run.event === 'push' && run.head_branch === 'main' && run.head_sha === commit &&
    run.path === '.github/workflows/ci.yml' && Number.isSafeInteger(run.id) && run.id > 0 &&
    run.repository?.full_name === repository && run.head_repository?.full_name === repository &&
    required.every(name => jobs.some(job => job.name === name && job.status === 'completed' && job.conclusion === 'success'));
}

export function findMainCi(commit, repository, api) {
  if (!/^[a-f0-9]{40}$/.test(commit) || !/^[\w.-]+\/[\w.-]+$/.test(repository)) {
    throw new Error('Expected a full planned commit and owner/repository.');
  }
  const query = `repos/${repository}/actions/workflows/ci.yml/runs?branch=main&event=push&status=success&head_sha=${commit}&per_page=10`;
  for (const run of api(query).workflow_runs ?? []) {
    if (!Number.isSafeInteger(run.id) || run.id <= 0) continue;
    const jobs = api(`repos/${repository}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`).jobs ?? [];
    if (verifiedMainCi(run, jobs, commit, repository)) return run.id;
  }
  return null;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const commit = process.env.PLANNED_COMMIT ?? '';
  const repository = process.env.GITHUB_REPOSITORY ?? '';
  let runId = null;
  try {
    runId = findMainCi(commit, repository, route => JSON.parse(execFileSync('gh', ['api', route], { encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'] })));
  } catch {
    // Missing permissions, API errors and incomplete proofs all require fresh CI.
    process.stdout.write('No reusable main CI proof available; running full validation.\n');
  }
  if (runId) process.stdout.write(`Reusing main CI run ${runId} for ${commit}.\n`);
  else process.stdout.write('Fresh CI validation is required.\n');
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `reuse=${Boolean(runId)}\n`);
}
