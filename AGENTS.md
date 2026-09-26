## Agent skills

### Issue tracker

GitHub Issues is the issue tracker for this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the canonical Matt triage label vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain layout. See `docs/agents/domain.md`.

## CI runners

Local workers, meaning agents running on the owner's Mac, must not spend GitHub Actions runner minutes on checks they can run locally. Only cloud-based and GitHub-hosted agents use the runners.

- Run the gates locally: `npm test`, `swift test`, both `swift build --target` view builds, and the unsigned Xcode Debug and Release builds listed in the README. Report those results.
- Put `[skip ci]` in every commit message you push, including merge commits (`gh pr merge --subject "... [skip ci]"`). It skips push and pull_request workflows.
- Cancel duplicate runs that a push or merge starts anyway (`gh run cancel`).
- When branch protection requires the CI check, merge with the owner's admin bypass (`gh pr merge --admin`) after the local gates pass, and say so in the PR.
