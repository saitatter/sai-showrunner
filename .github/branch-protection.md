# Branch Protection

Protect `main` in GitHub repository settings with these rules:

- Require a pull request before merging.
- Require branches to be up to date before merging.
- Require conversation resolution before merging.
- Require linear history and squash merges for feature PRs.
- Restrict direct pushes to `main`.
- Require these status checks:
  - `test-windows`
  - `scripts-ubuntu`
  - `release-dry-run`
- Keep releases gated by the `Release` workflow:
  - `package-windows-preflight` must pass before semantic-release creates a draft release.
  - `package-windows` must smoke packaged artifacts, upload assets, and publish the draft release.

The release workflow intentionally creates draft GitHub releases first. The draft is only published after Windows assets are built, smoke-checked, uploaded, and verified to exclude `builder-debug.yml`.
