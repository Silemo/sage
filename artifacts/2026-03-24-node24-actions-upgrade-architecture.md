# Architecture Design: GitHub Actions Node.js 24 Upgrade

## Summary

GitHub Actions runners are deprecating Node.js 20 (enforced June 2, 2026). The Sage project's two workflow files use four actions pinned to Node.js 20 versions, causing deployment warnings. The fix combines version bumps for actions that have Node.js 24 releases with a runner environment variable for actions that don't yet have updated releases.

## Post-Implementation Analysis (2026-03-24)

The architecture plan was implemented correctly. The `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` env var is working — actions **do** execute on Node.js 24. However, a pre-flight GitHub Actions warning still appears. This section explains why.

### The warning persists — but is cosmetic

After implementation, the workflow still shows:
```
Warning: Node.js 20 actions are deprecated. The following actions are running on Node.js 20:
actions/configure-pages@v5, actions/deploy-pages@v4, actions/upload-artifact@ea165f8d...
```

This is a **pre-flight informational warning** emitted by GitHub Actions before any action executes. GitHub scans all action manifests at workflow start time and lists any that declare `node20` as their runtime in `action.yml`. This warning is emitted *before* consulting the `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` env var — it reflects manifest declarations, not actual runtime.

### Proof that Node.js 24 IS the actual runtime

The `deploy-pages@v4` log shows:
```
(node:2350) [DEP0040] DeprecationWarning: The `punycode` module is deprecated.
```
The `punycode` module deprecation was introduced in Node.js 21. Its presence **proves** the action is running on Node.js 24. On Node.js 20, this warning would not appear.

### Transitive dependency: `actions/upload-artifact`

The warning mentions `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02` — this action is **not** in our workflow files. It is an internal transitive dependency of `actions/upload-pages-artifact@v4`, which pins `upload-artifact` by SHA in its own implementation. This cannot be fixed by the user; the `upload-pages-artifact` maintainers must update their internal dependency.

### Conclusion

| Aspect | Status |
|--------|--------|
| Actions actually running on Node.js 24 | **Yes** (proven by punycode deprecation warning) |
| Pre-flight warning eliminable by user | **No** — based on action manifest declarations, not runtime |
| Risk to June 2 deadline | **None** — runtime is already Node.js 24 |
| Warning will resolve when... | Action maintainers release Node 24-native versions of `configure-pages`, `deploy-pages`, and `upload-pages-artifact` updates its internal `upload-artifact` dependency |

**No further action required.** The implementation is complete and working correctly. The cosmetic warning is outside user control.

## Codebase Context

Two workflow files exist:

- **`.github/workflows/static.yml`** — deploys static content to GitHub Pages on push to `main`. Uses four actions:
  - `actions/checkout@v4` (Node.js 20)
  - `actions/configure-pages@v5` (Node.js 20)
  - `actions/upload-pages-artifact@v3` (Node.js 20)
  - `actions/deploy-pages@v4` (Node.js 20)

- **`.github/workflows/copilot-setup-steps.yml`** — prepares the Copilot coding agent environment. Uses:
  - `actions/checkout@v4` (Node.js 20)

### Latest Available Versions (verified from GitHub releases/tags pages, March 24 2026)

| Action | Current | Latest Release | Node.js 24 Native? |
|--------|---------|---------------|---------------------|
| `actions/checkout` | `@v4` | `@v6` (v6.0.2, Jan 2026) | **Yes** (v5+ uses Node.js 24) |
| `actions/configure-pages` | `@v5` | `@v5` (v5.0.0, Mar 2024) | **No** — no newer version exists |
| `actions/upload-pages-artifact` | `@v3` | `@v4` (v4.0.0, Aug 2025) | **Yes** |
| `actions/deploy-pages` | `@v4` | `@v4` (v4.0.5, Mar 2024) | **No** — no newer version exists |

## Design Approaches Considered

### Approach A: Bump available versions + set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` ⭐ (recommended)

- **Description**: Upgrade `actions/checkout` to `@v6` and `actions/upload-pages-artifact` to `@v4` (both have native Node.js 24 support). For `actions/configure-pages@v5` and `actions/deploy-pages@v4` (no Node.js 24 releases available), set the `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` environment variable at the workflow level to force Node.js 24 runtime.
- **Pros**: Uses native Node.js 24 where possible; environment variable covers the gap; ensures all actions actually run on Node.js 24; forward-compatible with the June 2 deadline; minimal risk since GitHub-hosted runners support all required versions. **Note**: a cosmetic pre-flight warning will still appear for actions whose manifests declare `node20` — this is informational only and does not affect runtime.
- **Cons**: Two actions still rely on the environment variable workaround until their maintainers release Node.js 24 versions; `upload-pages-artifact@v4` has a breaking change (dotfiles excluded from artifacts by default, which is fine for this static site); pre-flight warning persists until action maintainers update manifests

### Approach B: Only set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` environment variable

- **Description**: Keep all action versions unchanged. Set the environment variable at workflow level to force all actions to run on Node.js 24 regardless of their declared runtime.
- **Pros**: Single-line change; no version compatibility concerns; quick to implement
- **Cons**: Leaves actions on older versions missing bug fixes and improvements; when `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` is eventually removed, you'll need to upgrade versions anyway; doesn't get the security/credential improvements in `checkout@v6`

### Approach C: Bump to latest versions only (no environment variable)

- **Description**: Upgrade checkout to `@v6` and upload-pages-artifact to `@v4`, but don't set the environment variable.
- **Pros**: Uses newest versions; no workaround needed for two of four actions
- **Cons**: **Does not eliminate warnings** — `configure-pages@v5` and `deploy-pages@v4` will still trigger Node.js 20 deprecation warnings since they have no Node.js 24 releases; incomplete fix

## Chosen Design

**Approach A** — bump available versions + set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24`. This is the most thorough fix: it adopts native Node.js 24 where releases exist, and uses the GitHub-recommended environment variable for the remaining actions. It ensures all actions actually execute on Node.js 24 and positions the project well ahead of the June 2 deadline. A cosmetic pre-flight warning will persist until action maintainers release Node 24-native manifests — this is informational only and outside user control.

### Components

Two workflow files require changes:

1. **`.github/workflows/static.yml`** — the Pages deployment workflow (primary target)
2. **`.github/workflows/copilot-setup-steps.yml`** — the Copilot agent environment setup

### Changes Required

#### `static.yml`

1. Add `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` as a top-level `env:` block (applies to all jobs/steps)
2. Update `actions/checkout@v4` → `actions/checkout@v6`
3. Update `actions/upload-pages-artifact@v3` → `actions/upload-pages-artifact@v4`
4. Keep `actions/configure-pages@v5` as-is (no newer version; env var forces Node.js 24)
5. Keep `actions/deploy-pages@v4` as-is (no newer version; env var forces Node.js 24)

#### `copilot-setup-steps.yml`

1. Update `actions/checkout@v4` → `actions/checkout@v6`
2. Optionally add the `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` env var for future-proofing (currently only checkout is used, but if new steps are added later, they'd be covered)

### Data Flow

No data flow changes — the deployment pipeline behavior is identical. The only difference is the Node.js runtime version used to execute the action JavaScript.

### Integration Points

- **`static.yml`** lines 33-42: the four `uses:` directives
- **`copilot-setup-steps.yml`** line 27: the checkout `uses:` directive
- **GitHub-hosted runners**: `ubuntu-latest` already ships with runner version ≥ v2.329.0 (required by `checkout@v6`)

### Breaking Change Notes

- **`actions/checkout@v6`**: Persists credentials to `$RUNNER_TEMP` instead of the local git config. Requires runner ≥ v2.329.0. No impact on `ubuntu-latest` (always up to date). The Sage workflow only checks out code for static deployment — no git operations after checkout — so this change is transparent.
- **`actions/upload-pages-artifact@v4`**: Dotfiles (files starting with `.`) are no longer included in the artifact by default. The Sage project has `.github/`, `.metrics/`, and `.gitignore` which would be excluded, but these are not part of the deployed website content. This change is actually beneficial — it reduces artifact size.

## Error Handling

No error handling changes needed. If an action fails to run on Node.js 24, the workflow will fail with a clear error message in the Actions log. The `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` variable is the GitHub-recommended opt-in mechanism and is well-tested.

## Testing Strategy

- **Manual verification**: After merging, trigger a workflow run (push to `main` or manual dispatch) and verify:
  1. The GitHub Pages site deploys successfully
  2. The site content is correct (no missing assets due to the dotfiles exclusion)
  3. Actions are running on Node.js 24 (confirm by checking for `punycode` deprecation warning in action logs — its presence proves Node 24 runtime)
  4. **Note**: The pre-flight Node.js 20 deprecation warning will still appear — this is a cosmetic warning based on action manifest declarations, not actual runtime. It cannot be eliminated until action maintainers release Node 24-native versions.
- **Copilot workflow**: Trigger a manual dispatch of `copilot-setup-steps.yml` to verify checkout works with `@v6`

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `configure-pages@v5` or `deploy-pages@v4` break on forced Node.js 24 | Low — GitHub recommends this env var | Revert the env var if issues occur; these actions are simple API wrappers |
| `checkout@v6` credential changes cause issues | Very low — Sage has no post-checkout git operations | Fall back to `@v5` (also Node.js 24 native) if needed |
| `upload-pages-artifact@v4` dotfile exclusion removes needed content | Very low — static site doesn't need dotfiles | No dotfiles are part of the deployed website |
| `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` env var deprecated later | Expected — once all actions support Node.js 24 natively | Remove env var when `configure-pages` and `deploy-pages` release Node.js 24 versions |

## Handoff

**Artifact saved**: `artifacts/2026-03-24-node24-actions-upgrade-architecture.md`

**Path signal**: unexpectedly simple (localized change, no new abstractions) → consider @ema-planner-lite instead

> 📋 **Model**: Select **Gemini 3 Flash** before invoking `@ema-planner-lite`

**Upstream artifacts**:
- None (issue originated from GitHub Actions deployment warning)

**Context for @ema-planner**:
- Chosen approach: Bump available action versions to Node.js 24 native + set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` for remaining actions
- Files to create: none
- Files to modify: `.github/workflows/static.yml` (update 2 action versions, add env block), `.github/workflows/copilot-setup-steps.yml` (update 1 action version)
- Key integration points: `static.yml` uses directives at lines 33-42; `copilot-setup-steps.yml` checkout at line 27
- Testing strategy: manual — trigger workflow dispatch, verify no warnings and site deploys correctly
- Conventions to follow: YAML formatting consistent with existing workflow files; use major version tags (`@v6` not `@v6.0.2`)

**Files the planner must verify exist before writing the plan**:
- `.github/workflows/static.yml` — the primary deployment workflow to modify
- `.github/workflows/copilot-setup-steps.yml` — the Copilot setup workflow to modify

**What @ema-planner should do**:
1. Read this architecture artifact at the path above
2. Verify the listed files exist and match the descriptions
3. Produce a step-by-step plan with exact file paths, version changes, and commit messages
4. Save plan to `artifacts/2026-03-24-node24-actions-upgrade-plan.md`
