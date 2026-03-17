# Architecture Design — Schedule Viewer Refactor

## Summary

Refactor the PI Planning schedule viewer from a single-file app loading one hardcoded JSON into a modular, multi-source schedule viewer with CSV import, hierarchical team/value-stream filtering, per-day navigation, per-VS color coding, and a current-time indicator — all remaining a pure static site suitable for GitHub Pages.

The chosen approach (Approach A) uses native ES Modules (`<script type="module">`) to split logic into focused files without any build tooling.

## Codebase Context

### Files examined

| File | Purpose | Key findings |
|------|---------|--------------|
| `index.html` | Entry point | Loads `script.js`, has 1 search input + 1 team dropdown; title hardcoded to "day 1" |
| `script.js` | All app logic (88 lines) | Fetches only `rooms.json`; renders cards via `innerHTML` (XSS surface); filter is flat team-match + text search |
| `styles.css` | Styling (95 lines) | Responsive card grid, fade animations; no color palette, no CSS variables, no legend |
| `rooms.json` | Day 1 data (36 entries) | Fields: `time`, `location`, `product`, `team`, `vs`, `type`; **no `date` field**; `time` is free-text range ("11:30-16:00") |
| `room2.json` | Day 2 data (36 entries) | Same schema; **not loaded by the app**; naming inconsistencies vs day 1 (e.g., "Plenary Exp Runway" vs "Plenary Exp RW", "Experimentation Runway" vs "Exp RW") |

### Patterns and conventions

- Pure vanilla JS, no framework, no build step, no dependencies.
- DOM manipulation via `document.createElement` and `innerHTML`.
- Global mutable state (`roomsData`, `currentCards`).
- No modular structure — everything in one script.
- CSS uses fixed values, no custom properties.

### Data shape observations

The current JSON uses a `time` field (e.g., `"09:00-09:50"`) that encodes both start and end. No `date` field exists — files are implicitly per-day. The `team` field doubles as a classifier: `"ALL"` and `"Every One"` denote global plenaries; `"Plenary PLM"` denotes VS-level plenaries; regular names (`"MSFT"`, `"Marvels"`) denote team breakouts.

### Security observation

`renderRooms()` uses `card.innerHTML` with unsanitized data from template literals. This is safe when data comes solely from committed JSON files, but **CSV import introduces user-supplied data**, creating an XSS vector. The new design must sanitize or avoid `innerHTML` for data fields.

---

## Design Approaches Considered

### Approach A: ES Modules, multi-file structure ⭐ (recommended)

**Description**: Split `script.js` into focused ES Module files loaded via `<script type="module" src="app.js">`. Each module handles one concern: data loading, filtering, rendering, URL state, time indicator. No build step — browsers load modules natively.

**File structure**:
```
index.html                 — entry point, <script type="module" src="app.js">
app.js                     — orchestrator: init, event binding, main flow
js/
  loader.js                — loadJson(), parseCsv(), normalize(), merge()
  filter.js                — filterEvents(), buildHierarchy()
  url-state.js             — readState(), writeState() (query string + localStorage)
  renderer.js              — renderCards(), renderLegend(), escapeHtml()
  time-indicator.js        — insertIndicator(), startUpdater()
config/
  colors.json              — VS → { bg, border, text } mapping
  sources.json             — list of { file, defaultDate } for JSON sources
rooms.json                 — day 1 data (migrated: add "date" field)
room2.json                 — day 2 data (migrated: add "date" field)
styles.css                 — expanded with CSS variables, card color rules, legend, indicator
```

**Pros**:
- Clean separation of concerns — each file is independently understandable and testable.
- No build tooling required — `<script type="module">` is supported by all modern browsers (Chrome 61+, Firefox 60+, Safari 11+, Edge 79+); GitHub Pages serves `.js` files with correct MIME type.
- Easy to extend: adding a timeline view later means adding one module and a render mode toggle.
- `import`/`export` makes dependencies explicit and prevents global pollution.

**Cons**:
- Each module is a separate HTTP request on first load (~6 small files). Acceptable for this scale; HTTP/2 multiplexing on GitHub Pages mitigates it.
- Developers unfamiliar with ES modules may need a brief intro (minimal learning curve).

---

### Approach B: Single-file expansion (keep everything in `script.js`)

**Description**: Expand `script.js` with clearly commented sections: data loading, normalization, CSV parsing, filtering, rendering, URL state, time indicator. All functions remain in one file.

**Pros**:
- Fewest files changed — minimal structural disruption.
- No module system to understand.
- Single `<script>` tag.

**Cons**:
- File grows to 400–600+ lines, becoming hard to navigate and maintain.
- No isolation — all functions share one scope; naming collisions become likelier as the file grows.
- Harder to test pieces in isolation.
- Adding the timeline view later means this file grows further.

---

### Approach C: Multiple `<script>` tags with a global namespace

**Description**: Split into multiple `.js` files, each loaded via a separate `<script>` tag in `index.html`. Files attach their exports to a shared global object (`window.Sage = {}`). Load order managed manually.

**Pros**:
- Works in every browser, including very old ones.
- Provides some separation of concerns.

**Cons**:
- Manual load ordering in HTML is fragile and error-prone.
- Global namespace pollution (`window.Sage.loader`, `window.Sage.filter`, etc.).
- No `import`/`export` — dependencies are implicit, not enforced.
- Strictly worse than ES modules for any modern browser target.

---

## Chosen Design

**Approach A — ES Modules, multi-file structure.**

Reason: It is the simplest design that provides real modularity without a build step. The browser support requirement (modern browsers for GitHub Pages) is easily met. The modular structure makes it straightforward to add a timeline view in a future phase, and to test individual modules.

---

### Canonical Event Schema

Every event record, whether parsed from JSON or CSV, is normalized to this shape before it enters the filter or renderer:

```js
{
  id:       string,   // deterministic: hash of (date + start + team + location)
  date:     string,   // "YYYY-MM-DD" — required
  start:    string,   // "HH:mm" — required
  end:      string,   // "HH:mm" — required
  team:     string,   // required
  vs:       string,   // required (may be "" for global plenaries)
  product:  string,   // required
  location: string,   // required
  type:     string,   // "Plenary" | "Breakout" | "Presentation" | ...
  source:   string    // optional — origin filename or "csv-import"
}
```

Migration for existing JSON files: split the existing `time` field (`"09:00-09:50"`) into `start` and `end`, and add a `date` field. The loader handles this via `sources.json` which provides a `defaultDate` per file.

---

### Components

#### 1. `js/loader.js` — Data Loading & Normalization

**Responsibilities**:
- `loadJsonSource(url, defaultDate)` — fetches a JSON file, returns raw array.
- `parseCsv(csvString)` — parses CSV text into an array of objects using the header row as keys. Handles quoted fields containing commas. Expected headers: `date,start,end,team,vs,product,location,type` (case-insensitive matching). If a `time` column is present instead of `start`/`end`, it splits on `-`.
- `normalizeRecord(raw, source, defaultDate)` — maps a raw object to the canonical schema. Splits `time` into `start`/`end` if needed. Applies `defaultDate` if record has no `date`. Generates deterministic `id`. Returns `null` for invalid records (logs warning).
- `validateRecord(record)` — checks all required fields are non-empty strings and `date`/`start`/`end` match expected formats. Returns `{ valid: boolean, errors: string[] }`.
- `loadAllSources(sourcesConfig)` — fetches `sources.json`, then loads each configured file, normalizes all records, merges, and deduplicates by `id`.

**CSV safety**: all parsed string values are trimmed. No `innerHTML` usage in the loader — data is plain strings.

#### 2. `js/filter.js` — Hierarchical Filtering

**Responsibilities**:
- `buildHierarchy(events)` — scans all events and returns a structure:
  ```js
  {
    valueStreams: {
      "PLM": ["MSFT", "PMS BEV", "PMS DQ", "Marvels", ...],
      "R&D": ["CTIS dev team", "Data Wizards", ...],
      ...
    },
    dates: ["2026-03-17", "2026-03-18"],
    types: ["Plenary", "Breakout", "Presentation"]
  }
  ```
  Teams whose name starts with "Plenary" or equals "ALL"/"Every One" are excluded from the team lists (they are plenaries, not selectable teams).

- `filterEvents(events, { mode, value, date, searchText })` — applies the hierarchical filter logic:

  | `mode` | `value` | Events returned (for selected `date`) |
  |--------|---------|---------------------------------------|
  | `"all"` | — | All events |
  | `"plenary"` | — | Global plenaries only: events where `isGlobalPlenary(e)` is true |
  | `"vs"` | `"PLM"` | Global plenaries + all events where `e.vs === "PLM"` |
  | `"team"` | `"MSFT"` | Global plenaries + VS-level plenaries for MSFT's VS + events where `e.team === "MSFT"` |

- `isGlobalPlenary(event)` — returns `true` if the event is a whole-event plenary: `event.type === "Plenary"` AND (`event.team === "ALL"` OR `event.team === "Every One"` OR `event.vs === ""` OR `event.vs === "Portfolio"`).

- `isVsPlenary(event, vs)` — returns `true` if `event.type === "Plenary"` AND `event.vs === vs`.

**Team filter rule (detailed)**:
When filtering for team "MSFT" (which belongs to VS "PLM"):
1. Include all global plenaries (team "ALL", "Every One", or vs empty/"Portfolio").
2. Include VS-level plenaries for "PLM" (e.g., "Plenary PLM" sessions).
3. Include events where `event.team === "MSFT"`.
4. Do NOT include other teams' breakout sessions in PLM (those appear under VS filter).

This distinction between Team and VS view is intentional — VS view shows the full value stream (all teams), while Team view shows only what's relevant to that specific team.

#### 3. `js/url-state.js` — URL & Preference Persistence

**Responsibilities**:
- `readState()` — reads `URLSearchParams` from `window.location.search` and returns `{ date, mode, value, search }`. Falls back to `localStorage` saved preferences if query string is empty.
- `writeState({ date, mode, value, search })` — updates query string via `history.replaceState()` (no page reload) and saves to `localStorage` under key `"sage-prefs"`.
- URL format: `?date=2026-03-17&mode=team&value=MSFT&search=ePI`
- On fresh page load with no query string: restores last-used `mode`/`value` from `localStorage`; defaults `date` to today (if today has events) or the first available date.

#### 4. `js/renderer.js` — Card Rendering & Colors

**Responsibilities**:
- `renderCards(container, events, colorMap)` — clears the container, creates one card per event, sorted by `start` time. Uses DOM APIs (`createElement`, `textContent`) instead of `innerHTML` to prevent XSS.
- `applyCardColor(cardEl, event, colorMap)` — sets CSS custom properties (`--card-bg`, `--card-border`) on the card element based on the event's `vs` field and the loaded color map.
- `renderLegend(container, colorMap, activeVsList)` — renders a compact legend showing colored swatches for each VS present in the current view.
- `escapeHtml(str)` — utility for any case where HTML insertion is unavoidable (currently not needed if using `textContent` throughout).

**Card HTML structure** (built via DOM APIs):
```html
<div class="room-card" style="--card-bg: #E3F2FD; --card-border: #1565C0;">
  <div class="card-time">09:30 – 11:45</div>
  <h2 class="card-team">MSFT</h2>
  <p class="card-location">Room 15A</p>
  <p class="card-product">ePI</p>
  <p class="card-vs">PLM</p>
  <span class="card-type">Breakout</span>
</div>
```

CSS consumes the custom properties:
```css
.room-card {
  background: var(--card-bg, white);
  border-left: 4px solid var(--card-border, #ccc);
}
```

#### 5. `js/time-indicator.js` — Current Time Bar

**Responsibilities**:
- `insertIndicator(container, events, now)` — determines where the current time falls among sorted events. Inserts a full-width `<div class="time-indicator">` element between the last "past/current" card and the first "upcoming" card in the grid. Shows "▶ Now — HH:mm" label.
- `startUpdater(container, events)` — calls `insertIndicator` immediately, then sets a `setInterval` every 60 seconds to reposition.
- The indicator uses `grid-column: 1 / -1` to span all columns in the responsive grid.
- Only shown when the displayed date is today.

#### 6. `app.js` — Orchestrator

**Responsibilities**:
- On `DOMContentLoaded`:
  1. Fetch `config/colors.json` and `config/sources.json`.
  2. Call `loadAllSources()` to get all normalized events.
  3. Call `buildHierarchy()` to get VS/team/date lists.
  4. Call `readState()` to get initial filter state.
  5. Build the filter UI (date tabs, hierarchical dropdown, search box).
  6. Render cards and legend.
  7. Start the time indicator updater.
  8. Bind event listeners on filter controls → `applyFilters()` → `writeState()` + re-render.
- CSV import flow: file input `change` event → `FileReader` → `parseCsv()` or `JSON.parse()` → `normalizeRecord()` each row → merge into `allEvents` → rebuild hierarchy and re-render.

#### 7. `config/sources.json` — Data Source Registry

```json
{
  "sources": [
    { "file": "rooms.json",  "defaultDate": "2026-03-17" },
    { "file": "room2.json",  "defaultDate": "2026-03-18" }
  ]
}
```

This makes adding new days trivial: add a JSON file and register it here. The `defaultDate` is used only if records in the file lack a `date` field (backward compatibility).

#### 8. `config/colors.json` — VS Color Palette

```json
{
  "PLM":      { "bg": "#E3F2FD", "border": "#1565C0" },
  "R&D":      { "bg": "#E8F5E9", "border": "#2E7D32" },
  "MON":      { "bg": "#FFF3E0", "border": "#E65100" },
  "TLM":      { "bg": "#F3E5F5", "border": "#6A1B9A" },
  "Exp RW":   { "bg": "#FBE9E7", "border": "#D84315" },
  "MTA":      { "bg": "#E0F7FA", "border": "#00695C" },
  "Portfolio": { "bg": "#ECEFF1", "border": "#455A64" },
  "_plenary": { "bg": "#ECEFF1", "border": "#455A64" },
  "_default": { "bg": "#FFFFFF", "border": "#9E9E9E" }
}
```

Global plenaries use `_plenary`. Events with an unknown VS use `_default`. Colors chosen from Material Design for accessibility (sufficient contrast on white text backgrounds). These are also available to override via `localStorage` in a future iteration.

---

### Data Flow

```
                    ┌──────────────┐
                    │ sources.json │
                    └──────┬───────┘
                           │ lists files
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         rooms.json   room2.json   CSV upload
              │            │            │
              └────────────┼────────────┘
                           │
                    ┌──────▼───────┐
                    │  loader.js   │  normalize + validate + merge
                    └──────┬───────┘
                           │
                    allEvents: CanonicalEvent[]
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼──────┐  ┌─▼──────┐  ┌──▼────────────┐
       │ filter.js   │  │ build  │  │ url-state.js   │
       │ filterEvents│  │Hierarchy│ │ readState()    │
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

---

### Integration Points

| Existing file | Change required |
|---------------|----------------|
| `index.html` | Replace `<script src="script.js">` with `<script type="module" src="app.js">`. Add filter controls (date tabs, hierarchical dropdown, file import input, legend container, time-indicator placeholder). Update `<title>`. |
| `styles.css` | Add CSS custom property consumption (`.room-card` background/border from `--card-bg`/`--card-border`). Add `.time-indicator`, `.legend`, `.date-tabs`, `.filter-group`, `.import-control` styles. Expand color palette. Keep existing responsive grid and animation. |
| `script.js` | **Replaced** by `app.js` + modules in `js/`. Can be deleted or kept as a redirect. |
| `rooms.json` | Add `"date": "2026-03-17"` to each entry (or rely on `sources.json` `defaultDate`). |
| `room2.json` | Add `"date": "2026-03-18"` to each entry (or rely on `sources.json` `defaultDate`). |

---

### Filter UI Design

The team/VS dropdown is a single hierarchical `<select>` using `<optgroup>`:

```html
<select id="filterSelect">
  <option value="all">All Activities</option>
  <option value="plenary">Plenary (all-hands)</option>
  <optgroup label="PLM">
    <option value="vs:PLM">All PLM</option>
    <option value="team:MSFT">  MSFT</option>
    <option value="team:PMS BEV">  PMS BEV</option>
    <option value="team:PMS DQ">  PMS DQ</option>
    <option value="team:Marvels">  Marvels</option>
    <!-- ... -->
  </optgroup>
  <optgroup label="R&D">
    <option value="vs:R&D">All R&D</option>
    <option value="team:CTIS dev team">  CTIS dev team</option>
    <!-- ... -->
  </optgroup>
  <!-- ... more VS groups ... -->
</select>
```

This is generated dynamically by `js/controls.js` based on the hierarchy built from data. No hardcoding of teams or VS names.

Date tabs are simple `<button>` elements:
```html
<div class="date-tabs">
  <button class="date-tab active" data-date="2026-03-17">Day 1 — Mar 17</button>
  <button class="date-tab" data-date="2026-03-18">Day 2 — Mar 18</button>
</div>
```

Also generated dynamically from the dates found in data.

---

## Error Handling

| Scenario | Handling |
|----------|----------|
| JSON fetch fails (network/404) | Show inline error message per failed source; continue loading other sources. Display partial data with warning banner. |
| CSV parse error (malformed rows) | Skip invalid rows; count and show summary ("3 of 50 rows skipped — missing required fields"). |
| Missing required fields in record | `validateRecord()` returns errors; `normalizeRecord()` returns `null`; record is excluded. |
| Unknown VS in color map | Falls back to `_default` color. |
| Empty data set (all sources fail) | Show "No schedule data available. Try importing a CSV file." with the import control prominently visible. |
| XSS in imported CSV values | All rendering uses `textContent` (DOM API), never `innerHTML` with data values. Template strings are used only for static HTML structure. |

---

## Testing Strategy

Since this is a pure static site with no build step, testing options are:

1. **Manual browser testing** — open `index.html` via a local server (`python -m http.server` or VS Code Live Server), verify:
   - Both JSON files load and merge correctly.
   - Filter dropdown shows correct hierarchy.
   - Each filter mode returns the expected events.
   - CSV upload works with a sample CSV file.
   - Colors match the VS mapping.
   - Time indicator appears when viewing today's date.
   - Query string persists and restores state.

2. **Unit tests via a simple test HTML page** (optional but recommended) — create `test.html` that imports the modules and runs assertions:
   - `loader.js`: test `parseCsv()`, `normalizeRecord()`, `validateRecord()` with known inputs.
   - `filter.js`: test `filterEvents()` with each mode against a small fixture dataset.
   - `url-state.js`: test `readState()`/`writeState()` with mocked `location.search`.

3. **Sample CSV file** — create `test-data/sample.csv` with known data for import testing.

**Edge cases to verify**:
- Events with empty `vs` field (global plenaries).
- Team names containing special characters or spaces.
- CSV with quoted fields containing commas.
- date that matches no events (empty view).
- Multiple events at the same time and location.
- Time indicator when current time is before first event, after last, or between events.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| VS naming inconsistencies across JSON files (e.g., "Exp RW" vs "Experimentation Runway") | High — already exists in data | Medium — breaks filtering | Normalize VS names in `loader.js` using an alias map in `sources.json` or a dedicated `vs-aliases.json`. |
| Team naming inconsistencies across days (e.g., "BI Team" vs "DAP BI Team") | Medium | Medium | Same alias-map approach. Document expected naming convention. |
| CSV header variation from upstream | Medium | Low — user-facing error | Auto-map common variants (case-insensitive); show clear error with expected headers. |
| `<script type="module">` not supported in user's browser | Very low (IE11 only) | High — blank page | Add a `<noscript>` and a small fallback `<script nomodule>` that shows "Please use a modern browser." |
| Performance with very large CSV imports (1000+ rows) | Low | Low | Show a warning if parsed rows exceed 500. Cards render via DOM; 500 cards is fine. |

---

## Handoff

**Artifact saved**: `artifacts/2026-03-17-schedule-architecture.md`

**Path signal**: full → @ema-planner

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-planner`

**Upstream artifacts**:
- Requirements: `artifacts/2026-03-17-schedule-requirements.md`

**Chosen approach**: ES Modules multi-file structure — clean separation with no build step; modules loaded natively by the browser via `<script type="module">`.

**Context for @ema-planner**:
- Chosen approach: ES Modules with file structure: `app.js` orchestrator + `js/loader.js`, `js/filter.js`, `js/url-state.js`, `js/renderer.js`, `js/time-indicator.js` + `config/colors.json`, `config/sources.json`
- Files to create:
  - `app.js` — main orchestrator, replaces `script.js`
  - `js/loader.js` — JSON/CSV loading, normalization, validation, merging
  - `js/filter.js` — hierarchical filter logic (all/plenary/vs/team modes)
  - `js/url-state.js` — query string read/write + localStorage persistence
  - `js/renderer.js` — card rendering with DOM APIs (no innerHTML for data), color application, legend
  - `js/time-indicator.js` — current time bar insertion and auto-update
  - `config/colors.json` — VS → color mapping (Material Design palette)
  - `config/sources.json` — registry of JSON data files with default dates
  - `test-data/sample.csv` — sample CSV for testing import
- Files to modify:
  - `index.html` — replace `<script>` tag, add new filter controls HTML, date tabs, import control, legend container
  - `styles.css` — add CSS custom properties for card colors, time indicator, legend, date tabs, filter group; keep existing grid and animations
  - `rooms.json` — optionally add `"date"` field to each record (or rely on `sources.json` defaultDate)
  - `room2.json` — same as above
- Files to delete:
  - `script.js` — functionality moves to `app.js` + modules (can keep as empty redirect or delete)
- Key integration points:
  - `index.html` line 22: `<script src="script.js">` → `<script type="module" src="app.js">`
  - `index.html` line 11: hardcoded `<h1>` → dynamic title set by `app.js`
  - `index.html` lines 13–18: controls div → expanded with date tabs, hierarchical select, import input
  - `styles.css` lines 58–67: `.room-card` → add `background: var(--card-bg, white); border-left: 4px solid var(--card-border, #ccc);`
  - Card rendering in current `script.js` lines 42–52 (`innerHTML`) → replaced by DOM API calls in `js/renderer.js`
  - Filter logic in current `script.js` lines 63–80 → replaced by `js/filter.js` hierarchical filter
- Testing strategy: manual browser testing + optional `test.html` unit test page; create `test-data/sample.csv`
- Conventions to follow: vanilla JS with ES modules; `const`/`let` (no `var`); DOM APIs over `innerHTML` for user data; `async`/`await` for fetches; meaningful function and variable names; JSDoc comments on exported functions

**Files the planner must verify exist before writing the plan**:
- `index.html` — confirm current `<script>` tag location and controls structure
- `script.js` — confirm current filter logic and rendering approach to understand what's being replaced
- `styles.css` — confirm current card styling to understand what CSS needs extending
- `rooms.json` — confirm current data schema and fields
- `room2.json` — confirm day 2 data schema and naming differences
- `artifacts/2026-03-17-schedule-requirements.md` — confirm requirements and success criteria

**What @ema-planner should do**:
1. Read this architecture artifact at `artifacts/2026-03-17-schedule-architecture.md`
2. Read `artifacts/2026-03-17-schedule-requirements.md` for requirements and success criteria
3. Verify the listed files exist and match the descriptions
4. Produce a step-by-step plan with exact file paths, function signatures, and commit messages
5. Save plan to `artifacts/2026-03-17-schedule-plan.md`
