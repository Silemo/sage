## Summary
Rename data files from logical labels (`day1.json`) to ISO-date names (`2026-03-17.json`) and add a `label` field in `sources.json` that maps human-readable day names to date-keyed files. The `data/` folder can contain many date files; only those referenced in `sources.json` are loaded and displayed. Approach B (add a `file` field derived from `defaultDate`) is recommended — it requires the fewest changes, keeps the schema self-describing, and avoids redundancy.

## Codebase Context
Key findings from exploring the current design:

- **`config/sources.json`** — array of `{ name, defaultDate }`. `name` is used by the loader to construct fetch paths (`data/csv/{name}.csv`, `data/json/{name}.json`). `defaultDate` is applied to records that lack a `date` field.
- **`js/loader.js` → `loadSourceRecords()`** (line ~216) — builds paths from `sourceConfig.name`: `data/csv/${sourceName}.csv` → fallback `data/json/${sourceName}.json`. `loadAllSources()` iterates `sourcesConfig.sources`, delegates to `loadSourceRecords`, passes `sourceConfig.defaultDate` to `normalizeRecord`.
- **`app.js` → `updateTitle()`** — derives "Day N" label from the index position of the date in `appState.hierarchy.dates`. Does not reference `name` at all.
- **Data files** — `data/json/day1.json` (36 records, date 2026-03-17) and `data/json/day2.json` (36 records, date 2026-03-18). Legacy `time` field format. No CSV files yet.
- **Tests** — `tests/sage-spec-requirements.mjs` asserts on source names (`["day1", "day2"]`), constructs CSV paths via `data/csv/${sourceName}.csv`. `tests/sage-review-followups-spec.mjs` mutates `data/json/day2.json` directly by path. `tests/requirements.spec.mjs` (untracked) also references `day1`/`day2` filenames.

The `name` field currently serves double duty: it is both the logical day label (for human readability and assertion) and the file stem (for path construction). The change decouples these two concerns.

## Design Approaches Considered

### Approach A: Replace `name` with `date` as the file stem
- **Description**: Rename `name` to `label` for display purposes. Data files are named `{defaultDate}.json` / `{defaultDate}.csv`. The loader derives file paths from `defaultDate` instead of `name`.
- **`sources.json` schema**: `{ "label": "day1", "defaultDate": "2026-03-17" }`.
- **Loader path logic**: `data/csv/${sourceConfig.defaultDate}.csv` → `data/json/${sourceConfig.defaultDate}.json`.
- **Pros**: Minimal schema — two fields, no redundancy. File names are immediately human-readable. `defaultDate` already exists and always matches the date in the file name.
- **Cons**: Couples file naming to `defaultDate` implicitly — a reader must know that `defaultDate` is used _both_ as a fallback date _and_ as the file stem. If a file ever serves a date range (not the current case), this assumption breaks. `label` replaces `name`, which touches every test assertion that checks source names.

### Approach B: Add an explicit `file` field derived from `defaultDate` ⭐ (recommended)
- **Description**: Keep `name` as the logical label (renamed to `label` for clarity). Add no new field — instead derive the file stem from `defaultDate` automatically in the loader. The schema becomes `{ "label": "day1", "defaultDate": "2026-03-17" }` and the loader uses `defaultDate` for path construction. Alternatively, an explicit `file` field can be added: `{ "label": "day1", "defaultDate": "2026-03-17", "file": "2026-03-17" }` — but since `file` always equals `defaultDate` in the current model, the derived approach avoids redundancy.
- **Loader path logic**: `const fileStem = sourceConfig.file ?? sourceConfig.defaultDate;` → tries `data/csv/${fileStem}.csv` → fallback `data/json/${fileStem}.json`.
- **Pros**: Self-describing schema — `label` is for humans, `defaultDate` is for both the date fallback and the file stem. Adding an optional `file` override supports future edge cases (e.g., a file whose name doesn't match the date) without changing the schema now.
- **Cons**: Very slightly more complex than Approach A due to the `??` fallback, but the difference is one line.

### Approach C: Use a full `path` field per source
- **Description**: Each source entry has a `path` field pointing to the full data directory stem. Example: `{ "label": "day1", "defaultDate": "2026-03-17", "path": "data/json/2026-03-17" }`.
- **Pros**: Maximum flexibility — any file layout works.
- **Cons**: Breaks the current convention that the loader constructs paths from `data/csv/` and `data/json/` prefixes. Introduces redundant path segments in every entry. Moves too much responsibility to config, making it error-prone.

## Chosen Design
**Approach B** — derive the file stem from `defaultDate`, rename `name` to `label`, and rename data files to `{defaultDate}.json`.

Rationale: This is the simplest change that achieves the user's goal (date-named data files, `sources.json` controls which dates are loaded, `data/` folder can contain many files). The schema remains two fields with no redundancy. The optional `file` override (not needed now) can be added later if a file ever needs a stem different from its `defaultDate`.

### Components

**Modified files:**

| File | Change |
|------|--------|
| `config/sources.json` | Rename `name` → `label`. Keep `defaultDate`. No new fields (the loader derives the file stem from `defaultDate`). |
| `js/loader.js` → `loadSourceRecords()` | Use `sourceConfig.defaultDate` (or `sourceConfig.file` if present) as the file stem instead of `sourceConfig.name`. Update `sourceName` variable to use `sourceConfig.label ?? sourceConfig.defaultDate` for the `event.source` metadata. |
| `data/json/day1.json` | Rename to `data/json/2026-03-17.json` |
| `data/json/day2.json` | Rename to `data/json/2026-03-18.json` |
| `tests/sage-spec-requirements.mjs` | Update assertions that check source names (`["day1", "day2"]` → `["day1", "day2"]` remains valid if tests assert on `label`; update `withTemporaryCsv` to construct paths using `defaultDate`). |
| `tests/sage-review-followups-spec.mjs` | Update `day2JsonPath` to `data/json/2026-03-18.json`. |
| `tests/requirements.spec.mjs` (untracked) | Update `data/json/day1.json` / `data/json/day2.json` references. (Optional — file is untracked.) |
| `README.md` | Update data layout section to reflect date-named files. |

**No changes needed:**

| File | Why |
|------|-----|
| `app.js` | Does not reference source file names. Uses `appState.hierarchy.dates` (derived from event `date` fields). "Day N" label comes from array index, not from `name`. |
| `js/filter.js` | Operates on normalized events, never touches source config. |
| `js/renderer.js` | Same — uses event fields only. |
| `js/url-state.js` | Reads/writes query string date values, unrelated. |
| `js/time-indicator.js` | Unrelated. |
| `index.html`, `styles.css` | No source name references. |

### Data Flow

```
config/sources.json
  ↓ (fetched by app.js → passed to loadAllSources)
loadAllSources(sourcesConfig)
  ↓ for each source entry:
  ↓   fileStem = source.file ?? source.defaultDate   ← NEW: derive from date
  ↓   label = source.label ?? fileStem                ← NEW: for event.source metadata
  ↓   try data/csv/{fileStem}.csv → fallback data/json/{fileStem}.json
  ↓   normalizeRecord(raw, sourceLabel, source.defaultDate)
  ↓
events[] with source = "data/json/2026-03-17.json" etc.
```

### Interfaces and Contracts

**`config/sources.json` schema (after change):**
```json
{
  "sources": [
    { "label": "day1", "defaultDate": "2026-03-17" },
    { "label": "day2", "defaultDate": "2026-03-18" }
  ]
}
```

- `label` (string, required) — human-readable identifier; used in tests and potentially in future UI elements. Replaces the former `name` field.
- `defaultDate` (string, required, ISO 8601) — used as both (a) the date fallback for records missing a `date` field and (b) the file stem for path construction.
- `file` (string, optional) — explicit file stem override. If present, the loader uses this instead of `defaultDate` for path construction. Not needed initially but supports future edge cases.

**`loadSourceRecords(sourceConfig)` — updated signature (internal, not exported):**
```js
async function loadSourceRecords(sourceConfig) {
  const fileStem = normalizeWhitespace(sourceConfig.file ?? sourceConfig.defaultDate);
  const csvPath = `data/csv/${fileStem}.csv`;
  const jsonPath = `data/json/${fileStem}.json`;
  // ... rest unchanged
}
```

**`loadAllSources(sourcesConfig)` — updated source label:**
```js
const sourceLabel = sourceConfig.label ?? sourceConfig.defaultDate;
// passed to normalizeRecord as the sourceName argument
```

### Integration Points

- **`js/loader.js` line ~216–219**: `loadSourceRecords` — change from `sourceConfig.name` to `sourceConfig.file ?? sourceConfig.defaultDate` for path construction.
- **`js/loader.js` line ~246**: `loadAllSources` loop — change the source label from `sourceConfig.name` to `sourceConfig.label ?? sourceConfig.defaultDate`.
- **`config/sources.json`**: Rename `name` → `label` in both entries. Keep `defaultDate` unchanged.
- **`data/json/`**: Rename `day1.json` → `2026-03-17.json` and `day2.json` → `2026-03-18.json`.

## Error Handling
No new error handling needed. The existing try/catch chain in `loadSourceRecords` already handles missing files. If a date file referenced in `sources.json` doesn't exist in both `data/csv/` and `data/json/`, the existing error message surfaces both attempted paths — those paths will now show the date stem instead of the label stem, which is clearer.

## Testing Strategy

**Unit-level updates:**
- `tests/sage-spec-requirements.mjs`: Update `["day1", "day2"]` assertion in test 2 to check `label` values. Update `withTemporaryCsv("day1", ...)` call to use the `defaultDate` value (`"2026-03-17"`) as the CSV file stem. Update `event.source.startsWith("data/json/")` assertions — these remain valid as-is.
- `tests/sage-review-followups-spec.mjs`: Update `day2JsonPath` from `data/json/day2.json` to `data/json/2026-03-18.json`.

**Behavioral verification:**
- Run both test suites with the HTTP server to confirm all 8 tests pass.
- Manually verify the static site loads both days correctly.

**Edge case to verify:**
- Place an extra JSON file in `data/json/` (e.g., `2026-03-19.json`) that is NOT referenced in `sources.json`. Confirm it is not loaded — this validates the "data folder can have many files but only referenced ones display" requirement.

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Tests that hardcode `day1`/`day2` in file paths break | High (known) | Part of the plan — update all path references in tests |
| The `event.source` field changes from `data/json/day1.json` to `data/json/2026-03-17.json` — any downstream consumer that pattern-matches on `day1` breaks | Low (no known consumers beyond tests) | Tests will be updated; no production consumers exist |
| Future data files whose date doesn't match `defaultDate` | Low | The optional `file` field override handles this without schema change |
| Untracked `tests/requirements.spec.mjs` still references old paths | Medium | Note in the plan for the implementer to update or ignore |

## Handoff

**Artifact saved**: `artifacts/2026-03-23-date-named-sources-architecture.md`

**Path signal**: full → @ema-planner (schema change touches loader, config, data files, and tests — not a trivial one-file fix)

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-planner`

**Upstream artifacts**:
- Requirements: `artifacts/2026-03-17-schedule-requirements.md` (original SAGE requirements)

**Context for @ema-planner**:
- Chosen approach: Derive file stem from `defaultDate`, rename `name` → `label` in sources.json, rename data files to `{date}.json`
- Files to create: none
- Files to modify: `config/sources.json`, `js/loader.js`, `tests/sage-spec-requirements.mjs`, `tests/sage-review-followups-spec.mjs`, `README.md`
- Files to rename: `data/json/day1.json` → `data/json/2026-03-17.json`, `data/json/day2.json` → `data/json/2026-03-18.json`
- Key integration points: `loadSourceRecords()` at `js/loader.js` line ~216 (path construction), `loadAllSources()` at line ~246 (source label), `config/sources.json` schema, test assertions referencing `["day1", "day2"]` and `data/json/day2.json` path
- Testing strategy: update existing test assertions, run both suites, verify unreferenced files in `data/` are not loaded
- Conventions to follow: ESM imports, `const` by default, existing `normalizeWhitespace()` for input sanitization, existing test runner pattern with `runTest()`/`process.exit(failCount)`

**Files the planner must verify exist before writing the plan**:
- `config/sources.json` — confirm current `{ name, defaultDate }` schema
- `js/loader.js` — confirm `loadSourceRecords` uses `sourceConfig.name` for path construction (line ~216)
- `data/json/day1.json` — confirm it exists and needs renaming
- `data/json/day2.json` — confirm it exists and needs renaming
- `tests/sage-spec-requirements.mjs` — confirm `["day1", "day2"]` assertion and `withTemporaryCsv("day1", ...)` call
- `tests/sage-review-followups-spec.mjs` — confirm `day2JsonPath` reference

**What @ema-planner should do**:
1. Read this architecture artifact at `artifacts/2026-03-23-date-named-sources-architecture.md`
2. Verify the listed files exist and match the descriptions
3. Produce a step-by-step plan with exact file paths, function signatures, and commit messages
4. Save plan to `artifacts/2026-03-23-date-named-sources-plan.md`
