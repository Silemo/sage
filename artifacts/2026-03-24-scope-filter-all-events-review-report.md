## Summary
Request Changes — one warning-level issue in the test code; the production change itself is correct and well-scoped.

## Findings

### Warning

- **tests/name-teams-decoupling-spec.mjs (legacy JSON test — `normalizeRecord` mapping)**: `assert.equal(result.errors.length, 0)` is placed inside a `.filter()` callback, coupling assertion side-effects to functional filtering. If any record produces a normalization error, the `assert.equal` throws inside `.filter()`, which propagates as a confusing exception rather than a clean, readable test failure — the `runTest` wrapper will catch it, but the stack trace points into the pipeline rather than an explicit assertion line. → Replace with a two-pass pattern: map all records first, then iterate to assert zero errors, then filter and map to `record`:
  ```js
  const normalizeResults = jsonRecords.map(
    (record) => normalizeRecord(record, "data/json/2026-03-18.json", "2026-03-18")
  );
  normalizeResults.forEach((result) => assert.equal(result.errors.length, 0));
  const normalized = normalizeResults
    .filter((result) => result.record)
    .map((result) => result.record);
  ```

- **tests/sage-spec-requirements.mjs**: Two pre-existing stale test assertions (unrelated to this scope-filter change) are keeping the full suite red at 21/25 PASS:
  1. `"loader accepts committed CSV data and keeps legacy JSON fallback compatible"` asserts `jsonEvents.length > 0`, but day-two now loads from CSV not JSON. → Either point the test at a known JSON-only fixture, or adjust the assertion to cover CSV-loaded day-two events.
  2. `"loader skips malformed committed CSV rows without aborting the schedule"` asserts `result.events.every((event) => event.name !== "VS PLM Plenary")` across ALL dates, but day-two legitimately contains `VS PLM Plenary` events. → Scope the assertion to day one: `result.events.filter((e) => e.date === "2026-03-17").every(...)`.
  These failures cascade into two further failures in `tests/sage-review-followups-spec.mjs`. They were not introduced by this change, but they must be resolved before the full suite can be trusted as a regression gate.

### Info

- **js/filter.js:57** (`buildHierarchy`): The `isGlobalPlenary(event)` guard used to skip shared events in hierarchy building is semantically different from the new `isAllValueStreamEvent(event)` used in `filterEvents`. `isGlobalPlenary` requires `type === "Plenary"` as its outer condition; a non-Plenary `ALL` event with selectable teams would not be excluded from the hierarchy by the current guard (it would have to rely on `!hasSelectableTeams(event)` instead). In current committed data this is not an issue, but the semantic gap is worth noting. → Add an `|| isAllValueStreamEvent(event)` clause to the `buildHierarchy` skip guard, or add a comment explaining that non-Plenary ALL events are excluded by the `!hasSelectableTeams` check already.

- **tests/scope-filter-all-events-spec.mjs:49 and :96** (tester-owned file): The two `deepEqual` assertions use exact-ordered arrays matched against committed CSV data, e.g. `["Lunch", "Coffee break", "Overall PI Plenary", "Drinks and nibbles"]`. The order is deterministic because `filterEvents` calls `sortEventsByStart()`, but a change to event start times in `data/csv/2026-03-18.csv` would break the test even if the filter behavior remains correct. → Add a brief inline comment explaining that the expected order is by ascending event start time, so future data changes know to update the expected arrays accordingly.

## Plan Adherence
All 3 plan steps were implemented as specified:
- Step 1: `isAllValueStreamEvent` helper added; `plenary`, `vs`, and `team` modes updated in `filterEvents`.
- Step 2: `requirements.spec.mjs` updated with new contract, test renamed accurately.
- Step 3: Committed-data coverage added to `name-teams-decoupling-spec.mjs`.

One documented deviation: the implementer corrected the stale legacy JSON test harness in `name-teams-decoupling-spec.mjs` to use `normalizeRecord` directly (since `loadAllSources` now prefers CSV). This is a justified, minimal fix and was correctly documented in the implementation artifact.

No unplanned changes to production code. `buildHierarchy`, `sortEventsByStart`, `getTeamValueStream`, `isGlobalPlenary`, and `isVsPlenary` are all unchanged.

## Verdict
**Request Changes** — fix the `assert.equal` inside `.filter()` in `tests/name-teams-decoupling-spec.mjs` before merging. Additionally, the two stale failures in `tests/sage-spec-requirements.mjs` should be fixed either in this PR or as an immediate follow-up; leaving four red tests in the suite masks genuine future regressions.

The production change in `js/filter.js` is correct, clean, and appropriately narrow. The `isAllValueStreamEvent(event)` abstraction is well-named and consistent across all three scope modes. No security concerns. No guideline violations in the production file.

## Estimated Impact
- **Time saved ≈ 30-40%** — AI systematically read all upstream artifacts and all 6 test files against EMA guidelines and plan adherence, identified the assert-in-filter code smell, and traced the stale test root causes; developer still validates domain semantics, confirms the stale test fixes, and assesses whether the `buildHierarchy` Info item is worth a follow-up task (~1h AI-assisted vs ~1.5-2h fully manual)

## Pipeline Recap

**Artifact saved**: `artifacts/2026-03-24-scope-filter-all-events-review-report.md`

**Full artifact chain**:
- Requirements: none (user request in conversation)
- Architecture: none required for this limited change
- Plan: `artifacts/2026-03-24-scope-filter-all-events-plan.md`
- Implementation: `artifacts/2026-03-24-scope-filter-all-events-implementation.md`
- Test report: `artifacts/2026-03-24-scope-filter-all-events-test-report.md`
- Review report: `artifacts/2026-03-24-scope-filter-all-events-review-report.md` ← this file

**Pipeline outcome**: Request Changes
**Critical findings**: none
**Remaining actions for developer**:
1. Fix `tests/name-teams-decoupling-spec.mjs` (legacy JSON test): replace `assert.equal(result.errors.length, 0)` inside `.filter()` with a two-pass validate-then-filter pattern (see Warning finding above)
2. Fix `tests/sage-spec-requirements.mjs` line ~129: scope the `jsonEvents` assertion to a JSON-only fixture or switch to CSV assertion
3. Fix `tests/sage-spec-requirements.mjs` line ~155: scope the VS PLM Plenary exclusion assertion to `date === "2026-03-17"` only
4. Re-run full suite (`node tests/sage-spec-requirements.mjs; node tests/sage-review-followups-spec.mjs; node tests/requirements.spec.mjs; node tests/name-teams-decoupling-spec.mjs; node tests/scope-filter-all-events-spec.mjs; node tests/date-named-sources-spec.mjs`) to confirm 25/25 PASS
5. Commit staged changes per plan order: `fix(filter)` → `test(requirements)` → `test(filter)` → fix stale tests

> The `.metrics/` usage log has 28 data rows. Consider invoking `@ema-metrics-consolidator` to consolidate related entries into fewer, richer rows.
>
> 📋 **Model**: Select **Gemini 3 Flash** in the model picker before submitting.
