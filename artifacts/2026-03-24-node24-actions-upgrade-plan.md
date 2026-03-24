## Summary
Implement the GitHub Actions Node.js 24 migration described in [artifacts/2026-03-24-node24-actions-upgrade-architecture.md](c:/Users/manfredig/IdeaProjects/sage/artifacts/2026-03-24-node24-actions-upgrade-architecture.md) so the GitHub Pages deployment workflow stops raising Node.js 20 deprecation warnings. The fix is intentionally small and localized: update the action versions that already have Node.js 24-native releases, and set the GitHub-recommended `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` environment variable to force Node.js 24 for the two Pages actions that do not yet have newer releases.

## Steps

### Step 1: Update the Pages deployment workflow for Node.js 24
- **File**: `.github/workflows/static.yml` (modify)
- **Changes**:
  - Add a top-level `env:` block after `concurrency:` and before `jobs:` with:
    - `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`
  - Keep the existing trigger, permissions, and concurrency settings unchanged.
  - Update the `Checkout` step from `actions/checkout@v4` to `actions/checkout@v6`.
  - Keep `actions/configure-pages@v5` unchanged because `v5` is still the latest release.
  - Update the `Upload artifact` step from `actions/upload-pages-artifact@v3` to `actions/upload-pages-artifact@v4`.
  - Keep `actions/deploy-pages@v4` unchanged because `v4` is still the latest release.
  - Do not change the artifact `path: '.'` or any job names, permissions, or deployment environment wiring.
- **Rationale**: This workflow is the direct source of the GitHub Pages warning. `checkout@v6` and `upload-pages-artifact@v4` move two steps to native Node.js 24 support, while the workflow-level env var eliminates the warning for `configure-pages@v5` and `deploy-pages@v4` until their maintainers ship Node.js 24-native releases.
- **Tests**:
  - Validate the YAML structure visually after editing so `env:` remains top-level and not nested under `concurrency:` or `jobs:`.
  - Trigger the workflow through `workflow_dispatch` or by pushing to `main`.
  - Confirm the run completes successfully.
  - Confirm the deprecation warning about Node.js 20 no longer appears in the workflow log.
  - Confirm the Pages deployment still publishes the site successfully.
- **Commit message**: `ci(pages): move deployment workflow onto node 24 actions`

### Step 2: Update the Copilot setup workflow checkout action
- **File**: `.github/workflows/copilot-setup-steps.yml` (modify)
- **Changes**:
  - Update the `Checkout repository` step from `actions/checkout@v4` to `actions/checkout@v6`.
  - Preserve the workflow trigger (`workflow_dispatch`), required job name (`copilot-setup-steps`), and all surrounding comments.
  - Do not remove the `# AUTO-GENERATED` banner or alter the scaffold comments in this planning scope.
  - Do not add extra setup steps or unrelated dependency installation.
  - Leave the workflow without an `env:` block unless implementation reveals a concrete need to keep the Node.js 24 forcing behavior consistent across all future JavaScript actions in this workflow. The architecture marked that addition as optional, not required.
- **Rationale**: This workflow still uses a Node.js 20-based checkout action and will start warning or be auto-migrated by GitHub later. Updating it now keeps the repository’s automation aligned on the current supported runtime without expanding the scope beyond the single checkout step.
- **Tests**:
  - Trigger `Copilot Setup Steps` manually from the Actions tab.
  - Confirm the checkout step succeeds with `actions/checkout@v6`.
  - Confirm no other behavior changes occur in the workflow.
- **Commit message**: `ci(copilot): upgrade setup workflow checkout action`

## Testing Approach
There is no repo-local automated test suite for GitHub Actions workflows in this project, so verification is workflow-based.

1. Review both YAML files after editing to confirm indentation and top-level keys are valid.
2. Run the Pages workflow:
   - Use the existing `workflow_dispatch` trigger in `.github/workflows/static.yml` or merge/push to `main`.
   - Verify the deployment succeeds.
   - Verify the warning about Node.js 20 deprecation is gone.
3. Run the Copilot setup workflow:
   - Manually dispatch `.github/workflows/copilot-setup-steps.yml`.
   - Verify the checkout step completes successfully with `actions/checkout@v6`.
4. Smoke-check the deployed Pages site after the successful deployment run to confirm static content is still served correctly.

## Handoff

**Artifact saved**: `artifacts/2026-03-24-node24-actions-upgrade-plan.md`

**Upstream artifacts**:
- Architecture: `artifacts/2026-03-24-node24-actions-upgrade-architecture.md`
- Requirements: none (user request in conversation)

**Context for @ema-implementer**:
- 2 steps to execute.
- Files to create: none.
- Files to modify: `.github/workflows/static.yml`, `.github/workflows/copilot-setup-steps.yml`.
- Test command: no local automated test command; validate by manually dispatching both GitHub Actions workflows after the YAML changes.
- Test framework: GitHub Actions runtime validation plus successful workflow execution in GitHub-hosted runners.
- Watch for:
  - In `.github/workflows/static.yml`, `env:` must be top-level, not nested under `concurrency:` or the `deploy` job.
  - `actions/configure-pages@v5` and `actions/deploy-pages@v4` must remain on their current major versions because no newer Node.js 24-native releases were found.
  - `actions/upload-pages-artifact@v4` excludes dotfiles by default; that is acceptable for this static site because dotfiles are not part of the published Pages output.
  - `.github/workflows/copilot-setup-steps.yml` is scaffold-generated; keep the required job name `copilot-setup-steps` and preserve the banner/comments unless the user explicitly asks for cleanup.
  - Use major tags exactly as planned: `actions/checkout@v6` and `actions/upload-pages-artifact@v4`.

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-implementer`

**What @ema-implementer should do**:
1. Read this plan artifact at the path above.
2. Read [artifacts/2026-03-24-node24-actions-upgrade-architecture.md](c:/Users/manfredig/IdeaProjects/sage/artifacts/2026-03-24-node24-actions-upgrade-architecture.md) for design intent only.
3. Modify the two workflow files exactly as planned, keeping the change set narrow.
4. Validate the YAML carefully, then run the workflow verification steps in GitHub Actions.
5. Document any deviations and save the implementation summary to `artifacts/2026-03-24-node24-actions-upgrade-implementation.md`.
