## Summary
Implement the SAGE branding and data reorganization refactor described in `artifacts/2026-03-19-sage-branding-data-reorg-architecture.md`. The codebase already has the modular static-site foundation, filtering, legend, and time indicator; this plan focuses on removing upload-based data entry, moving schedule data into `data/` subfolders, and updating the loader to prefer committed CSV files over JSON fallbacks.

Codebase verification completed before planning:
- Existing files confirmed: `index.html`, `app.js`, `js/loader.js`, `config/sources.json`, `styles.css`, `rooms.json`, `room2.json`, `test.html`
- Actual current state matches the architecture handoff:
  - `index.html` still renders a file upload control with `id="importInput"`
  - `app.js` still imports `normalizeRecord` and `parseCsv`, defines `mergeImportedEvents()` and `handleImportChange()`, and binds the import input change event
  - `js/loader.js` still expects `config/sources.json` entries with a `file` property and loads JSON only
  - `config/sources.json` still lists `rooms.json` and `room2.json` from the repo root
  - `rooms.json` and `room2.json` still exist at the workspace root and have not yet been moved under `data/json/`
  - `styles.css` does not contain a dedicated `.import-control` rule, so style cleanup is optional and limited to removing now-unused layout assumptions if needed

## Steps

### Step 1: Reorganize committed data files under `data/`
- **File**: `data/json/day1.json` (create)
- **Changes**: Copy the current contents of `rooms.json` into `data/json/day1.json` without changing record structure. Keep the existing legacy shape (`time`, `team`, `vs`, `topics`, `location`, `type`) so the current normalizer continues to work.
- **Rationale**: This establishes the required repository data layout while avoiding an unrelated data-schema migration.
- **Tests**: Validate that `data/json/day1.json` is valid JSON and contains the same number of rows as `rooms.json`.
- **Commit message**: `refactor(data): move day 1 schedule into data json folder`

- **File**: `data/json/day2.json` (create)
- **Changes**: Copy the current contents of `room2.json` into `data/json/day2.json` unchanged.
- **Rationale**: Keeps day 2 aligned with the new data layout and preserves the existing legacy compatibility path.
- **Tests**: Validate that `data/json/day2.json` is valid JSON and contains the same number of rows as `room2.json`.
- **Commit message**: `refactor(data): move day 2 schedule into data json folder`

- **File**: `data/csv/` (create directory)
- **Changes**: Create the directory even if initially empty.
- **Rationale**: The loader’s preferred path depends on this directory existing as the canonical CSV location.
- **Tests**: Confirm the directory exists in the repo and can host files such as `data/csv/day1.csv` in later releases.
- **Commit message**: `chore(data): add csv data directory`

- **File**: `rooms.json` (delete)
- **Changes**: Remove the root-level day 1 file after `data/json/day1.json` is in place.
- **Rationale**: Avoid duplicate schedule sources and ambiguity about the canonical data location.
- **Tests**: Confirm no config or loader code still references `rooms.json` directly.
- **Commit message**: `refactor(data): remove legacy root day 1 file`

- **File**: `room2.json` (delete)
- **Changes**: Remove the root-level day 2 file after `data/json/day2.json` is in place.
- **Rationale**: Same as day 1 — a single canonical location prevents drift.
- **Tests**: Confirm no config or loader code still references `room2.json` directly.
- **Commit message**: `refactor(data): remove legacy root day 2 file`

### Step 2: Convert the source registry to logical names
- **File**: `config/sources.json` (modify)
- **Changes**: Replace the current `file`-based entries with `name`-based entries:
  - `{ "name": "day1", "defaultDate": "2026-03-17" }`
  - `{ "name": "day2", "defaultDate": "2026-03-18" }`
- **Rationale**: The loader should derive both CSV and JSON paths from the logical source name rather than hardcoding one format path in config.
- **Tests**: Validate the JSON shape and confirm every listed `name` matches the newly created `data/json/*.json` filenames.
- **Commit message**: `refactor(config): switch schedule sources to logical names`

### Step 3: Update the loader to prefer CSV and fall back to JSON
- **File**: `js/loader.js` (modify)
- **Changes**: Refactor the loading layer to support the new source convention and file preference order.
- **Changes**: Introduce or adjust the following functions:
  - `async function fetchSourceText(path)` for text-based fetches when loading CSV
  - `async function loadJsonSource(path)` to fetch and parse a JSON array by direct path string
  - `async function loadSourceRecords(sourceConfig)` that:
    1. derives `csvPath` as ``data/csv/${sourceConfig.name}.csv``
    2. derives `jsonPath` as ``data/json/${sourceConfig.name}.json``
    3. tries the CSV path first
    4. falls back to JSON when the CSV path is missing or non-OK
    5. returns both the loaded rows and a `sourceLabel` reflecting the actual file used
  - `export async function loadAllSources(sourcesConfig)` updated to call `loadSourceRecords(sourceConfig)` instead of the current JSON-only path
- **Changes**: Keep `parseCsv()`, `normalizeRecord()`, `validateRecord()`, and existing alias normalization behavior unchanged unless a small signature adjustment is required.
- **Changes**: Ensure `normalizeRecord()` receives the actual loaded file label, e.g. `data/csv/day1.csv` or `data/json/day1.json`, so the `source` field remains accurate.
- **Rationale**: This is the core behavior change: repo-committed CSV should override JSON automatically without changing any UI or deployment model.
- **Tests**: Cover these scenarios in browser smoke tests or targeted checks:
  - JSON fallback works when `data/csv/day1.csv` is absent
  - CSV takes precedence when a same-name file exists under `data/csv/`
  - malformed CSV rows are skipped, not fatal
  - missing source in both folders yields a warning but does not abort other sources
- **Commit message**: `feat(loader): prefer csv schedule sources with json fallback`

### Step 4: Remove upload-based data entry from the application shell
- **File**: `index.html` (modify)
- **Changes**: Remove the `<label class="filter-group import-control">` block containing the `importInput` file field.
- **Changes**: Update branding text:
  - `<title>` from `PI Planning Schedule` to `SAGE`
  - eyebrow copy from `Static event schedule` to concise SAGE-aligned text such as `Schedule viewer`
  - `<h1 id="pageTitle">` default text from `PI Planning Schedule` to `SAGE`
- **Rationale**: The UI must not offer any file uploads, and the app name must be visible in the interface and browser tab.
- **Tests**: Confirm the DOM no longer contains `#importInput` and the initial page header renders `SAGE` before JS runs.
- **Commit message**: `feat(shell): remove uploads and brand app as sage`

- **File**: `app.js` (modify)
- **Changes**: Remove upload-related imports from the first line so only `loadAllSources` remains imported from `./js/loader.js`.
- **Changes**: Update `getElements()` to stop querying `importInput`.
- **Changes**: Remove `mergeImportedEvents(events)` entirely.
- **Changes**: Remove `async function handleImportChange(event)` entirely.
- **Changes**: In `initializeApp()`, remove `importInput` from the destructured elements and remove `importInput.addEventListener("change", handleImportChange)`.
- **Changes**: Update `updateTitle()` so both the visible title and `document.title` include `SAGE`, for example `SAGE - Day 1` instead of `PI Planning Schedule - Day 1`.
- **Changes**: Keep all date tab, search, scope filtering, legend, and time-indicator behavior unchanged.
- **Rationale**: The application should only render repo-committed schedule data; removing import logic from the orchestrator eliminates the forbidden UX path and dead code.
- **Tests**: Confirm `app.js` compiles without unused imports or null lookups, and verify the app still initializes with the existing JSON fallback path.
- **Commit message**: `refactor(app): remove runtime imports and apply sage branding`

### Step 5: Align smoke tests and static content with the new loading model
- **File**: `test.html` (modify)
- **Changes**: Keep the parser and normalizer assertions, but add or adjust loader-oriented checks to reflect the new contract if helper signatures change.
- **Changes**: Update visible page copy from `Schedule Smoke Tests` to `SAGE Smoke Tests` for consistency.
- **Changes**: Add a short manual verification note in the page body or comments indicating that CSV precedence is validated by placing a same-name file under `data/csv/`.
- **Rationale**: The smoke test page is the repo’s lightweight regression harness; it should reflect the new branding and loader behavior.
- **Tests**: Open `test.html` via a local static server and confirm all assertions still pass after the loader refactor.
- **Commit message**: `test(ui): align smoke tests with sage data loading`

- **File**: `styles.css` (modify)
- **Changes**: Remove or simplify any now-unused import-related styling hooks if they exist after the HTML cleanup. Keep the current pleasant visual system otherwise.
- **Rationale**: Avoid stale selectors after the import control is removed, but do not introduce unnecessary visual churn.
- **Tests**: Confirm the controls grid still lays out cleanly with two inputs instead of three at mobile and desktop widths.
- **Commit message**: `style(ui): clean up layout after upload removal`

### Step 6: Document and verify the new repo-driven data workflow
- **File**: `README.md` (modify)
- **Changes**: Add or update a short section describing the new data convention:
  - committed data lives under `data/csv/` and `data/json/`
  - source names are declared in `config/sources.json`
  - the app prefers `data/csv/{name}.csv` and falls back to `data/json/{name}.json`
  - no upload UI exists; schedule updates ship via repository changes/releases
- **Rationale**: The architecture explicitly calls out the need to document the convention so contributors know where to place schedule files.
- **Tests**: Verify the README instructions match the actual folder layout and loader behavior after implementation.
- **Commit message**: `docs(readme): document repo based schedule data workflow`

## Testing Approach
Use the existing static-site verification style and keep testing focused on behavior rather than implementation details.

1. Start a local static server from the workspace root.
Example command:
```powershell
npx http-server . -p 8000
```

2. Verify the main app in the browser.
- Open `http://127.0.0.1:8000/index.html`
- Confirm the header shows `SAGE`
- Confirm no file upload control appears
- Confirm the schedule loads from `data/json/day1.json` and `data/json/day2.json`
- Confirm filters, legend, and current-time indicator still behave as before

3. Verify CSV precedence manually.
- Add a temporary `data/csv/day1.csv` using the canonical header format
- Refresh the app and confirm the day 1 view reflects CSV data instead of `data/json/day1.json`
- Remove the temporary CSV and confirm JSON fallback resumes

4. Verify the smoke test page.
- Open `http://127.0.0.1:8000/test.html`
- Confirm all existing assertions pass after the loader and branding changes

## Handoff

**Artifact saved**: `artifacts/2026-03-19-sage-branding-data-reorg-plan.md`

**Upstream artifacts**:
- Architecture: `artifacts/2026-03-19-sage-branding-data-reorg-architecture.md`
- Requirements: `artifacts/2026-03-17-schedule-requirements.md`

**Context for @ema-implementer**:
- 6 steps to execute
- Files to create:
  - `data/json/day1.json`
  - `data/json/day2.json`
- Directories to create:
  - `data/csv/`
  - `data/json/`
- Files to modify:
  - `config/sources.json`
  - `js/loader.js`
  - `index.html`
  - `app.js`
  - `test.html`
  - `styles.css`
  - `README.md`
- Files to delete:
  - `rooms.json`
  - `room2.json`
- Test command: `npx http-server . -p 8000`
- Test framework: browser smoke page in `test.html` plus manual browser verification of `index.html`
- Watch for: the loader must not abort all sources when CSV is missing for one source; `source` metadata should reflect the actual loaded file path; removing the import input requires cleaning up all `document.getElementById("importInput")` usage so initialization does not dereference `null`

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-implementer`

**What @ema-implementer should do**:
1. Read this plan artifact at `artifacts/2026-03-19-sage-branding-data-reorg-plan.md`
2. Read the architecture artifact for background context only — do not second-guess the design
3. Execute each step atomically — stage changes but do NOT commit — and run the static-site verification flow after each meaningful step
4. Document any deviations in the implementation summary
5. Save the implementation summary to `artifacts/2026-03-19-sage-branding-data-reorg-implementation.md`
