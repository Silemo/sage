## Completed Steps
- [x] Step 1: Fixed README heading branding — changed `README.md` H1 from `pi-planning-v2` to `SAGE`; changes staged
- [x] Step 2: Updated the requirements test runner to collect failures before exiting — removed the re-throw in `runTest()` and added a final `process.exit(failCount > 0 ? 1 : 0)`; changes staged
- [x] Step 3: Removed hardcoded loader dataset-size expectations — replaced the two `=== 72` assertions with behavior-driven checks using `> 0` and a baseline loader result; changes staged

## Skipped / Blocked Steps
- [ ] Optional regression check in `test.html` — not run because the plan marked it optional and the required `node .\tests\sage-spec-requirements.mjs` suite already passed

## Deviations from Plan
- None

## Test Results
- `node .\tests\sage-spec-requirements.mjs`: 5 passed, 0 failed, 0 skipped
- Static server command used for the suite: `npx http-server . -p 8000`
- Editor diagnostics: no errors in `tests/sage-spec-requirements.mjs`

## Notes for Reviewer
- The requirements test script now reports all test outcomes before exiting non-zero on failure, which makes future CI failures easier to diagnose.
- The JSON fallback and missing-source resilience tests now validate loader behavior without depending on the current committed row count.
- `tests/requirements.spec.mjs` remains untracked and untouched, per plan scope.

## Handoff

**Artifact saved**: `artifacts/2026-03-23-sage-review-followups-implementation.md`

**Upstream artifacts**:
- Requirements: `artifacts/2026-03-17-schedule-requirements.md`
- Architecture: `artifacts/2026-03-19-sage-branding-data-reorg-architecture.md`
- Plan: `artifacts/2026-03-23-sage-review-followups-plan.md`
- Review report: `artifacts/2026-03-23-sage-branding-data-reorg-review-report.md`

**Context for @ema-tester**:
- Steps completed: 3 / 3 total
- Steps blocked: none
- Files changed:
  - `README.md` (modified) — aligned the H1 with shipped SAGE branding
  - `tests/sage-spec-requirements.mjs` (modified) — changed the runner to collect failures before exit and replaced hardcoded event-count assertions with data-independent behavior checks
- Existing tests location: `tests/sage-spec-requirements.mjs`, `test.html`
- Test suite command: `npx http-server . -p 8000` and `node .\tests\sage-spec-requirements.mjs`
- Current suite result: 5 passed, 0 failed, 0 skipped
- Deviations from plan: none
- Spec to test against: `artifacts/2026-03-23-sage-review-followups-plan.md`
- Areas needing extra coverage: verify the runner exits non-zero while still printing later test results when one test fails; decide separately whether the untracked `tests/requirements.spec.mjs` should be retained or removed

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-tester`

**What @ema-tester should do**:
1. Read the plan artifact at `artifacts/2026-03-23-sage-review-followups-plan.md`
2. Read this implementation summary to understand the exact follow-up changes
3. Re-run `node .\tests\sage-spec-requirements.mjs` against a local static server
4. Add a targeted regression check that confirms the script still exits non-zero while continuing past an early failure, if practical without destabilizing the suite
5. Save the test report to `artifacts/2026-03-23-sage-review-followups-test-report.md`
