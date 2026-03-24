## Summary
Replace misleading 30-minute timeslot bucketing with exact-start grouping so irregular events such as `08:55 - 09:45` render under accurate group headers while keeping the existing grouped-card layout.

## Steps

### Step 1: Update exact-start grouping logic
- **File**: `js/timeslot.js` (modify)
- **Changes**: Make `getBucketKey()` return the normalized exact time; change `formatBucketLabel()` to accept a start and end time; update `groupEventsByTimeslot()` to derive each group's label from actual grouped event times; keep bucket object shape unchanged; preserve `findCurrentBucketIndex()` behavior with exact `HH:MM` keys.
- **Tests**: Run `node tests/timeslot-grouping-spec.mjs`
- **Commit message**: `fix(schedule): group timeslots by exact event start`

### Step 2: Remove the obsolete bucket-size call site
- **File**: `app.js` (modify)
- **Changes**: Remove the second argument from `groupEventsByTimeslot(selectedEvents, 30)` so the app uses the new exact-start grouping API.
- **Tests**: Run `node tests/timeslot-grouping-spec.mjs`
- **Commit message**: `refactor(schedule): remove obsolete timeslot bucket argument`

### Step 3: Update regression coverage for exact-start behavior
- **File**: `tests/timeslot-grouping-spec.mjs` (modify)
- **Changes**: Replace rounded-bucket expectations with exact-start assertions, including an irregular-start case such as `08:55 - 09:45`; keep renderer and indicator coverage intact.
- **Tests**: This IS the test, then rerun the same file after implementation
- **Commit message**: `test(schedule): cover exact-start timeslot grouping`

## Testing Approach
Run:
- `node tests/timeslot-grouping-spec.mjs`

If terminal validation is available, also run the broader regression sweep afterward:
- `node tests/clear-filter-button-spec.mjs`
- `node tests/legend-click-search-spec.mjs`

## Handoff

**Artifact saved**: `artifacts/2026-03-24-exact-start-grouping-plan.md`

**Upstream artifacts**:
- Architecture: `artifacts/2026-03-24-exact-start-grouping-architecture.md`
- Requirements: (none — direct user request)

**Context for @ema-implementer-lite**:
- 3 steps to execute
- Files affected: `js/timeslot.js`, `app.js`, `tests/timeslot-grouping-spec.mjs`
- Test command: `node tests/timeslot-grouping-spec.mjs`
- Watch for: keep the `bucketLabel`/`bucketKey`/`events` object shape stable for `js/renderer.js`; ensure exact `HH:MM` lexicographic comparisons still work in `findCurrentBucketIndex()`; stage changes but do not commit

> 📋 **Model**: Select **Gemini 3 Flash** before invoking `@ema-implementer-lite`

**What @ema-implementer-lite should do**:
1. Read the plan artifact at `artifacts/2026-03-24-exact-start-grouping-plan.md`
2. Execute each step atomically, running the test command after each relevant step
3. Stage changes but do NOT commit
4. Save implementation summary to `artifacts/2026-03-24-exact-start-grouping-implementation.md`
