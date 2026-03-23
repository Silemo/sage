# Architecture: Decouple Name / Teams from Team Field

## Summary

Refactor SAGE to split the current single `team` field into two distinct concepts: `name` (display label shown on cards) and `teams` (array of team names used for filtering). The CSV file `data/csv/2026-03-17.csv` already uses this new structure with separate `name`, `value stream`, and `teams` columns. The filter dropdown continues to group teams under value streams and supports selecting a team to show all events that contain that team or have no team assigned.

## Codebase Context

Key findings from codebase exploration:

- **Data model** — The current normalized record shape is `{ date, start, end, team, vs, topics, location, type, source, id }`. The `team` field serves a dual purpose: it is both the display name on cards and the filter key.
- **CSV parser** (`js/loader.js`) — `parseCsv()` lowercases headers and produces raw records keyed by header name. The new CSV has headers `time,location,topics,name,value stream,teams,type`.
- **Normalizer** (`js/loader.js`) — `normalizeRecord()` reads `rawRecord.team` and `rawRecord.vs`. It must be extended to also read `rawRecord.name`, `rawRecord["value stream"]`, and `rawRecord.teams`.
- **Filter** (`js/filter.js`) — `buildHierarchy()` builds a `{ vs → Set<team> }` map. `filterEvents()` matches `event.team === filterState.value` for team mode. `isSelectableTeam()` and `isGlobalPlenary()` check `event.team`.
- **Renderer** (`js/renderer.js`) — `createRoomCard()` renders `event.team` as the card `h2` heading.
- **App** (`app.js`) — `buildScopeSelect()` iterates `hierarchy.valueStreams` (an object of `{ vs: teamNames[] }`) to build optgroups with team options. No structural change needed here since the hierarchy shape stays the same.
- **Existing JSON** (`data/json/*.json`) — Uses `{ team, vs }` with `team` as a single string. These must continue to work (backward compatibility) until they are migrated.
- **Tests** — Multiple test files reference `event.team` and the current record shape. They will need updates.

## Design Approaches Considered

### Approach A: Array-based `teams` field with `name` ⭐ (recommended)

- **Description**: Add `name` to the normalized record. Change `team` (single string) to `teams` (array of strings). CSV comma-separated team values are split into arrays during normalization. For backward-compatible JSON files that lack `name` and have `team` as a single string, fall back `name` to `team` value and wrap `team` into a one-element array for `teams`.
- **Pros**: Clean data model; filtering with `.includes()` on arrays is natural; `name` and `teams` have clear, distinct purposes; backward compatible with existing JSON.
- **Cons**: More files to change (loader, filter, renderer, tests); all downstream code referencing `event.team` must change.

### Approach B: Keep `team` as comma-separated string, add `name`

- **Description**: Add `name` to the record but keep `team` as a comma-separated string. Split on commas during filtering and hierarchy building.
- **Pros**: Minimal change to data model; JSON backward compatibility trivial.
- **Cons**: String-splitting logic repeated in filter.js, renderer.js, and app.js; easy to forget the split in one place causing subtle bugs; inconsistent mental model.

### Approach C: Separate teams mapping in config

- **Description**: Maintain a separate mapping structure in config that maps event names to teams.
- **Pros**: Zero change to existing event records.
- **Cons**: Overkill; adds indirection; breaks "single source of truth" from CSV; harder to maintain.

## Chosen Design

**Approach A** — Array-based `teams` field with `name`. The cleanest model that aligns with how the CSV already structures the data. Downstream changes are mechanical and well-scoped.

### Normalized Record Shape

**Before:**
```js
{ date, start, end, team, vs, topics, location, type, source, id }
```

**After:**
```js
{ date, start, end, name, teams, vs, topics, location, type, source, id }
```

Where:
- `name` — string, the display name shown on cards (from `rawRecord.name`, falling back to `rawRecord.team`)
- `teams` — array of strings, the teams associated with the event for filtering purposes

### Components

| Component | File | Change |
|-----------|------|--------|
| Loader | `js/loader.js` | Add `name` field, parse `teams` into array, handle `value stream` header, update `REQUIRED_FIELDS`, `createEventId`, `normalizeRecord`, `TEAM_ALIASES` |
| Filter | `js/filter.js` | Adapt `isGlobalPlenary`, `isSelectableTeam`, `buildHierarchy`, `getTeamValueStream`, `filterEvents`, `sortEventsByStart`, `matchesSearch` to use `name` + `teams[]` |
| Renderer | `js/renderer.js` | Card `h2` displays `event.name`; `isGlobalPlenary` already imported |
| App | `app.js` | No structural change — `buildScopeSelect` already receives `hierarchy.valueStreams` |
| URL State | `js/url-state.js` | No change |
| Time Indicator | `js/time-indicator.js` | No change |

### Data Flow

```
CSV row:  time | location | topics | name | value stream | teams (comma-sep) | type
   ↓ parseCsv()  (lowercases headers → { time, location, topics, name, "value stream", teams, type })
   ↓ normalizeRecord()
Normalized: { date, start, end, name, teams: [...], vs, topics, location, type, source, id }
   ↓ buildHierarchy()
Hierarchy:  { valueStreams: { "PLM": ["Avengers", "Marvels", ...], ... }, dates, types }
   ↓ filterEvents()
Filtered events → renderCards() → card h2 = event.name
```

### CSV Column Mapping in `normalizeRecord()`

| CSV Header (lowercased by parseCsv) | Raw Record Key | Normalized Field | Notes |
|--------------------------------------|----------------|------------------|-------|
| `time` | `rawRecord.time` | `start`, `end` | Split on `-` as before |
| `location` | `rawRecord.location` | `location` | |
| `topics` | `rawRecord.topics` | `topics` | |
| `name` | `rawRecord.name` | `name` | **New** — displayed on card. Falls back to `rawRecord.team` for JSON compat |
| `value stream` | `rawRecord["value stream"]` | `vs` | Must check both `rawRecord.vs` and `rawRecord["value stream"]` |
| `teams` | `rawRecord.teams` | `teams` (array) | Split on `,`, trim each. Also check `rawRecord.team` for JSON compat. Empty → `[]` |
| `type` | `rawRecord.type` | `type` | |

### JSON Backward Compatibility

Existing JSON files (`2026-03-17.json`, `2026-03-18.json`) use `{ team, vs }` with `team` as a single string and no `name` field. The normalizer handles this:

```js
// name: prefer explicit name, fall back to team
name = rawRecord.name ?? rawRecord.team

// teams: prefer explicit teams field, fall back to team field
// parseTeams() splits on comma and trims; single value → ["value"], empty → []
teams = parseTeams(rawRecord.teams ?? rawRecord.team)

// vs: prefer explicit vs, fall back to "value stream" (from CSV headers)
vs = rawRecord.vs ?? rawRecord["value stream"]
```

### Interfaces and Contracts

**`normalizeRecord(rawRecord, sourceName, defaultDate)` — updated return shape:**
```js
{
  record: {
    date: string,
    start: string,      // "HH:MM"
    end: string,        // "HH:MM"
    name: string,       // display label (from name or team fallback)
    teams: string[],    // ["Marvels", "Avengers"] or [] for global events
    vs: string,         // "PLM", "R&D", "MON", etc. or ""
    topics: string,
    location: string,
    type: string,       // "Plenary", "Breakout", etc.
    source: string,
    id: string,
  },
  errors: string[],
}
```

**`buildHierarchy(events)` — unchanged return shape:**
```js
{
  valueStreams: { [vs: string]: string[] },  // vs → sorted team names
  dates: string[],
  types: string[],
}
```

The hierarchy iterates `event.teams` (array) instead of `event.team` (string) to populate the value stream map.

**`filterEvents(events, filterState)` — filter logic updates:**

| Mode | Current Logic | New Logic |
|------|--------------|-----------|
| `all` | Show all | Show all (unchanged) |
| `plenary` | `isGlobalPlenary(event)` | Unchanged — uses `event.name` and `event.vs` checks |
| `vs` | Global plenary OR `event.vs === value` | Unchanged |
| `team` | Global plenary OR VS plenary OR `event.team === value` | Global plenary OR VS plenary OR `event.teams.includes(value)` OR `event.teams.length === 0` |

The key behavioral change for team filtering: events with **no team assigned** (`teams.length === 0`) are always shown when filtering by team, per the requirement "If no team assigned by default this will be shown under the filter."

**`isGlobalPlenary(event)` — updated checks:**
```js
// Before: event.team === "ALL" || event.team === "Every One"
// After:  event.name === "ALL" || event.name === "Every One"
//         OR event.vs === "" || event.vs === "Portfolio"
```

Note: With the new CSV, global plenaries have `name` like "Overall PI Plenary" and `value stream` = "ALL". The `normalizeVsName("ALL")` maps to "Portfolio". So the `event.vs === "Portfolio"` check still catches these. We also need to handle the case where the name check was previously catching "ALL" teams — now the name is descriptive, not "ALL". The `vs`-based check is sufficient.

**`isSelectableTeam(event)` → becomes `hasSelectableTeams(event)`:**
```js
// Returns true if the event has at least one real team that should appear in the filter
function hasSelectableTeams(event) {
  return event.teams.length > 0;
}
```

**`getTeamValueStream(events, teamName)` — updated:**
```js
// Finds the VS for a team by scanning events that contain that team
function getTeamValueStream(events, teamName) {
  const match = events.find((event) => event.teams.includes(teamName) && hasSelectableTeams(event));
  return match?.vs ?? "";
}
```

**`createRoomCard(event, colorMap)` — renderer:**
```js
// h2 displays event.name instead of event.team
const heading = document.createElement("h2");
heading.className = "card-team";  // CSS class name can stay — it's just a heading
heading.textContent = event.name;
```

**`createEventId(record)` — updated seed:**
```js
// Use name instead of team for uniqueness
const seed = [record.date, record.start, record.end, record.name, record.location, record.topics].join("|");
```

**`REQUIRED_FIELDS` — updated:**
```js
const REQUIRED_FIELDS = ["date", "start", "end", "name", "topics", "location", "type"];
```
`teams` is intentionally NOT required — global plenaries, coffee breaks, and lunch events have no team.

**`validateRecord` — no new validations needed** beyond the existing field-presence and format checks. `teams` is an array and always present (possibly empty).

### Integration Points

| Existing File | Hook Point | What Changes |
|---------------|-----------|--------------|
| `js/loader.js` L1 | `REQUIRED_FIELDS` | Replace `"team"` with `"name"` |
| `js/loader.js` L10-12 | `TEAM_ALIASES` | Apply aliases per team in the teams array |
| `js/loader.js` L113-115 | `createEventId` | Use `record.name` in seed |
| `js/loader.js` L148-167 | `normalizeRecord` | Add `name`, `teams` parsing, read `value stream` header |
| `js/filter.js` L4-9 | `isGlobalPlenary` | Check `event.name` instead of `event.team` for "ALL"/"Every One" |
| `js/filter.js` L15-17 | `isSelectableTeam` | Rename and check `event.teams.length > 0` |
| `js/filter.js` L19-31 | `sortEventsByStart` | Sort fallback on `event.name` instead of `event.team` |
| `js/filter.js` L33-36 | `getTeamValueStream` | Check `event.teams.includes(teamName)` |
| `js/filter.js` L38-62 | `buildHierarchy` | Iterate `event.teams` array |
| `js/filter.js` L64-72 | `matchesSearch` | Search `event.name` and `event.teams.join(" ")` |
| `js/filter.js` L74-101 | `filterEvents` | Team mode: `event.teams.includes(value)` and show teamless events |
| `js/renderer.js` L42-43 | `createRoomCard` | Display `event.name` |

## Error Handling

- **Empty `teams` field**: Normalized to `[]`. Not a validation error — global events, coffee breaks, and lunches have no team.
- **Missing `name` field (JSON backward compat)**: Falls back to `rawRecord.team`. If both are missing, validation catches `Missing name`.
- **Malformed CSV team list**: Each comma-separated value is trimmed; empty strings after splitting are filtered out.
- **Unknown team in filter URL state**: `getTeamValueStream` returns `""`, filter gracefully shows global plenaries only. No crash.

## Testing Strategy

### Unit Tests (pure function tests in test spec files)

1. **`normalizeRecord` with new CSV shape** — verify `name` and `teams` array are correctly extracted from CSV-style raw records
2. **`normalizeRecord` JSON backward compat** — verify that records with only `team` (no `name`/`teams`) produce correct `name` and `teams`
3. **`buildHierarchy` with multi-team events** — verify a plenary with `teams: ["A", "B"]` adds both to the VS map
4. **`filterEvents` team mode** — verify selecting team "Marvels" shows events where `teams.includes("Marvels")` plus global plenaries plus VS plenaries plus teamless events
5. **`filterEvents` team mode shows teamless events** — verify events with `teams: []` appear in team-filtered view
6. **`isGlobalPlenary` with new data** — verify "Overall PI Plenary" with `vs: "Portfolio"` is correctly identified
7. **`createEventId` uses name** — verify ID stability with new seed

### Integration Tests

1. **Load CSV file** — verify `2026-03-17.csv` loads correctly with the new column mapping
2. **Load JSON file (backward compat)** — verify `2026-03-18.json` still loads correctly
3. **Full filter roundtrip** — load both sources, build hierarchy, verify team dropdown contains all teams from multi-team events

## Risks

| Risk | Mitigation |
|------|-----------|
| Existing tests hardcode `event.team` assertions | Tests must be updated systematically — search for all `.team` references |
| JSON files have different field names than CSV | Normalizer handles both with explicit fallback logic |
| `createEventId` seed change produces different IDs for existing JSON data | Acceptable — IDs are ephemeral (used for DOM dedup in a session, not persisted) |
| `TEAM_ALIASES` currently normalizes single team names, now needs to handle arrays | Apply alias to each element in the teams array |
| `value stream` header has a space — lowercased to `"value stream"` by parseCsv | Normalizer must check `rawRecord["value stream"]` in addition to `rawRecord.vs` |

## Handoff

**Artifact saved**: `artifacts/2026-03-23-name-teams-decoupling-architecture.md`

**Path signal**: full → @ema-planner

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-planner`

**Upstream artifacts**:
- None (requirements provided directly by user in conversation)

**Context for @ema-planner**:
- Chosen approach: Array-based `teams` field with `name` — decouples display name from filter teams, clean array model
- Files to create: none
- Files to modify: `js/loader.js` (normalizeRecord, createEventId, REQUIRED_FIELDS, TEAM_ALIASES), `js/filter.js` (isGlobalPlenary, isSelectableTeam→hasSelectableTeams, buildHierarchy, getTeamValueStream, filterEvents, matchesSearch, sortEventsByStart), `js/renderer.js` (createRoomCard h2 text)
- Test files to update: `tests/sage-spec-requirements.mjs`, `tests/date-named-sources-spec.mjs`, `tests/sage-review-followups-spec.mjs`, `tests/requirements.spec.mjs`
- Key integration points: `normalizeRecord()` at line ~148 in `js/loader.js`; `buildHierarchy()` at line ~38 in `js/filter.js`; `createRoomCard()` at line ~29 in `js/renderer.js`
- Testing strategy: unit tests for normalizer (CSV shape, JSON compat), filter (team mode with arrays, teamless events), integration tests for CSV+JSON loading
- Conventions to follow: ESM imports, `const` by default, early returns, existing naming patterns (camelCase functions, UPPER_CASE constants)

**Files the planner must verify exist before writing the plan**:
- `js/loader.js` — normalizeRecord, createEventId, REQUIRED_FIELDS, parseCsv
- `js/filter.js` — buildHierarchy, filterEvents, isGlobalPlenary, isSelectableTeam, getTeamValueStream
- `js/renderer.js` — createRoomCard
- `data/csv/2026-03-17.csv` — new CSV structure with name/teams columns
- `data/json/2026-03-17.json` — existing JSON structure for backward compat reference
- `data/json/2026-03-18.json` — existing JSON structure for backward compat reference

**What @ema-planner should do**:
1. Read this architecture artifact at the path above
2. Read all listed files to verify integration points match the descriptions
3. Produce a step-by-step plan with exact file paths, function signatures, and commit messages
4. The plan should be phased: Phase 1 = loader changes, Phase 2 = filter changes, Phase 3 = renderer changes, Phase 4 = test updates
5. Save plan to `artifacts/2026-03-23-name-teams-decoupling-plan.md`
