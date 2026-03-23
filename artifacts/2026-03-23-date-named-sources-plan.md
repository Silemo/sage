## Summary
Implement the date-named source-file design from [artifacts/2026-03-23-date-named-sources-architecture.md](artifacts/2026-03-23-date-named-sources-architecture.md): rename the committed JSON files from logical labels to ISO dates, change `config/sources.json` to map logical labels to date-keyed files, update `js/loader.js` to derive fetch paths from the date/file stem, and update the requirements/regression tests and README to match the new contract.

## Verified Codebase State
- `config/sources.json` exists and currently uses `{ name, defaultDate }` entries for `day1` and `day2`.
- `js/loader.js` exists and `loadSourceRecords(sourceConfig)` currently constructs `data/csv/${sourceConfig.name}.csv` and `data/json/${sourceConfig.name}.json`.
- `data/json/day1.json` and `data/json/day2.json` both exist and are the files that need renaming.
- `tests/sage-spec-requirements.mjs` currently asserts `name` keys, uses `withTemporaryCsv("day1", ...)`, and still contains the unrelated but already-known hardcoded `37` event-count assertion in the malformed-CSV test.
- `tests/sage-review-followups-spec.mjs` currently points to `data/json/day2.json`.
- `README.md` still documents the old `{name}`-based path convention.

## Steps

### Step 1: Rename the committed JSON data files to ISO dates
- **File**: `data/json/day1.json` (rename to `data/json/2026-03-17.json`)
- **File**: `data/json/day2.json` (rename to `data/json/2026-03-18.json`)
- **Changes**: Rename the two tracked JSON files without changing their contents. Preserve the existing JSON formatting and trailing newline. Do not create or modify any extra date files.
- **Rationale**: This is the core repository-layout change requested by the user. The folder can now hold many date-named files, while the app loads only the ones explicitly referenced from `sources.json`.
- **Tests**: No standalone test for the rename. Verification happens in Steps 2-4 when the loader and tests are updated.
- **Commit message**: `refactor(data): rename schedule files to iso dates`

### Step 2: Change source configuration to map logical labels to date-backed files
- **File**: `config/sources.json` (modify)
- **Changes**: Replace the current `name` properties with `label`, keeping `defaultDate` unchanged.
- **Changes**: Final shape should be:
```json
{
  "sources": [
    {
      "label": "day1",
      "defaultDate": "2026-03-17"
    },
    {
      "label": "day2",
      "defaultDate": "2026-03-18"
    }
  ]
}
```
- **Changes**: Do not add `file` yet. The architecture allows an optional future override, but the chosen design for this change is to derive the file stem directly from `defaultDate`.
- **Rationale**: This decouples the human/logical source label from the on-disk file name while keeping the config compact.
- **Tests**: The requirements suite should later assert that each source has `label` and `defaultDate`, and that the logical labels remain `day1` and `day2`.
- **Commit message**: `refactor(config): map logical labels to date-backed sources`

### Step 3: Update the loader to derive file paths from the date/file stem
- **File**: `js/loader.js` (modify)
- **Changes**: In `loadSourceRecords(sourceConfig)`, replace the current `sourceName` path logic with a date/file-stem variable:
```js
const fileStem = normalizeWhitespace(sourceConfig.file ?? sourceConfig.defaultDate);
const csvPath = `data/csv/${fileStem}.csv`;
const jsonPath = `data/json/${fileStem}.json`;
```
- **Changes**: Keep the existing CSV-first then JSON-fallback behavior unchanged.
- **Changes**: In `loadAllSources(sourcesConfig)`, keep using `sourceLabel` returned from `loadSourceRecords()` for `normalizeRecord()`. Update the fallback error message to reference `sourceConfig.label ?? sourceConfig.defaultDate` instead of `sourceConfig.name`.
- **Changes**: Do not change `normalizeRecord()`, `validateRecord()`, deduplication logic, or the emitted `event.source` format. After this step, `event.source` should naturally become values like `data/json/2026-03-17.json` because that is what `loadSourceRecords()` returns as `sourceLabel`.
- **Rationale**: This is the functional change that allows the app to load date-named files while still keeping `day1`/`day2` as logical config labels.
- **Tests**: Existing requirements tests should continue passing once updated. Pay particular attention to missing-source errors: a synthetic missing source should now try `data/csv/2026-03-19.csv` and `data/json/2026-03-19.json` if its `defaultDate` is `2026-03-19`.
- **Commit message**: `refactor(loader): derive source paths from dates`

### Step 4: Update the requirements suite to the new config and file-path contract
- **File**: `tests/sage-spec-requirements.mjs` (modify)
- **Changes**: Update the config-shape assertion in `repo uses canonical data folders and logical source names` from `["defaultDate", "name"]` to `["defaultDate", "label"]`.
- **Changes**: Update the logical-label assertion from `source.name` to `source.label` while keeping the expected values `["day1", "day2"]`.
- **Changes**: Update `withTemporaryCsv(sourceName, content, testFn)` usage so the temporary CSV filename matches the date-based file stem. For the malformed-CSV test, call `withTemporaryCsv("2026-03-17", malformedCsv, ...)` instead of `withTemporaryCsv("day1", ...)`.
- **Changes**: Update the missing-source scenario to match the new schema:
```js
{ label: "missing-day", defaultDate: "2026-03-19" }
```
- **Changes**: Update the missing-source error assertions to expect `data/csv/2026-03-19.csv` and `data/json/2026-03-19.json`.
- **Changes**: While editing this file, also fix the already-known brittle assertion in the malformed-CSV test. Replace `assert.equal(result.events.length, 37)` with a dynamic expectation based on the current day-2 baseline, for example:
```js
const baselineDay2Count = (await loadAllSources(sources)).events.filter((event) => event.date === "2026-03-18").length;
...
assert.equal(result.events.length, 1 + baselineDay2Count);
```
- **Changes**: Keep the rest of the runner behavior (`process.exit(failCount > 0 ? 1 : 0)`) unchanged.
- **Rationale**: This file is the primary spec-facing suite and currently encodes both the old schema and one unrelated fragile count. The implementer should leave it aligned with the new source contract and still green.
- **Tests**: Run `node .\tests\sage-spec-requirements.mjs` against a local static server after this step.
- **Commit message**: `test(requirements): align source tests with date-named files`

### Step 5: Update the follow-up regression suite to the renamed day-2 file
- **File**: `tests/sage-review-followups-spec.mjs` (modify)
- **Changes**: Replace `const day2JsonPath = path.join(workspaceRoot, "data", "json", "day2.json");` with `const day2JsonPath = path.join(workspaceRoot, "data", "json", "2026-03-18.json");`.
- **Changes**: Leave the rest of the suite unchanged unless required by Step 4's test fix.
- **Rationale**: This regression suite mutates the day-2 fixture directly by file path; it must track the renamed JSON file.
- **Tests**: Run `node .\tests\sage-review-followups-spec.mjs` against the local static server after this step. It should pass all 3 tests once Step 4's hardcoded `37` is fixed.
- **Commit message**: `test(regression): point follow-up suite at date-named fixture`

### Step 6: Update repository documentation for the new source contract
- **File**: `README.md` (modify)
- **Changes**: In the `Data layout` section, replace the old sentence `For each source, the app tries data/csv/{name}.csv first and falls back to data/json/{name}.json` with wording that reflects the new contract, e.g. `For each configured source, the app uses its defaultDate as the file stem: data/csv/{date}.csv first, then data/json/{date}.json.`
- **Changes**: Add one short line clarifying that `config/sources.json` controls which date files are loaded, so `data/json/` may contain additional unreferenced date files.
- **Rationale**: The documentation needs to describe the new repository workflow accurately, especially because the user explicitly wants many date files to coexist with only a selected subset displayed.
- **Tests**: Read the rendered markdown or open the file directly to confirm the description is accurate and consistent with the implemented loader behavior.
- **Commit message**: `docs(readme): describe date-named source files`

## Testing Approach
Run from the repository root.

1. Start a local static server:
```powershell
npx http-server . -p 8000
```

2. Run the requirements suite:
```powershell
node .\tests\sage-spec-requirements.mjs
```

3. Run the follow-up regression suite:
```powershell
node .\tests\sage-review-followups-spec.mjs
```

4. Optional manual verification:
```powershell
# with the server still running, open the app and confirm both configured days still render
start http://127.0.0.1:8000/
```

5. Optional edge-case verification for the new design:
- Temporarily place an extra unreferenced file such as `data/json/2026-03-19.json` in the workspace.
- Confirm the app and tests still load only the two dates listed in `config/sources.json`.
- Remove the extra file afterward unless the user wants to keep it.

## Handoff

**Artifact saved**: `artifacts/2026-03-23-date-named-sources-plan.md`

**Upstream artifacts**:
- Requirements: `artifacts/2026-03-17-schedule-requirements.md`
- Architecture: `artifacts/2026-03-23-date-named-sources-architecture.md`
- Relevant known test context: `artifacts/2026-03-23-sage-review-followups-test-report.md`

**Context for @ema-implementer**:
- 6 steps to execute
- Files to rename: `data/json/day1.json` → `data/json/2026-03-17.json`, `data/json/day2.json` → `data/json/2026-03-18.json`
- Files to modify: `config/sources.json`, `js/loader.js`, `tests/sage-spec-requirements.mjs`, `tests/sage-review-followups-spec.mjs`, `README.md`
- Files to leave unchanged: `app.js`, `js/filter.js`, `js/renderer.js`, `js/url-state.js`, `js/time-indicator.js`, `index.html`, `styles.css`
- Test command: `npx http-server . -p 8000`, then `node .\tests\sage-spec-requirements.mjs` and `node .\tests\sage-review-followups-spec.mjs`
- Test framework: custom Node ESM test scripts using `assert/strict`
- Watch for:
  - `tests/sage-spec-requirements.mjs` already has a known failing hardcoded `37`; fix it as part of Step 4 instead of carrying it forward
  - Missing-source assertions must switch from label-based file names to date-based file names
  - `event.source` values will change to `data/json/YYYY-MM-DD.json` or `data/csv/YYYY-MM-DD.csv`; update only tests that actually assert on those paths
  - `tests/requirements.spec.mjs` is untracked and out of scope unless the user explicitly asks to reconcile it

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-implementer`

**What @ema-implementer should do**:
1. Read this plan artifact at `artifacts/2026-03-23-date-named-sources-plan.md`
2. Read the architecture artifact for design intent only; do not redesign the schema
3. Execute the six steps atomically, staging changes but not committing
4. Run both test scripts with the local static server before finishing
5. Save the implementation summary to `artifacts/2026-03-23-date-named-sources-implementation.md`
