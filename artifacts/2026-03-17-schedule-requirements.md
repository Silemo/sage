## Goal
Create a simple, pleasant, static GitHub Pages-friendly schedule viewer called **SAGE** (Schedule and Agenda for Group Events) that reads committed data files from the repository, supports team/value-stream aggregation, per-day pages, basic filters, and an accessible color palette — keeping the existing one-card-per-activity UI.

**The interface must not allow any file uploads.** All schedule data lives in the repository under a `data/` folder and is updated via code releases only.

## Codebase Context
- Current site is a static HTML/JS/CSS app using ES Modules: `app.js` orchestrator + modules in `js/` (`loader.js`, `filter.js`, `url-state.js`, `renderer.js`, `time-indicator.js`).
- Data currently lives in root-level JSON files (`rooms.json`, `room2.json`); `config/sources.json` lists them.
- The app has a file import control in `index.html` and import handling in `app.js` — these must be removed.
- Filtering, URL state persistence, color-coded cards, legend, and time indicator are already implemented.
- The title currently says "PI Planning Schedule" — needs to show "SAGE".

## Scope

### Data organization
- All schedule data lives under `data/` with format-specific subfolders:
  - `data/csv/` — CSV files (preferred format when present)
  - `data/json/` — JSON files (fallback when no CSV exists for a source)
- `config/sources.json` lists logical source names; the loader tries `data/csv/{name}.csv` first, then `data/json/{name}.json`.
- Data is committed to the repository and updated via releases — **no user upload, no file input in the UI**.

### Canonical event schema (required fields)
  - `id` (string), `date` (YYYY-MM-DD), `start` (HH:mm), `end` (HH:mm), `team`, `vs`, `topics`, `location`, `type`, `source` (optional)

### Loader behavior
  - Reads from `config/sources.json` which lists logical data sources with `name` and `defaultDate`.
  - For each source, attempts to fetch `data/csv/{name}.csv` first. If that returns 404, falls back to `data/json/{name}.json`.
  - CSV parsing handles the canonical header row: `date,start,end,team,vs,topics,location,type`.
  - JSON loading supports both the canonical schema and the legacy `time` field (split into `start`/`end`).
  - Normalizes all records into the canonical schema (generates `id` if missing).
  - Validates records and skips incomplete rows with warnings.

### Filtering behavior
  - All activities: show every event
  - Plenary: show only sessions where `type` === "Plenary" or where `team` is a plenary value (e.g., `ALL`)
  - Value stream: show plenary + events where `vs` matches the selected value stream
  - Team: show plenary + value stream plenaries for that team's VS + events where `team` matches the selected team

### UI and branding
- The application name **SAGE** must be visible in the page header.
- The page title (browser tab) should include "SAGE".
- Do NOT expand the acronym in the interface — just show "SAGE".
- One card per activity; pages are per-day via query string (`?date=YYYY-MM-DD`). URL persists user selections (day/scope/search).
- Filters: date selector (day tabs), hierarchical scope dropdown (All / Plenary / VS / Team), free-text search.
- Visuals: per-`vs` color mapping with accessible palette, legend, and CSS variables for easy theme tuning.
- Current time indicator bar on the page for the displayed day.
- Simple, clean, and pleasant interface — no unnecessary complexity.
- **No file upload control anywhere in the UI.**

## Out of Scope
- Horizontal timeline visualization (deferred to next phase)
- Server-side components or build tooling — the solution must remain a static site
- Complex persistence (no DB); only `localStorage` for user preferences
- CSV upload or any file import UI — data is managed in the repository

## Constraints
- Must remain a static, client-side site (no build step, no bundlers).
- Keep dependencies to a minimum; the built-in CSV parser handles repo-committed files only.
- Support GitHub Pages hosting and direct file fetch of data assets.
- Data files are committed to the repo under `data/csv/` and `data/json/`.

## Approach
1. Reorganize data into `data/json/` and `data/csv/` folders (move existing JSON files).
2. Update `config/sources.json` to use logical source names with the CSV-preferred loading convention.
3. Update `js/loader.js` to try CSV first, then JSON for each source.
4. Remove the file import control from `index.html` and the import handler from `app.js`.
5. Update branding to show "SAGE" in the page header and browser title.
6. Keep the existing card layout, filtering, legend, color coding, and time indicator.

Why this approach: all data is version-controlled alongside the code, removing any need for user-facing import. The CSV-preferred loading lets data maintainers use whichever format is most convenient, with CSV being the simpler choice for tabular schedule data.

## Success Criteria
- Selecting a team shows: plenary + VS-level plenaries for that team's VS + events where `team` matches.
- The loader reads CSV files from `data/csv/` when present, falls back to `data/json/`.
- Users can navigate days via query string (e.g., `?date=2026-03-17`) and bookmarks preserve filters.
- Visual legend and per-`vs` colors appear and are easy to edit (`config/colors.json`).
- A current time indicator is visible for the displayed date and helps locate upcoming events.
- The page header shows "SAGE" and the browser title includes "SAGE".
- There is **no file upload control** anywhere in the interface.
- The interface is simple, clean, and pleasant to use.

## Risks and Considerations
- Time parsing edge cases (different locales): required time format is 24-hour `HH:mm`; validation rejects non-conforming rows.
- VS naming inconsistencies between data files: loader normalizes known aliases (e.g., "Experimentation Runway" → "Exp RW").
- Adding new days requires committing a data file and updating `config/sources.json` — document this in the README.

## Open Questions
- Do you prefer per-`team` colors instead of per-`vs`? (Current plan uses `vs` as primary color grouping.)

## Handoff
**Artifact saved**: `artifacts/2026-03-17-schedule-requirements.md`

**Next step**: `@ema-architect` to produce the updated architecture design incorporating these requirements.
