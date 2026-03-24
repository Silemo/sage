## Summary
Simplify SAGE legend and color assignment so the renderer colors events strictly by `event.vs`, shows one legend entry per active value stream, removes the `_plenary` renderer/config concept, and keeps `_default` as the anomaly-detection fallback for events with missing or unmapped value streams.

Codebase verification completed before planning:
- Existing files confirmed: `artifacts/2026-03-24-legend-color-simplification-architecture.md`, `artifacts/2026-03-24-all-legend-duplication-test-report.md`, `js/renderer.js`, `config/colors.json`, `tests/name-teams-decoupling-spec.mjs`, `tests/requirements.spec.mjs`
- Verified current integration points match the architecture:
  - `js/renderer.js` imports `isGlobalPlenary`, special-cases `getEventColor()`, and remaps legend items to `_plenary`
  - `config/colors.json` contains both `ALL` and `_plenary`
  - `tests/name-teams-decoupling-spec.mjs` still includes `_plenary` in a renderer fixture
- Confirmed unchanged scope:
  - `js/filter.js` keeps `isGlobalPlenary()` for filtering/hierarchy behavior
  - `app.js` does not require interface changes for this refactor
  - No data-file changes are required

## Steps

### Step 1: Simplify renderer color selection and legend bucketing
- **File**: `js/renderer.js` (modify)
- **Changes**:
  - Remove `import { isGlobalPlenary } from "./filter.js"`.
  - Replace `getEventColor(event, colorMap)` with a single return path:
    - `return colorMap[event.vs] ?? colorMap._default;`
  - Update `renderLegend(container, colorMap, events)` so `activeStreams` is built from `event.vs` directly:
    - replace `.map((event) => (isGlobalPlenary(event) ? "_plenary" : event.vs))`
    - with `.map((event) => event.vs)`
  - Remove the `_plenary` display relabeling and render legend labels as the literal value stream name.
  - Preserve the existing `filter(Boolean)` and sort behavior.
- **Rationale**: This is the root fix. The duplicate `ALL` labels come from renderer-only remapping, not from the event data model.
- **Tests**:
  - Add renderer assertions proving:
    - `getEventColor({ vs: "ALL" }, colorMap)` returns `colorMap.ALL`
    - `getEventColor({ vs: "" }, colorMap)` returns `colorMap._default`
    - legend output contains one `ALL` label when events include both a plenary with `vs: "ALL"` and a non-plenary with `vs: "ALL"`
- **Commit message**: `refactor(renderer): color and label by value stream only`

### Step 2: Remove the redundant `_plenary` palette entry
- **File**: `config/colors.json` (modify)
- **Changes**:
  - Delete the `_plenary` color block.
  - Keep `ALL` unchanged as the cross-cutting value-stream color.
  - Keep `_default` unchanged as the explicit fallback for missing or unmapped value streams.
- **Rationale**: After Step 1, `_plenary` is dead configuration. Keeping it would hide whether the code path is truly removed.
- **Tests**:
  - Verify all referenced color keys used by the renderer remain available: `ALL`, known value streams, `_default`.
  - Confirm no runtime code still looks up `_plenary`.
- **Commit message**: `refactor(config): remove plenary-only color alias`

### Step 3: Update focused regression coverage for the new renderer contract
- **File**: `tests/name-teams-decoupling-spec.mjs` (modify)
- **File**: `tests/requirements.spec.mjs` (modify)
- **Changes**:
  - In `tests/name-teams-decoupling-spec.mjs`, remove `_plenary` from the renderer fixture color map.
  - Add a focused legend regression test in either `tests/name-teams-decoupling-spec.mjs` or `tests/requirements.spec.mjs` that installs the minimal DOM, calls `renderLegend`, and asserts:
    - duplicate `ALL` labels are not produced for events sharing `vs: "ALL"`
    - `_default` is used only for empty/missing `vs`
  - Keep existing filter assertions intact. Do not rewrite `isGlobalPlenary()` tests; they still describe valid filter behavior.
- **Rationale**: The implementation is small enough that one targeted regression test should lock the behavior without broad test churn.
- **Tests**:
  - This IS the test for the duplicate-legend bug.
  - Re-run core regression suites after the test update.
- **Commit message**: `test(renderer): cover legend deduplication by value stream`

## Testing Approach
Serve the repo root on port 8000, then run the existing Node-based suites against that base URL.

1. Start a local static server from the repo root:
   - Preferred if available: `python -m http.server 8000`
   - If Python is unavailable, use an equivalent static server bound to `http://127.0.0.1:8000/`
2. Run focused and regression suites from the repo root:
   - `node tests/name-teams-decoupling-spec.mjs`
   - `node tests/requirements.spec.mjs`
   - `node tests/date-named-sources-spec.mjs`
   - `node tests/sage-review-followups-spec.mjs`
   - `node tests/sage-spec-requirements.mjs`
3. Manual smoke check in the browser:
   - Open the schedule for the CSV-backed day.
   - Confirm the legend shows exactly one `ALL` entry.
   - Confirm `ALL` events still share the configured `ALL` color.
   - Confirm `_default` styling appears only for malformed/unmapped value streams, not normal CSV-backed events.

## Handoff

**Artifact saved**: `artifacts/2026-03-24-legend-color-simplification-plan.md`

**Upstream artifacts**:
- Architecture: `artifacts/2026-03-24-legend-color-simplification-architecture.md`
- Test report: `artifacts/2026-03-24-all-legend-duplication-test-report.md`
- Requirements: none

**Context for @ema-implementer**:
- 3 steps to execute.
- Files to create: none.
- Files to modify: `js/renderer.js`, `config/colors.json`, `tests/name-teams-decoupling-spec.mjs`, `tests/requirements.spec.mjs`.
- Files expected to remain unchanged: `js/filter.js`, `app.js`, `config/sources.json`, all data files.
- Test command:
  - Start local server on port 8000 serving repo root.
  - Then run:
    - `node tests/name-teams-decoupling-spec.mjs`
    - `node tests/requirements.spec.mjs`
    - `node tests/date-named-sources-spec.mjs`
    - `node tests/sage-review-followups-spec.mjs`
    - `node tests/sage-spec-requirements.mjs`
- Watch for:
  - Do not reintroduce color behavior based on event type; color is value-stream-only.
  - Keep `_default` intact and reachable for missing/unmapped `vs` values.
  - Do not remove or weaken `isGlobalPlenary()` in `js/filter.js`; it still governs filter semantics.
  - Avoid scope creep into legacy JSON cleanup or data normalization changes.
  - Preserve the current DOM-safe renderer style and existing legend sort order.

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-implementer`

**What @ema-implementer should do**:
1. Read this plan artifact at the path above.
2. Read `artifacts/2026-03-24-legend-color-simplification-architecture.md` for design intent and non-goals.
3. Implement the 3 steps atomically, staging changes but not committing.
4. Run the focused suites after the renderer/test changes, then run the full regression sequence.
5. Save the implementation summary to `artifacts/2026-03-24-legend-color-simplification-implementation.md`.
