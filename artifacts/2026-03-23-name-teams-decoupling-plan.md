## Summary
Implement the name/teams decoupling described in the architecture artifact so SAGE treats meeting display text separately from filterable teams. The implementation must make the new CSV source [data/csv/2026-03-17.csv](c:/Users/manfredig/IdeaProjects/sage/data/csv/2026-03-17.csv) the proving ground for the new `name` + `teams[]` model while preserving backward compatibility for the existing JSON sources that still use the legacy `team` string.

## Steps

### Step 1: Refactor event normalization for `name` and `teams[]`
- **File**: `js/loader.js` (modify)
- **Changes**:
  - Replace `REQUIRED_FIELDS = ["date", "start", "end", "team", "topics", "location", "type"]` with `REQUIRED_FIELDS = ["date", "start", "end", "name", "topics", "location", "type"]`.
  - Keep `normalizeWhitespace`, `normalizeVsName`, and `normalizeType` as-is, but add a helper such as `parseTeams(rawTeams)` that:
    - Accepts `rawRecord.teams` from CSV or `rawRecord.team` from legacy JSON.
    - Splits comma-separated values.
    - Trims whitespace on each entry.
    - Runs each entry through `normalizeTeamName`.
    - Filters out empty strings.
    - Returns `[]` when the source value is empty.
  - Update `createEventId(record)` so the seed uses `record.name` instead of `record.team`.
  - Update `normalizeRecord(rawRecord, sourceName, defaultDate)` to normalize this shape:
    - `name: normalizeWhitespace(rawRecord.name ?? rawRecord.team)`
    - `teams: parseTeams(rawRecord.teams ?? rawRecord.team)`
    - `vs: normalizeVsName(rawRecord.vs ?? rawRecord["value stream"])`
    - Preserve all existing fields (`date`, `start`, `end`, `topics`, `location`, `type`, `source`, `id`).
  - Do not change `parseCsv()` beyond relying on its current lowercased-header behavior; it already exposes `name`, `teams`, and `value stream` from the new CSV.
  - Preserve JSON backward compatibility: records from [data/json/2026-03-17.json](c:/Users/manfredig/IdeaProjects/sage/data/json/2026-03-17.json) and [data/json/2026-03-18.json](c:/Users/manfredig/IdeaProjects/sage/data/json/2026-03-18.json) must still load even though they only have `team`.
- **Rationale**: The root cause is the overloaded `team` field. Normalizing a dedicated display `name` and a filtering `teams[]` array removes ambiguity once, at the data boundary, instead of scattering split/fallback logic across the UI.
- **Tests**:
  - Add or extend loader-focused assertions to prove:
    - CSV records with `name`, `value stream`, and `teams` normalize correctly.
    - Legacy JSON records without `name` still normalize with `name === team` fallback.
    - Teamless records normalize with `teams.length === 0` and remain valid.
  - Validate that the committed CSV from [data/csv/2026-03-17.csv](c:/Users/manfredig/IdeaProjects/sage/data/csv/2026-03-17.csv) is accepted by `loadAllSources` without validation failures caused by the new shape.
- **Commit message**: `refactor(loader): normalize display name and team arrays`

### Step 2: Rework filtering and hierarchy building around `teams[]`
- **File**: `js/filter.js` (modify)
- **Changes**:
  - Replace `isSelectableTeam(event)` with a helper such as `hasSelectableTeams(event)` that returns `event.teams.length > 0`.
  - Update `isGlobalPlenary(event)` so it no longer relies on the display name being `ALL`; use the normalized value stream conditions as the authoritative check and retain any name checks only if still needed for legacy data.
  - Update `sortEventsByStart(events)` to use `event.name` as the final tie-breaker instead of `event.team`.
  - Update `getTeamValueStream(events, teamName)` to find the first event where `event.teams.includes(teamName)`.
  - Update `buildHierarchy(events)` to iterate each `event.teams` entry and add each team into the correct value-stream set.
  - Update `matchesSearch(event, searchText)` to search across `event.name`, `event.teams.join(" ")`, `event.vs`, `event.location`, and `event.topics`.
  - Update `filterEvents(events, filterState)` so team filtering returns:
    - Global plenaries.
    - The matching value-stream plenary when a team belongs to a value stream.
    - Any event whose `teams[]` contains the selected team.
    - Any event with `teams.length === 0`.
  - Keep the current `all`, `plenary`, and `vs` modes intact apart from the field renames.
- **Rationale**: The filter behavior is the main user-visible contract. This step makes team selection behave per the new requirement: a team filter must show events tagged with that team or with no team, while still grouping team options under value streams.
- **Tests**:
  - Add focused assertions for `buildHierarchy()` showing that a CSV plenary row with multiple teams contributes every team under the right value stream.
  - Add focused assertions for `filterEvents()` showing that selecting one team includes:
    - That team’s own cards.
    - Its value-stream plenary.
    - Global plenaries.
    - Teamless cards.
  - Add at least one negative assertion proving unrelated teams are excluded.
- **Commit message**: `refactor(filter): drive hierarchy and team scope from teams arrays`

### Step 3: Update card rendering to display `name` instead of filter teams
- **File**: `js/renderer.js` (modify)
- **File**: `app.js` (modify only if required for a broken assumption during implementation)
- **Changes**:
  - In `createRoomCard(event, colorMap)`, keep the current DOM-safe rendering approach and card structure, but change the main heading from `event.team` to `event.name`.
  - Preserve the existing VS, location, topics, and type rows.
  - Do not add the hidden filtering teams to the card UI unless implementation reveals a gap that blocks testing; the requirement says the team field should not be displayed.
  - Verify `buildScopeSelect()` in `app.js` still works unchanged with the `hierarchy.valueStreams` shape. Only touch `app.js` if a `team`-specific assumption breaks during implementation.
- **Rationale**: The user-facing change is that the card title now represents the meeting name, while team metadata remains a filtering concern only.
- **Tests**:
  - Add a renderer or integration-level assertion that the display heading reflects `name` for a CSV-backed event and does not depend on the old `team` field.
  - Manual smoke check in the browser against the loaded schedule: team-filtered views should still show cards titled with the meeting `name`.
- **Commit message**: `refactor(renderer): show meeting name on schedule cards`

### Step 4: Update requirements and regression tests for the new data contract
- **File**: `tests/sage-spec-requirements.mjs` (modify)
- **File**: `tests/date-named-sources-spec.mjs` (modify)
- **File**: `tests/sage-review-followups-spec.mjs` (modify only where fixture shape assumptions require it)
- **File**: `tests/requirements.spec.mjs` (modify)
- **Changes**:
  - Replace temporary CSV fixtures that still use the old header `date,start,end,team,vs,topics,location,type` with fixtures that exercise the new contract:
    - `time,location,topics,name,value stream,teams,type` where the test is specifically about committed CSV behavior.
    - Keep legacy JSON fixture objects using `team` where the test is intentionally proving backward compatibility.
  - Add direct assertions on normalized events where useful:
    - `event.name` exists and is used.
    - `event.teams` is an array.
    - Legacy JSON records still produce usable events.
  - Update any regression fixture objects that currently hardcode `{ team: "Regression Team" }` when the scenario is meant to emulate the new CSV contract; leave legacy JSON-style fixtures alone only where the test specifically depends on backward compatibility.
  - Keep the existing source-loading behavior tests intact: CSV precedence, ignored extra files, and missing-source messages must continue passing after the refactor.
- **Rationale**: The current tests still encode the old single-string `team` contract. Without updating them, they will either fail for the wrong reason or miss the new behavior entirely.
- **Tests**:
  - Re-run all four Node-based suites after the changes.
  - Ensure there is explicit coverage for both data shapes:
    - New CSV shape: `name` + `teams` + `value stream`.
    - Legacy JSON shape: `team` + `vs`.
- **Commit message**: `test(schedule): cover name and teams decoupling contract`

### Step 5: Document the transitional data contract
- **File**: `README.md` (modify)
- **Changes**:
  - Extend the data layout section to describe the current transitional contract:
    - CSV files may define `name`, `value stream`, and `teams`.
    - Existing JSON files still load with legacy `team` + `vs` and are normalized for compatibility.
    - The UI displays meeting `name`; team membership is used only for filtering.
  - Keep the existing explanation that sources are controlled by [config/sources.json](c:/Users/manfredig/IdeaProjects/sage/config/sources.json) and loaded from date-named files.
- **Rationale**: This change alters the meaning of the main display field. The next person editing data needs to know why CSV and JSON temporarily differ and which fields drive UI vs filtering.
- **Tests**:
  - No automated test required.
  - Confirm the documentation does not contradict the implemented runtime behavior.
- **Commit message**: `docs(readme): describe meeting name and team filter fields`

## Testing Approach
Run the existing Node-based regression suites against a local static server.

1. Start a local server from the repo root:
   - Preferred if available: `python -m http.server 8000`
   - If Python is unavailable in this environment, use the same fallback pattern used in earlier work: any simple local static server that serves the workspace root at `http://127.0.0.1:8000/`
2. Run the suites individually from the repo root:
   - `node tests/sage-spec-requirements.mjs`
   - `node tests/date-named-sources-spec.mjs`
   - `node tests/sage-review-followups-spec.mjs`
   - `node tests/requirements.spec.mjs`
3. Manual verification in the browser:
   - Load the schedule for 2026-03-17 from the committed CSV.
   - Confirm cards show meeting names, not teams.
   - Confirm the team dropdown is still grouped under value streams.
   - Confirm selecting a team shows cards that include that team plus cards with no assigned teams.

## Handoff

**Artifact saved**: `artifacts/2026-03-23-name-teams-decoupling-plan.md`

**Upstream artifacts**:
- Architecture: `artifacts/2026-03-23-name-teams-decoupling-architecture.md`
- Requirements: none (user request in conversation)

**Context for @ema-implementer**:
- 5 steps to execute.
- Files to create: none.
- Files to modify: `js/loader.js`, `js/filter.js`, `js/renderer.js`, `tests/sage-spec-requirements.mjs`, `tests/date-named-sources-spec.mjs`, `tests/requirements.spec.mjs`, `README.md`.
- Files to modify only if implementation reveals a real dependency: `app.js`, `tests/sage-review-followups-spec.mjs`.
- Files to leave unchanged in this change: `data/json/2026-03-17.json`, `data/json/2026-03-18.json`, `config/sources.json`, `index.html`, `styles.css`, `js/url-state.js`, `js/time-indicator.js`.
- Test command:
  - Start local server on port 8000 serving repo root.
  - Then run:
    - `node tests/sage-spec-requirements.mjs`
    - `node tests/date-named-sources-spec.mjs`
    - `node tests/sage-review-followups-spec.mjs`
    - `node tests/requirements.spec.mjs`
- Test framework: custom Node assertion scripts using `node:assert/strict` plus fetch-based loading against a local static server.
- Watch for:
  - The committed CSV header is `teams` plural and `value stream` with a space.
  - Teamless events are valid and must remain visible in team-filtered views.
  - JSON compatibility is required now; JSON schema migration is explicitly out of scope for this change.
  - `isGlobalPlenary()` must still classify legacy JSON rows and the new CSV rows correctly after the field split.
  - Do not accidentally expose filtering teams in the card UI.

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-implementer`

**What @ema-implementer should do**:
1. Read this plan artifact at the path above.
2. Read [artifacts/2026-03-23-name-teams-decoupling-architecture.md](c:/Users/manfredig/IdeaProjects/sage/artifacts/2026-03-23-name-teams-decoupling-architecture.md) for the design intent only.
3. Execute the 5 steps atomically, staging changes but not committing.
4. Run the full test sequence after each logical step that changes behavior, then again at the end.
5. Document any deviations and save the implementation summary to `artifacts/2026-03-23-name-teams-decoupling-implementation.md`.
