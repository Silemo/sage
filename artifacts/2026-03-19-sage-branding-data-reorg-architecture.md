# Architecture Design — SAGE Branding, Data Reorganization & Import Removal

## Summary

Update the existing SAGE schedule viewer to: (1) remove the CSV/JSON file upload control from the UI, (2) reorganize data into `data/json/` and `data/csv/` subfolders with CSV-preferred loading, and (3) rebrand the interface to show "SAGE". This is a focused refactor of an already-implemented codebase — no new modules, no new abstractions.

## Codebase Context

### Current state (post-initial implementation)

The app is a working static site using ES Modules:

| File | Purpose | Relevant findings |
|------|---------|-------------------|
| `index.html` | Entry point | Has a file import control (`<input id="importInput" type="file">`) at line 35 that must be removed. Title shows "PI Planning Schedule" — needs "SAGE". Eyebrow says "Static event schedule". |
| `app.js` | Orchestrator | Contains `handleImportChange()` (~lines 192–220) for file import, plus event listener binding for `importInput` (~line 262). These must be removed. Title updates in `updateTitle()` (~line 66) use "PI Planning Schedule" — needs "SAGE". |
| `js/loader.js` | Data loading | `loadAllSources()` iterates `sourcesConfig.sources`, calls `loadJsonSource()` for each. Currently expects `{ file, defaultDate }` per source. Must be updated to try CSV first, then JSON. `parseCsv()` already works — it's used for the now-removed import feature but is still needed for reading repo-committed CSV files. |
| `js/filter.js` | Filtering | No changes needed — hierarchical filter logic is correct. |
| `js/url-state.js` | URL state | No changes needed. |
| `js/renderer.js` | Card rendering | No changes needed — already uses DOM APIs/textContent (no XSS risk). |
| `js/time-indicator.js` | Time indicator | No changes needed. |
| `config/sources.json` | Source registry | Currently `{ sources: [{ file: "rooms.json", defaultDate: "2026-03-17" }, ...] }`. Must change to `{ sources: [{ name: "day1", defaultDate: "2026-03-17" }, ...] }` with the name-based convention. |
| `config/colors.json` | VS color palette | No changes needed. |
| `styles.css` | Styling | `.import-control` styles exist but the control is being removed. Clean up the rule. Existing styles are clean and pleasant — the visual system is already in good shape. |
| `rooms.json`, `room2.json` | Data files (root) | Must be moved to `data/json/day1.json` and `data/json/day2.json`. |
| `test.html` | Smoke tests | May need minor updates if loader API changes. |
| `test-data/sample.csv` | Test CSV | Should also move to `data/csv/` or remain as test fixture. |

### Patterns and conventions

- Pure vanilla JS with ES Modules, no build step, no dependencies.
- DOM manipulation via `createElement` and `textContent` (safe, no `innerHTML` for data).
- `config/sources.json` is the single registry of data sources.
- CSS custom properties for theming.

---

## Design Approaches Considered

### Approach A: Name-based convention with CSV-preferred fetch ⭐ (recommended)

**Description**: `sources.json` lists logical source names (e.g., `"day1"`). The loader tries `data/csv/{name}.csv` first via a fetch that handles 404 gracefully, then falls back to `data/json/{name}.json`. The existing `parseCsv()` function handles CSV files; `loadJsonSource()` handles JSON files.

**Pros**:
- Simple convention — adding a new day means: (1) add a file under `data/csv/` or `data/json/`, (2) add one entry to `sources.json`.
- Data maintainers can choose CSV or JSON per source without changing code.
- Minimal code changes — only `loadAllSources()` and `loadJsonSource()` need updating.
- The CSV parser already exists and works.

**Cons**:
- A 404 fetch for a missing CSV file generates a network error in browser DevTools (cosmetic, not functional).
- Convention must be documented so contributors know where to put files.

### Approach B: Explicit dual paths in sources.json

**Description**: Each source explicitly lists both paths: `{ csv: "data/csv/day1.csv", json: "data/json/day1.json", defaultDate: "..." }`. The loader tries the `csv` path first if present.

**Pros**:
- Explicit — no guessing about file locations.
- No convention to learn.

**Cons**:
- More verbose config — every source needs two paths.
- Adds no real value over the convention approach since the paths are entirely predictable.
- Adding a CSV override later means editing `sources.json` to add the `csv` field.

### Approach C: Auto-discovery via a manifest

**Description**: Generate a manifest file listing all files in `data/` (e.g., via a small script or manual maintenance). The loader reads the manifest and picks the best format per source.

**Pros**:
- Fully automatic if a build step is allowed.

**Cons**:
- Requires either a build step (violating the static-site constraint) or manual manifest maintenance (worse than `sources.json`).
- Over-engineered for the current scale (2–3 data sources).

---

## Chosen Design

**Approach A — Name-based convention with CSV-preferred fetch.**

Reason: It's the simplest approach that meets the requirements. The convention is easy to document, the code changes are minimal, and it preserves the existing architecture. Data maintainers can drop a CSV file into `data/csv/` and it takes precedence automatically.

---

### Components

No new modules are introduced. Changes are localized to existing files:

#### 1. Data folder structure (new directories)

```
data/
  csv/          — CSV files (preferred when present)
  json/         — JSON files (fallback)
    day1.json   — moved from rooms.json
    day2.json   — moved from room2.json
```

#### 2. `config/sources.json` (modify)

New format — `name`-based instead of `file`-based:

```json
{
  "sources": [
    { "name": "day1", "defaultDate": "2026-03-17" },
    { "name": "day2", "defaultDate": "2026-03-18" }
  ]
}
```

#### 3. `js/loader.js` (modify)

- Update `loadAllSources()` to implement the CSV-preferred fetch convention:
  1. For each source, try `fetch(`data/csv/${name}.csv`)`.
  2. If the response is OK, read as text, pass to `parseCsv()`.
  3. If 404 or error, try `fetch(`data/json/${name}.json`)`.
  4. If both fail, record error and continue to next source.
- The existing `parseCsv()` function is unchanged — it already correctly parses CSV text.
- `normalizeRecord()` is unchanged — it handles both canonical and legacy fields.
- Rename or generalize `loadJsonSource()` to handle the new flow.

#### 4. `app.js` (modify)

- Remove `handleImportChange()` function entirely.
- Remove the `importInput.addEventListener("change", handleImportChange)` listener binding.
- Remove `importInput` from `getElements()` (or keep it but don't bind to it).
- Remove the `mergeImportedEvents()` function.
- Remove the `normalizeRecord` and `parseCsv` imports (they're no longer needed in app.js — the loader handles everything internally).
- Update `updateTitle()`: change "PI Planning Schedule" to "SAGE".
- Update the subtitle/eyebrow approach: keep "SAGE" as the main heading; the subtitle can show the current filter state.

#### 5. `index.html` (modify)

- Remove the import control `<label>` block (lines 34–37: the `.filter-group.import-control` containing the file input).
- Change `<title>` from "PI Planning Schedule" to "SAGE".
- Change the `<p class="eyebrow">` text to something brief like "Schedule viewer" or just remove it.
- Change `<h1>` default text to "SAGE".
- Keep all other structure (date tabs, search, scope select, legend, rooms container).

#### 6. `styles.css` (modify)

- Remove or keep the `.import-control` rule (it won't hurt if left, but cleaner to remove).
- No other visual changes needed — the existing design is already clean and pleasant.

#### 7. Root data files (move/delete)

- Move `rooms.json` → `data/json/day1.json`
- Move `room2.json` → `data/json/day2.json`
- The original files can be deleted after move.

---

### Data Flow

```
                    ┌──────────────┐
                    │ sources.json │  { name: "day1", ... }
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │  loader.js   │
                    │              │
                    │  For each source:
                    │  1. Try data/csv/{name}.csv
                    │  2. If 404 → data/json/{name}.json
                    │  3. Normalize + validate + merge
                    └──────┬───────┘
                           │
                    allEvents: CanonicalEvent[]
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼──────┐  ┌─▼──────┐  ┌──▼────────────┐
       │ filter.js   │  │ build  │  │ url-state.js   │
       │ filterEvents│  │Hierarchy│  │ readState()    │
       └──────┬──────┘  └─┬──────┘  └──┬────────────┘
              │            │            │
              └────────────┼────────────┘
                           │
                    ┌──────▼───────┐
                    │ renderer.js  │  renderCards + renderLegend
                    └──────┬───────┘
                           │
                    ┌──────▼──────────────┐
                    │ time-indicator.js   │  insertIndicator (if today)
                    └─────────────────────┘
```

Note: **no user upload path** — the only data input is committed files under `data/`.

---

### Integration Points

| Existing file | Change required |
|---------------|----------------|
| `index.html` | Remove import control; update title/heading to "SAGE". |
| `app.js` | Remove import handler, merge function, and related imports; update title text. |
| `js/loader.js` | Update `loadAllSources()` to implement CSV-preferred fetch by source name. |
| `config/sources.json` | Change from `file`-based to `name`-based source entries. |
| `styles.css` | Remove `.import-control` rule. |
| `rooms.json` | Move to `data/json/day1.json`. |
| `room2.json` | Move to `data/json/day2.json`. |
| `test.html` | Update if loader API signature changes. |

---

## Error Handling

| Scenario | Handling |
|----------|----------|
| CSV file not found (404) | Silently fall back to JSON — this is the expected behavior when only JSON exists for a source. |
| JSON file also not found | Record error for that source; continue loading other sources. Display partial data with warning. |
| CSV parse error (malformed rows) | Skip invalid rows; show count in status message. |
| All sources fail | Show "No schedule data available" empty state. |
| Unknown VS in color map | Falls back to `_default` color (existing behavior). |

---

## Testing Strategy

1. **Manual browser testing** — serve locally, verify:
   - Data loads from `data/json/` files (JSON fallback path).
   - When a CSV file is placed in `data/csv/`, it takes precedence over the JSON.
   - No file upload control is visible anywhere in the UI.
   - Page header shows "SAGE".
   - Browser tab title includes "SAGE".
   - All existing filtering, color coding, legend, and time indicator work as before.

2. **Update `test.html`** — adjust any loader tests to exercise the new CSV-preferred loading path.

3. **Regression** — confirm all existing smoke tests still pass.

**Edge cases to verify**:
- Source with CSV only (no JSON fallback file) — should work.
- Source with JSON only (no CSV file) — should work via fallback.
- Source with both CSV and JSON — CSV should be used.
- Malformed CSV file — should be handled gracefully with error reporting.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| 404 fetch for missing CSV creates noisy DevTools errors | Medium | Low (cosmetic) | Use a `HEAD` request first or catch the 404 silently. Document this is expected behavior. |
| Contributors put files in wrong directory | Low | Low | Document the convention in README. `sources.json` makes the expected names explicit. |
| Moving data files breaks existing bookmarks/links to `rooms.json` | Low | Low | This is an internal tool; no external consumers of the raw JSON. |

---

## Handoff

**Artifact saved**: `artifacts/2026-03-19-sage-branding-data-reorg-architecture.md`

**Path signal**: unexpectedly simple (localized changes, no new abstractions) → consider @ema-planner-lite instead

> 📋 **Model**: Select **Gemini 3 Flash** before invoking `@ema-planner-lite`

**Upstream artifacts**:
- Requirements: `artifacts/2026-03-17-schedule-requirements.md` (updated 2026-03-19 to remove CSV upload, add SAGE branding, add data folder structure)

**Context for @ema-planner**:
- Chosen approach: Name-based convention with CSV-preferred fetch — minimal code changes, no new modules
- Files to create:
  - `data/json/day1.json` — moved from `rooms.json` (same content)
  - `data/json/day2.json` — moved from `room2.json` (same content)
  - `data/csv/` — empty directory (placeholder for future CSV data files)
- Files to modify:
  - `config/sources.json` — change from `file`-based to `name`-based source entries
  - `js/loader.js` — update `loadAllSources()` to try `data/csv/{name}.csv` first, fall back to `data/json/{name}.json`
  - `app.js` — remove `handleImportChange()`, `mergeImportedEvents()`, import-related imports, and `importInput` listener; update title from "PI Planning Schedule" to "SAGE"
  - `index.html` — remove file import control block; change `<title>`, `<h1>`, and eyebrow to "SAGE" branding
  - `styles.css` — remove `.import-control` rule (optional cleanup); no other visual changes
  - `test.html` — update loader tests if API signature changes
- Files to delete:
  - `rooms.json` — moved to `data/json/day1.json`
  - `room2.json` — moved to `data/json/day2.json`
- Key integration points:
  - `js/loader.js` `loadAllSources()` at line ~204 — this is where the fetch strategy changes
  - `app.js` `handleImportChange()` at line ~192 — remove entirely
  - `app.js` `mergeImportedEvents()` at line ~185 — remove entirely
  - `app.js` import statement at line 1 — remove `normalizeRecord` and `parseCsv` imports
  - `app.js` listener binding at line ~262 — remove `importInput.addEventListener`
  - `app.js` `updateTitle()` at line ~66 — change "PI Planning Schedule" to "SAGE"
  - `index.html` lines 34–37 — remove the `.import-control` label block
  - `index.html` line 6 — change `<title>` to "SAGE"
  - `index.html` line 12 — update eyebrow text
  - `index.html` line 13 — change `<h1>` default text to "SAGE"
- Testing strategy: manual browser testing + updated `test.html`; verify CSV-preferred loading, SAGE branding, no upload control
- Conventions to follow: vanilla JS with ES modules; `const`/`let`; `async`/`await` for fetches; DOM APIs over `innerHTML`

**Files the planner must verify exist before writing the plan**:
- `index.html` — confirm import control location and title elements
- `app.js` — confirm `handleImportChange`, `mergeImportedEvents`, and import listener locations
- `js/loader.js` — confirm `loadAllSources()` signature and current fetch logic
- `config/sources.json` — confirm current format
- `rooms.json` — confirm it exists at root and contains day 1 data
- `room2.json` — confirm it exists at root and contains day 2 data
- `styles.css` — confirm `.import-control` rule exists

**What @ema-planner should do**:
1. Read this architecture artifact at `artifacts/2026-03-19-sage-branding-data-reorg-architecture.md`
2. Read `artifacts/2026-03-17-schedule-requirements.md` for updated requirements
3. Verify the listed files exist and match the descriptions
4. Produce a step-by-step plan with exact file paths, function signatures, and commit messages
5. Save plan to `artifacts/2026-03-19-sage-branding-data-reorg-plan.md`
