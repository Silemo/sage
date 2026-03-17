## Goal
Create a simple, static GitHub Pages-friendly schedule viewer that supports CSV import, team/value-stream aggregation, per-day pages, basic filters, and an accessible color palette — keeping the existing one-card-per-activity UI and adding minimal structure for multi-source data.

## Codebase Context
- Current site is a static HTML/JS/CSS app: [index.html](index.html#L1), [script.js](script.js#L1), [styles.css](styles.css#L1).
- Sample data lives in JSON files: [rooms.json](rooms.json#L1) and [room2.json](room2.json#L1); the app currently fetches only `rooms.json`.
- `script.js` renders card-based entries from a flat JSON array; times are free-text (e.g., "11:30-16:00").
- No CSV import, no date field per event, no color mapping or legend.

## Scope
- Canonical event schema (required fields):
  - `id` (string), `date` (YYYY-MM-DD), `start` (HH:mm), `end` (HH:mm), `team`, `vs`, `product`, `location`, `type`, `source` (optional)
- Loader that accepts:
  - JSON files matching the canonical schema, and
  - CSV files with a header mapping (import UI will map column names to the canonical schema)
- Filtering behavior (per your spec):
  - All activities: show every event
  - Plenary: show only sessions where `type` === "Plenary" or where `team` is a plenary value (e.g., `ALL`)
  - Value stream: show plenary + events where `vs` matches the selected value stream
  - Team: show plenary + value stream + events where `team` matches the selected team
- One card per activity; pages are per-day (URL pattern: `?date=YYYY-MM-DD` or simple separate HTML pages). Use query string to persist user selections (team/vs/type).
- Filters: `date` (day selector), `team` (dropdown), `value stream` (dropdown), `type` (dropdown), free-text search.
- Visuals: per-`vs` color mapping with accessible palette, legend, and CSS variables for easy theme tuning.
- UI affordance: current time indicator bar on the page for the displayed day.

## Out of Scope
- Horizontal timeline visualization (deferred to next phase)
- Server-side components or build tooling — the solution must remain a static site
- Complex persistence (no DB); only `localStorage` for user preferences
- Retry/import validation beyond simple schema checks

## Constraints
- Must remain a static, client-side site (no build step, no bundlers).
- Event sources will include a `date` field (assumption you confirmed). Implement validation and reject incomplete rows.
- Keep dependencies to a minimum; prefer a tiny CSV parser (e.g., small, single-file library) or build a simple CSV parser in-place.
- Support GitHub Pages hosting and direct file fetch of JSON assets.

## Approach
1. Add a small `data-loader` module in `script.js` (or `loader.js`) that:
   - Can fetch one or more JSON files and merge them, and
   - Accepts uploaded CSV files and maps headers to the canonical schema (reporting and skipping invalid rows).
2. Normalize all records into the canonical schema (generate `id` if missing).
3. Update filtering logic:
   - Implement selection modes (All / Plenary / VS / Team) and the aggregation rules you provided.
   - Use the query string to persist `date`, `team`, `vs`, and `type` (read/write helpers).
4. Date handling: treat each `date` as separate page/state. Default to today or first date found in data.
5. UI changes:
   - Keep card layout. Group cards by day when switching dates.
   - Add a compact legend and color swatches for each `vs` (CSS variables and a `colors.json` mapping file optionally).
   - Add a horizontal current-time indicator bar that positions itself relative to the day's earliest/latest known time range (or shows a marker at nearest card).
6. CSV import UI: small file input control and mapping dialog that suggests column matches; store last-used mapping in `localStorage`.

Why this approach: minimal friction, keeps the site static, and delivers CSV + aggregation + multi-day page support quickly while leaving advanced timeline visuals for a second iteration.

## Success Criteria
- Selecting a team shows: plenary + events for that team's `vs` + events where `team` matches the team.
- CSV files that match the schema (or are mappable) display correctly after import.
- Users can navigate days via query string (e.g., `?date=2026-03-17`) and bookmarks preserve filters.
- Visual legend and per-`vs` colors appear and are easy to edit (CSS variables or `colors.json`).
- A current time indicator is visible for the displayed date and helps locate upcoming events.

## Risks and Considerations
- CSV column-name variability: provide a mapping UI and clear error messages for rejected rows.
- Time parsing edge cases (different locales): document required time format (24-hour `HH:mm`) and validate on import.
- Large CSVs in the browser may be slow; add a warning for very large files.

## Open Questions
- Preferred CSV header names you expect from upstream (helpful to provide 1-2 example CSVs for testing).
- Do you prefer per-`team` colors instead of per-`vs`? (current plan uses `vs` as primary color grouping.)

## Handoff
**Artifact saved**: c:\Users\manfredig\IdeaProjects\sage\artifacts\2026-03-17-schedule-requirements.md

**Next steps I can take**:
- Implement the CSV import and canonical normalization (small PR: add `loader.js`, update `script.js`, add a small `colors.json`, and UI controls in `index.html`).
- Add the current-time indicator and query-string persistence.

If you approve, I'll produce a concrete implementation plan with the exact files to add/modify, example CSV mapping, and a small list of minimal helper functions to implement, then start the changes.
