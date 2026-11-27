# Repository rulesets

`main-branch.json` is the reference copy of the `main branch` ruleset (Settings → Rules → Rulesets) that protects the
default branch. GitHub does not read this file; the live ruleset is edited in the UI and this copy is kept in sync by hand.

## What it enforces

- `main` cannot be deleted or force-pushed.
- Every change goes through a pull request; no approvals are required.
- Two status checks must pass: `App build (Debug, simulator)` and `ToriKit (macOS)` from `.github/workflows/ios.yml`.
  Their names must match the job `name:` values in that workflow. `ios.yml` runs on every pull request and skips both
  jobs when the PR touches no iOS paths; a skipped job counts as passed.
- Merge, squash and rebase merges are allowed. No bypass actors.

## Why "Require branches to be up to date" is off

With it on, every merge makes all other open pull requests out of date. Each then needs a manual "Update branch" before
it can merge, so pull requests opened by automation cannot merge on their own. A personal-account repository has no
merge queue.

Accepted risk: a push to `main` runs no tests. `ios.yml` only builds the app on `main`, and only when iOS paths change.
Two pull requests that pass separately but break the build or tests once combined are not caught on `main`; the checks
of the next iOS pull request catch them.

`require_extra_approval_for_unattributed_changes` is also off: no approvals are required, so it adds nothing here.

## Applying a change

- Preferred: edit the existing `main branch` ruleset in the UI, then update this file to match.
- Importing this file (Rulesets → New ruleset → Import) creates a second ruleset. Active rulesets add up, so delete the
  old one afterwards. Exactly one active ruleset must target the default branch.
