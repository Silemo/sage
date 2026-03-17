## Summary
Implement the schedule viewer refactor described in `artifacts/2026-03-17-schedule-architecture.md` using native ES modules and no build step. The implementation will preserve the existing static-site deployment model while adding multi-source loading, CSV import, hierarchical all/plenary/value-stream/team filtering, URL-persisted state, VS-based color styling, and a current-time indicator.

Codebase verification completed before planning:
- Existing files confirmed: `index.html`, `script.js`, `styles.css`, `rooms.json`, `room2.json`, `artifacts/2026-03-17-schedule-requirements.md`, `artifacts/2026-03-17-schedule-architecture.md`
- Actual current state matches the architecture description:
  - `index.html` has one text input, one team dropdown, one cards container, and a plain `<script src="script.js">`
  - `script.js` fetches only `rooms.json`, filters only exact team matches, and renders cards via `innerHTML`
  - `styles.css` contains only base card/grid styling
  - `rooms.json` and `room2.json` still use the legacy schema with `time` and no `date`
- Design discrepancy resolved for implementation:
  - The architecture mentions `js/controls.js` once in the UI section, but it is not part of the chosen module set. The plan keeps control generation inside `app.js` to stay minimal.

## Steps

### Step 1: Add configuration files and sample import data
- **File**: `config/sources.json` (create)
- **Changes**: Add a source registry with entries for `rooms.json` and `room2.json`, each with a `defaultDate` so the loader can normalize the current legacy data without forcing a bulk data rewrite immediately.
- **Rationale**: This decouples the app from hardcoded file names and enables adding more daily JSON files later by configuration only.
- **Tests**: Confirm the file is valid JSON and lists both current source files with the expected dates.
- **Commit message**: `feat(config): add schedule source registry`

- **File**: `config/colors.json` (create)
- **Changes**: Add the VS color palette from the architecture with `_plenary` and `_default` fallbacks.
- **Rationale**: Centralizes the color system so CSS and rendering logic remain simple and editable.
- **Tests**: Confirm the file is valid JSON and contains mappings for current VS values present in `rooms.json` and `room2.json`, including an alias-safe fallback path.
- **Commit message**: `feat(config): add value stream color palette`

- **File**: `test-data/sample.csv` (create)
- **Changes**: Add a small canonical CSV sample with headers `date,start,end,team,vs,product,location,type` and 4-6 representative rows covering global plenary, VS plenary, and team breakout scenarios.
- **Rationale**: Gives a stable smoke-test file for import behavior and manual verification.
- **Tests**: Open the file and confirm quoted values and headers are parseable by the intended CSV parser.
- **Commit message**: `test(data): add sample schedule csv`

### Step 2: Implement data loading, normalization, validation, and CSV parsing
- **File**: `js/loader.js` (create)
- **Changes**: Add named exports for the data layer:
  - `export async function loadJsonSource(sourceConfig)`
  - `export async function loadAllSources(sourcesConfig)`
  - `export function parseCsv(csvText)`
  - `export function normalizeRecord(rawRecord, sourceName, defaultDate)`
  - `export function validateRecord(record)`
  - `export function createEventId(record)`
  - `export function normalizeVsName(valueStream)`
  - `export function normalizeTeamName(teamName)`
- **Changes**: Implement the following behaviors:
  - Fetch JSON arrays from configured files
  - Parse CSV rows with support for quoted commas and trimmed values
  - Accept both canonical fields (`date`, `start`, `end`) and current legacy JSON shape (`time`) by splitting `time` on `-`
  - Apply `defaultDate` from `config/sources.json` when a record lacks `date`
  - Normalize inconsistent VS values already present in the repo, especially `Exp RW` vs `Experimentation Runway`
  - Optionally normalize known team aliases only where required for filter coherence; keep this conservative to avoid accidental data merging
  - Validate required fields and skip invalid records with structured error reporting
  - Deduplicate merged records by deterministic `id`
- **Rationale**: This is the core compatibility layer that lets the app support both current JSON files and future CSV-based inputs without forcing upstream format migration on day one.
- **Tests**: Use `test-data/sample.csv` plus the existing JSON files to verify:
  - legacy `time` strings become `start` and `end`
  - `defaultDate` fills missing dates for current JSON
  - invalid CSV rows are rejected cleanly
  - `Exp RW` and `Experimentation Runway` normalize to the same VS key
- **Commit message**: `feat(data): add schedule loader and normalization`

### Step 3: Implement filter logic and persisted URL state
- **File**: `js/filter.js` (create)
- **Changes**: Add named exports for filter and hierarchy logic:
  - `export function buildHierarchy(events)`
  - `export function filterEvents(events, filterState)`
  - `export function isGlobalPlenary(event)`
  - `export function isVsPlenary(event, valueStream)`
  - `export function getTeamValueStream(events, teamName)`
  - `export function sortEventsByStart(events)`
- **Changes**: Implement the exact requested behavior:
  - `mode: "all"` returns all events for the selected date
  - `mode: "plenary"` returns only global plenaries
  - `mode: "vs"` returns global plenaries plus all events in the selected VS
  - `mode: "team"` returns global plenaries plus VS-level plenaries for the team’s VS plus that team’s own events
  - Search text should apply on top of the mode/date filter across `team`, `vs`, `location`, and `product`
  - Team lists in the hierarchy must exclude `ALL`, `Every One`, and `Plenary ...` synthetic teams
- **Rationale**: The current app only supports flat exact-team filtering. This module encodes the business semantics you defined and keeps them isolated from DOM code.
- **Tests**: Build a small in-memory fixture and verify each filter mode returns the expected event set, especially the distinction between VS view and Team view.
- **Commit message**: `feat(filters): add hierarchical schedule filtering`

- **File**: `js/url-state.js` (create)
- **Changes**: Add named exports:
  - `export function readState(availableDates)`
  - `export function writeState(state)`
  - `export function normalizeState(rawState, availableDates)`
  - `export function getDefaultDate(availableDates)`
- **Changes**: Persist `date`, `mode`, `value`, and `search` in the query string and mirror them to `localStorage` under a single key such as `sage-schedule-preferences`.
- **Rationale**: This makes bookmarks and refreshes preserve the selected team/VS/day without server support.
- **Tests**: Verify initial load with no query string, with a full query string, and with partially invalid state values.
- **Commit message**: `feat(state): persist schedule filters in url`

### Step 4: Implement safe rendering, legend output, and current-time indicator
- **File**: `js/renderer.js` (create)
- **Changes**: Add named exports:
  - `export function renderCards(container, events, colorMap)`
  - `export function renderLegend(container, colorMap, events)`
  - `export function clearContainer(container)`
  - `export function createRoomCard(event, colorMap)`
  - `export function getEventColor(event, colorMap)`
  - `export function renderEmptyState(container, message)`
  - `export function renderErrorState(container, message)`
- **Changes**: Render each card with DOM APIs and `textContent` only. Do not use `innerHTML` for any user/data-driven values. Preserve the current card layout style but extend it with labels for time, location, product, VS, and type.
- **Rationale**: CSV import turns schedule data into user-controlled input. The renderer must eliminate the XSS risk currently present in `script.js`.
- **Tests**: Verify cards render correctly for imported CSV rows containing special characters like `&`, `<`, `>` without being interpreted as HTML.
- **Commit message**: `feat(ui): add safe event card renderer`

- **File**: `js/time-indicator.js` (create)
- **Changes**: Add named exports:
  - `export function insertIndicator(container, events, selectedDate, now = new Date())`
  - `export function clearIndicator(container)`
  - `export function startIndicatorUpdates(container, getEvents, getSelectedDate)`
  - `export function findIndicatorIndex(events, selectedDate, now)`
- **Changes**: Insert a full-width `time-indicator` row in the card grid only when the selected date is today. Position it before the next upcoming event; if all events are in the past, place it at the end; if all are upcoming, place it at the top.
- **Rationale**: This provides the “what’s next for my team” affordance without introducing a full timeline view.
- **Tests**: Verify indicator placement for before-first-event, between-events, and after-last-event scenarios.
- **Commit message**: `feat(ui): add current time indicator`

### Step 5: Replace the page shell and wire the application together
- **File**: `app.js` (create)
- **Changes**: Create the browser entrypoint that imports all modules and owns app state. Add named top-level functions:
  - `async function initializeApp()`
  - `function buildControls(hierarchy, state)`
  - `function buildDateTabs(dates, selectedDate)`
  - `function buildScopeSelect(hierarchy, state)`
  - `function applyCurrentFilters()`
  - `async function handleImportChange(event)`
  - `function updateView()`
- **Changes**: `initializeApp()` should:
  - fetch `config/sources.json` and `config/colors.json`
  - load and normalize all configured sources
  - build the hierarchy
  - read URL/local storage state
  - build the controls UI dynamically
  - render legend, cards, and time indicator
  - register listeners for search, scope selection, date tabs, and file import
- **Rationale**: This replaces the current global-script architecture with a single module entrypoint while keeping the app static and dependency-light.
- **Tests**: Start the site locally and verify initial render works with both JSON files merged and no console errors.
- **Commit message**: `feat(app): add modular schedule bootstrap`

- **File**: `index.html` (modify)
- **Changes**: Replace the existing minimal controls block with a structure that includes:
  - heading and subtitle containers
  - `date-tabs` container
  - search input
  - hierarchical scope select for All / Plenary / VS / Team
  - file input for CSV/JSON import
  - status/error message container
  - legend container
  - rooms container
  - `<script type="module" src="app.js"></script>` instead of the legacy `script.js`
- **Changes**: Keep markup intentionally lean; dynamic options and date buttons are created in `app.js`.
- **Rationale**: The current HTML does not have anchors for the new controls or feedback states.
- **Tests**: Verify all required elements exist and are discoverable via the IDs expected by `app.js`.
- **Commit message**: `feat(shell): expand page layout for schedule viewer`

### Step 6: Extend styling for colors, controls, legend, and import states
- **File**: `styles.css` (modify)
- **Changes**: Preserve the current responsive card grid and animation behavior, then add:
  - CSS custom properties for page colors and card accent colors
  - stronger visual hierarchy for the page header and control groups
  - styles for `.date-tabs`, `.date-tab`, `.legend`, `.legend-item`, `.legend-swatch`, `.time-indicator`, `.status-message`, `.import-control`, and empty/error states
  - `.room-card` support for `--card-bg` and `--card-border`
  - a slightly richer but still simple palette aligned with `config/colors.json`
- **Rationale**: The current stylesheet is too limited to support color-coded streams, status messaging, or the current-time indicator.
- **Tests**: Verify the UI remains usable on mobile and desktop widths and that the indicator spans all grid columns.
- **Commit message**: `feat(styles): add schedule filters legend and color system`

### Step 7: Retire the legacy script and add lightweight browser smoke tests
- **File**: `script.js` (modify or delete)
- **Changes**: Prefer deletion. If keeping it temporarily is safer for GitHub Pages history, replace its content with a short comment stating it has been superseded by `app.js` and is no longer referenced by `index.html`.
- **Rationale**: Avoid leaving duplicate app logic in the repository.
- **Tests**: Confirm `index.html` no longer references `script.js` and the app still loads.
- **Commit message**: `refactor(app): remove legacy single file script`

- **File**: `test.html` (create)
- **Changes**: Add a lightweight browser-based smoke test page that imports `js/loader.js`, `js/filter.js`, and `js/url-state.js` and runs a few assertions against a tiny fixture dataset, writing pass/fail output to the DOM.
- **Rationale**: There is no existing JS test runner or build step. A simple browser test page provides regression coverage while staying within the static-site constraint.
- **Tests**: Open `test.html` via a local server and confirm all assertions pass.
- **Commit message**: `test(ui): add browser smoke tests for schedule modules`

## Testing Approach
Use a lightweight two-layer testing approach that fits the static-site constraint.

1. Browser smoke tests
- Serve the repo locally with:
```powershell
python -m http.server 8000
```
- Open:
  - `http://localhost:8000/index.html`
  - `http://localhost:8000/test.html`
- Verify the following behaviors:
  - both JSON files load through `config/sources.json`
  - day selection works through query string state
  - All / Plenary / VS / Team modes return the expected events
  - CSV import works with `test-data/sample.csv`
  - current-time indicator appears only for today
  - legend colors match the active VS values

2. Manual edge-case checks
- Import a CSV with an invalid row and confirm it is skipped with an error message.
- Use a query string like `?date=2026-03-17&mode=team&value=MSFT` and confirm refresh preserves the same view.
- Confirm that `Exp RW` and `Experimentation Runway` appear under one normalized VS bucket.
- Confirm a team view does not show other teams’ breakouts from the same value stream.
- Confirm special characters from CSV are rendered as text, not HTML.

## Handoff

**Artifact saved**: `artifacts/2026-03-17-schedule-plan.md`

**Upstream artifacts**:
- Architecture: `artifacts/2026-03-17-schedule-architecture.md`
- Requirements: `artifacts/2026-03-17-schedule-requirements.md`

**Context for @ema-implementer**:
- 7 steps to execute
- Files to create: `config/sources.json`, `config/colors.json`, `test-data/sample.csv`, `js/loader.js`, `js/filter.js`, `js/url-state.js`, `js/renderer.js`, `js/time-indicator.js`, `app.js`, `test.html`
- Files to modify: `index.html`, `styles.css`, `script.js` or delete it
- Files to leave unchanged for now: `rooms.json`, `room2.json` — use `defaultDate` in `config/sources.json` instead of bulk-migrating legacy source data in this first pass
- Test command: `python -m http.server 8000`
- Test framework: browser-based smoke tests + manual verification in `test.html`
- Watch for:
  - Normalize `Exp RW` and `Experimentation Runway` to one VS value without over-normalizing unrelated names
  - Team mode must include global plenaries + VS plenaries + team events only, not the entire value stream
  - Do not use `innerHTML` with imported CSV values
  - Keep the site dependency-free and GitHub Pages compatible
  - Keep control generation inside `app.js`; do not add an extra `js/controls.js` module in this pass

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-implementer`

**What @ema-implementer should do**:
1. Read this plan artifact at `artifacts/2026-03-17-schedule-plan.md`
2. Read `artifacts/2026-03-17-schedule-architecture.md` for design intent and `artifacts/2026-03-17-schedule-requirements.md` for success criteria
3. Execute each step atomically — stage changes but do NOT commit
4. Run the local server command and use `test.html` plus the app UI for verification after the relevant steps
5. Save the implementation summary to `artifacts/2026-03-17-schedule-implementation.md`
