## Completed Steps
- [x] Step 1: Broadened scope filtering to include shared `ALL` value-stream events in `plenary`, `vs`, and existing team views — changes staged
- [x] Step 2: Updated the focused requirements regression to encode the new Scope filter contract for shared `ALL` events — changes staged
- [x] Step 3: Added committed-data regression coverage for real CSV schedule behavior — changes staged

## Skipped / Blocked Steps
- [ ] Manual browser verification — not run from this terminal-only flow; automated regression coverage passed, but the plan's UI smoke check still remains available for manual validation

## Deviations from Plan
- Updated the existing legacy JSON regression in [tests/name-teams-decoupling-spec.mjs](c:/Users/manfredig/IdeaProjects/sage/tests/name-teams-decoupling-spec.mjs) so it reads the committed JSON file directly through `normalizeRecord(...)` instead of `loadAllSources(config/sources.json)`. This was necessary because the current source loader prefers CSV when both CSV and JSON exist for `2026-03-18`, so the previous test no longer exercised legacy JSON fallback behavior even before this change.

## Test Results
- `node tests/requirements.spec.mjs`: 7 passed, 0 failed
- `node tests/name-teams-decoupling-spec.mjs`: 5 passed, 0 failed
- Primary plan verification command `node tests/requirements.spec.mjs; node tests/name-teams-decoupling-spec.mjs`: passed end to end

## Notes for Reviewer
- The production change is intentionally narrow and confined to [js/filter.js](c:/Users/manfredig/IdeaProjects/sage/js/filter.js); no dropdown structure, loader behavior, or committed schedule data was changed
- `Plenary` scope now means `event.vs === "ALL"`, not `event.type === "Plenary"`
- `All [VS]` scope now includes both the selected value stream and shared `ALL` events, which matches the requested behavior for items like Coffee break and Lunch
- Team scope still includes shared `ALL` events and teamless cards; the existing team-filter behavior remains intact

## Handoff

**Artifact saved**: `artifacts/2026-03-24-scope-filter-all-events-implementation.md`

**Upstream artifacts**:
- Plan: `artifacts/2026-03-24-scope-filter-all-events-plan.md`
- Architecture: none
- Requirements: none

**Context for @ema-tester**:
- Steps completed: 3 / 3 total
- Steps blocked: none
- Files changed:
  - `js/filter.js` — added a shared `ALL` value-stream helper and updated scope predicates so `plenary` and `vs` include shared `ALL` events consistently
  - `tests/requirements.spec.mjs` — updated the focused scope regression to cover `Plenary`, `All PLM`, and search-within-shared-scope behavior
  - `tests/name-teams-decoupling-spec.mjs` — added committed-data coverage for `Plenary` and `All MON` scope behavior; corrected the stale legacy JSON regression harness to read committed JSON directly
- Existing tests location: `tests/requirements.spec.mjs`, `tests/name-teams-decoupling-spec.mjs`
- Test suite command: `node tests/requirements.spec.mjs; node tests/name-teams-decoupling-spec.mjs`
- Current suite result: 12 passed, 0 failed, 0 skipped
- Deviations from plan: fixed the stale legacy JSON regression harness in `tests/name-teams-decoupling-spec.mjs` so the primary test command reflects current CSV-preferred source loading while still covering legacy JSON normalization
- Areas needing extra coverage: manual browser verification for `2026-03-17` Scope selections (`Plenary`, `All MON`) to confirm the UI matches the automated filter results

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-tester`

**What @ema-tester should do**:
1. Read the plan artifact first, then this implementation summary
2. Validate the new scope behavior from the requested contract rather than only from the updated tests
3. Re-run `node tests/requirements.spec.mjs; node tests/name-teams-decoupling-spec.mjs`
4. Add any missing tests for edge cases around shared `ALL` events, especially search interactions and value-stream exclusions
5. Perform the manual browser smoke check for `2026-03-17` Scope selections if environment access allows
6. Save the test report to `artifacts/2026-03-24-scope-filter-all-events-test-report.md`