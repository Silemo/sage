## Summary
Apply the three reviewer-approved follow-up fixes: align the README title with SAGE branding, make the requirements test runner collect all failures before exiting non-zero, and replace hardcoded event-count assertions with behavior-driven checks that survive data changes.

## Steps

### Step 1: Fix the README heading
- **File**: `README.md` (modify)
- **Changes**: Replace the top-level heading `# pi-planning-v2` with `# SAGE`.
- **Rationale**: This completes the branding change already applied everywhere else and closes the partial implementation gap from plan step 6.
- **Tests**: Open the README and confirm the H1 matches the product name shown in the app shell.
- **Commit message**: `docs(readme): align title with sage branding`

### Step 2: Make the requirements test runner report all failures
- **File**: `tests/sage-spec-requirements.mjs` (modify)
- **Changes**: Update `runTest()` so it records a failing result without re-throwing. After all tests run, compute `failCount` from `results` and call `process.exit(failCount > 0 ? 1 : 0)` after printing the summary.
- **Rationale**: A failing test should not prevent later requirements checks from running; CI still needs a non-zero exit code when any test fails.
- **Tests**: Run the suite once normally to confirm it still exits `0` when all tests pass. Optionally force one assertion to fail locally and confirm the script prints later test results before exiting non-zero.
- **Commit message**: `test(requirements): collect all failures before exiting`

### Step 3: Remove hardcoded dataset-size expectations
- **File**: `tests/sage-spec-requirements.mjs` (modify)
- **Changes**: Replace the `=== 72` assertions in the JSON fallback and missing-source resilience tests with behavior-driven checks.
- **Changes**: For the JSON fallback test, assert zero load errors, assert `result.events.length > 0`, assert every event source starts with `data/json/`, and assert both configured dates are present.
- **Changes**: For the missing-source resilience test, compute the baseline result from the unmodified `sources.json`, then assert the augmented source run returns the same event count as the baseline, still reports exactly one missing-source error, and still includes day 2 events.
- **Rationale**: The tests should validate loader behavior, not the exact current number of committed schedule rows.
- **Tests**: Run the requirements suite and confirm it passes against the current data without relying on a magic number.
- **Commit message**: `test(requirements): make loader assertions data-independent`

## Testing Approach
Run from the repo root:

```powershell
npx http-server . -p 8000
node .\tests\sage-spec-requirements.mjs
```

Optional regression check:

```powershell
# with the server still running
# open http://127.0.0.1:8000/test.html in a browser or re-run the existing smoke flow if available
```

## Handoff

**Artifact saved**: `artifacts/2026-03-23-sage-review-followups-plan.md`

**Upstream artifacts**:
- Requirements: `artifacts/2026-03-17-schedule-requirements.md`
- Architecture: `artifacts/2026-03-19-sage-branding-data-reorg-architecture.md`
- Plan: `artifacts/2026-03-19-sage-branding-data-reorg-plan.md`
- Implementation: `artifacts/2026-03-19-sage-branding-data-reorg-implementation.md`
- Test report: `artifacts/2026-03-19-sage-branding-data-reorg-test-report.md`
- Review report: `artifacts/2026-03-23-sage-branding-data-reorg-review-report.md`

**Context for @ema-implementer-lite**:
- 3 steps to execute
- Files affected: `README.md`, `tests/sage-spec-requirements.mjs`
- Test command: `npx http-server . -p 8000` and `node .\tests\sage-spec-requirements.mjs`
- Watch for: keep the test script exit code non-zero on any failure; do not reintroduce hardcoded event totals; `tests/requirements.spec.mjs` is out of scope unless the user explicitly asks to resolve its untracked status

> 📋 **Model**: Select **Gemini 3 Flash** before invoking `@ema-implementer-lite`

**What @ema-implementer-lite should do**:
1. Read the plan artifact at `artifacts/2026-03-23-sage-review-followups-plan.md`
2. Apply the README and test-file changes in order, staging changes but not committing
3. Run `node .\tests\sage-spec-requirements.mjs` against a local static server and confirm the suite still passes
4. Save the implementation summary to `artifacts/2026-03-23-sage-review-followups-implementation.md`
