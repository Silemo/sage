# Architecture: Legend & Color Simplification

## Summary

Simplify legend and color assignment so that each event is colored purely by its `vs` (value stream) field, with one legend entry per active value stream. Remove the `_plenary` concept from the renderer and color config. Keep `_default` as a safety net for events missing a value stream — making misconfigured data visually obvious. The `isGlobalPlenary` function remains in `filter.js` for filtering logic only.

## Codebase Context

### Current behavior (the problem)

- `getEventColor()` in `js/renderer.js` (lines 7-13) checks `isGlobalPlenary(event)` and returns `colorMap.ALL` for those events, otherwise `colorMap[event.vs]`. Since all global plenaries already have `vs: "ALL"` in the CSV data, this branch is redundant — `colorMap[event.vs]` would return `colorMap.ALL` anyway.
- `renderLegend()` in `js/renderer.js` (lines 81-103) maps global plenaries to an internal `_plenary` bucket, then relabels `_plenary` as "ALL" in the display. Non-plenary events with `vs: "ALL"` (Coffee break, Lunch) keep their literal `event.vs` value of "ALL". This produces **two legend entries both labeled "ALL"** — one from `_plenary` and one from the literal `vs`.
- `config/colors.json` has both `ALL` and `_plenary` entries with identical colors, plus `_default` with a distinct (white/grey) color.

### Key insight from CSV data

In the authoritative CSV data (`data/csv/2026-03-17.csv`), every cross-cutting event already has `value stream: ALL`:
- "Overall PI Plenary" → `vs: "ALL"`, `type: "Plenary"`
- "Coffee break" → `vs: "ALL"`, `type: "Coffee"`
- "Lunch" → `vs: "ALL"`, `type: "Lunch"`

The `_plenary` special-casing in the renderer is therefore unnecessary — `event.vs` already carries the correct value stream for all events.

### What stays unchanged

- **`isGlobalPlenary()` in `js/filter.js`** — still needed for filter logic: plenary mode returns only global plenaries, vs mode includes global plenaries alongside vs-specific events, team mode includes global plenaries. This is a **filtering concern**, not a color/legend concern.
- **`isVsPlenary()` in `js/filter.js`** — still needed for team filter mode.
- **`buildHierarchy()` in `js/filter.js`** — still uses `isGlobalPlenary()` to exclude global plenaries from the value-stream → team hierarchy (plenaries belong to no particular team). Correct behavior, unchanged.
- **`app.js`** — calls `renderLegend()` with the same signature; no change needed.
- **Event type display** — the `type` field ("Plenary", "Coffee", "Lunch", "Breakout room") is already displayed as a tag on each card via the `card-type` span. This is independent and correct.

## Design Approaches Considered

### Approach A: Remove `_plenary` from renderer only ⭐ (recommended)

- **Description**: Remove the `isGlobalPlenary` import and special-casing from `renderer.js`. Simplify `getEventColor` to `colorMap[event.vs] ?? colorMap._default`. Simplify `renderLegend` to use `event.vs` directly with no remapping. Remove `_plenary` from `colors.json`. Keep `_default` as fallback for misconfigured/missing value streams.
- **Pros**: Minimal change surface (2 source files + 1 config + 1 test fixture). Zero functional change to filtering. Directly addresses the duplicate legend bug. Color logic becomes trivially understandable: value stream → color.
- **Cons**: None significant. This is the simplest viable approach.

### Approach B: Remove `isGlobalPlenary` entirely from the codebase

- **Description**: Replace `isGlobalPlenary()` checks in `filter.js` with `event.vs === "ALL"` conditions. Remove the function entirely.
- **Pros**: Eliminates a concept completely.
- **Cons**: **Breaks filtering correctness.** The current `isGlobalPlenary` checks `type === "Plenary"` AND name/vs conditions — it distinguishes "Overall PI Plenary" (global) from "VS PLM Plenary" (vs-specific). Replacing with `event.vs === "ALL"` would incorrectly include non-plenary ALL events (Coffee, Lunch) in plenary filter mode, and would miss the `type === "Plenary"` guard that `isVsPlenary` depends on. The function encodes domain logic that cannot be replaced by a simple field check.
- **Verdict**: Rejected — changes filtering behavior, not just color/legend.

### Approach C: Normalize data at load time

- **Description**: In `js/loader.js`, set `vs: "ALL"` on any event where `isGlobalPlenary` would return true, then remove `isGlobalPlenary` from filter logic too.
- **Pros**: Single source of truth established at load time.
- **Cons**: Still doesn't fix the filtering issue — plenary mode needs to know an event is a plenary by type, not just that its value stream is ALL. Coffee breaks have `vs: "ALL"` but are not plenaries. Over-engineering for the stated goal.
- **Verdict**: Rejected — solves a problem that doesn't exist (vs is already correct) and breaks plenary filter mode.

## Chosen Design

**Approach A** — Remove `_plenary` from renderer only.

The user's direction is clear: one legend entry per value stream, color assigned by value stream (including ALL), `_default` for uncategorized data as a visual anomaly indicator. Event types (Plenary, Coffee, Lunch) are independent tags already displayed correctly. The `isGlobalPlenary` function remains in `filter.js` for its legitimate filtering purpose.

### Components

| Component | Change | Details |
|-----------|--------|---------|
| `js/renderer.js` | **Modify** | Remove `isGlobalPlenary` import. Simplify `getEventColor` to one-liner. Simplify `renderLegend` to use `event.vs` directly. |
| `config/colors.json` | **Modify** | Remove `_plenary` entry. Keep `ALL` and `_default`. |
| `tests/name-teams-decoupling-spec.mjs` | **Modify** | Remove `_plenary` from test color map fixture (line ~147). |
| `js/filter.js` | No change | `isGlobalPlenary` stays for filtering. |
| `app.js` | No change | Calls `renderLegend` with same signature. |
| `tests/requirements.spec.mjs` | No change | Asserts on `isGlobalPlenary` (still valid) and uses `_default` in fixture (still valid). |

### Data Flow

```
Event loaded from CSV
  → event.vs = "ALL" | "PLM" | "R&D" | ... | "" (if missing)
  → getEventColor(event, colorMap)
      → colorMap[event.vs] ?? colorMap._default
      → returns { bg, border }
  → renderLegend(container, colorMap, events)
      → unique set of event.vs values (filtered for truthy)
      → one legend swatch per value stream
      → label = value stream name (e.g. "ALL", "PLM", "R&D")
      → color = colorMap[vs] ?? colorMap._default
```

### Interfaces and Contracts

**`getEventColor(event, colorMap)`** — simplified:
```javascript
export function getEventColor(event, colorMap) {
  return colorMap[event.vs] ?? colorMap._default;
}
```

**`renderLegend(container, colorMap, events)`** — simplified bucket logic:
```javascript
const activeStreams = [...new Set(events
  .map((event) => event.vs)
  .filter(Boolean))];
```

No `_plenary` remapping. No special-case label. Each value stream is its own legend entry.

### Integration Points

| File | Line(s) | What to change |
|------|---------|----------------|
| `js/renderer.js` | 1 | Remove `import { isGlobalPlenary } from "./filter.js"` |
| `js/renderer.js` | 7-13 | Replace `getEventColor` body — remove `isGlobalPlenary` branch |
| `js/renderer.js` | 84-85 | Replace `.map((event) => (isGlobalPlenary(event) ? "_plenary" : event.vs))` with `.map((event) => event.vs)` |
| `js/renderer.js` | 98 | Remove `valueStream === "_plenary" ? "ALL" :` from label logic |
| `config/colors.json` | 28-31 | Remove `"_plenary": { "bg": "#ECEFF1", "border": "#455A64" }` entry |
| `tests/name-teams-decoupling-spec.mjs` | ~147 | Remove `_plenary: { bg: "#fff", border: "#000" }` from test fixture |

## Error Handling

- **Missing value stream** (`event.vs` is `""` or `undefined`): `colorMap[event.vs]` returns `undefined`, falls through to `colorMap._default`. The `_default` white/grey color makes such events visually distinct — intentional design for spotting misconfigured data.
- **Empty legend**: If `filter(Boolean)` removes all falsy `vs` values and no truthy ones remain, `renderLegend` exits early (existing behavior, unchanged).

## Testing Strategy

- **Unit**: Verify `getEventColor` returns `colorMap._default` for events with empty/missing `vs`, and `colorMap.ALL` for events with `vs: "ALL"` regardless of type.
- **Unit**: Verify `renderLegend` produces exactly one legend entry per unique active value stream, with no duplicates.
- **Integration**: Load committed CSV data, render with the real `colors.json`, confirm no duplicate legend labels.
- **Regression**: Run all existing test suites — filtering behavior must remain identical.
- **Visual**: `_default` color (white/grey) should only appear if data is misconfigured — never in correctly-configured CSV data.

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Legacy JSON data has events with empty `vs` that relied on `_plenary` coloring | Low (user confirmed JSON is legacy/low-quality and CSV is authoritative) | `_default` color will make these visually obvious; no data loss |
| Test fixtures reference `_plenary` in color maps | Certain (1 test file) | Update fixture to remove `_plenary`, keep `ALL` |
| Future data sources omit `vs` field | Low | `_default` fallback handles this safely and visibly |

## Handoff

**Artifact saved**: `artifacts/2026-03-24-legend-color-simplification-architecture.md`

**Path signal**: unexpectedly simple (localized change, no new abstractions) → consider @ema-planner-lite instead

> 📋 **Model**: Select **Gemini 3 Flash** before invoking `@ema-planner-lite`

**Upstream artifacts**:
- Test report: `artifacts/2026-03-24-all-legend-duplication-test-report.md`

**Context for @ema-planner**:
- Chosen approach: Remove `_plenary` from renderer and color config only — keep `isGlobalPlenary` in filter.js for filtering
- Files to create: none
- Files to modify: `js/renderer.js` (remove isGlobalPlenary import, simplify getEventColor and renderLegend), `config/colors.json` (remove _plenary entry), `tests/name-teams-decoupling-spec.mjs` (remove _plenary from test fixture)
- Key integration points: `renderer.js` lines 1, 7-13, 81-103; `colors.json` lines 28-31; test fixture at line ~147
- Testing strategy: unit tests for getEventColor and renderLegend deduplication, integration test with real CSV data, full regression suite
- Conventions to follow: ES module imports, `??` for nullish coalescing, existing code style

**Files the planner must verify exist before writing the plan**:
- `js/renderer.js` — contains getEventColor and renderLegend to simplify
- `config/colors.json` — contains _plenary entry to remove
- `tests/name-teams-decoupling-spec.mjs` — contains _plenary in test fixture to update

**What @ema-planner should do**:
1. Read this architecture artifact at the path above
2. Verify the listed files exist and match the descriptions
3. Produce a step-by-step plan with exact file paths, function signatures, and commit messages
4. Save plan to `artifacts/2026-03-24-legend-color-simplification-plan.md`
