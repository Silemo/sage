# Architecture: Legend Click-to-Search

## Summary
Adding click-to-search behavior on legend value stream items. Clicking a legend item (e.g., "MON") sets the search filter to that value stream name and refreshes the view. No visual changes needed — items already look like clickable pills. Uses event delegation on the `#legend` container, matching the existing date tabs pattern.

## Codebase Context
- **Legend rendering** in `js/renderer.js` `renderLegend()`: Creates `div.legend-item` elements with a swatch and label per active value stream. Purely presentational — no interactivity.
- **Search filter** in `app.js`: The search `<input>` listener sets `appState.filterState.search` and calls `applyCurrentFilters()`.
- **Event delegation pattern** in `app.js`: Date tabs already use event delegation on a parent container — clicking a `button[data-date]` inside `#dateTabs` updates the filter. This is the established pattern.
- **URL state** in `js/url-state.js`: `writeState()` persists `search` to URL query string and localStorage. `readState()` restores it on load.
- **Legend CSS** in `styles.css`: `.legend-item` is styled as a pill (padding, border-radius, background). Adding `cursor: pointer` improves affordance.

## Design Approaches Considered

### Approach A: Event delegation in `app.js` with `data-vs` attribute ⭐ (recommended)
- **Description**: Add a `data-vs` attribute to each legend item in `renderLegend()`. Add a single click listener on the `#legend` container in `app.js` (same pattern as date tabs). On click, set `appState.filterState.search` to the value stream name, update the search input value, and call `applyCurrentFilters()`.
- **Pros**: Follows the exact same event delegation pattern already used for date tabs. Minimal change — 2 lines in renderer, ~10 lines in app.js, 1 CSS property. Keeps renderer purely presentational. Single event listener regardless of item count.
- **Cons**: None significant.

### Approach B: Callback parameter in `renderLegend()`
- **Description**: Pass an `onClickValueStream` callback to `renderLegend()` and attach individual click handlers to each legend item inside the renderer.
- **Pros**: Self-contained — legend click behavior is set up in one place.
- **Cons**: Changes renderer function signature. Couples renderer to app logic via callback. Inconsistent with date tabs pattern. One listener per item.

### Approach C: Custom DOM events
- **Description**: Legend items dispatch a custom `legend-select` event, and `app.js` listens for it.
- **Pros**: Maximum decoupling.
- **Cons**: Over-engineered. No precedent in codebase. Unnecessary abstraction.

## Chosen Design
**Approach A** — event delegation with `data-vs` attribute. Matches the existing date tabs pattern exactly, minimizing cognitive overhead and keeping changes minimal.

### Components
- **`js/renderer.js` — `renderLegend()`** (existing): Add `data-vs` attribute to each `div.legend-item`. No signature change.
- **`app.js` — `initializeApp()`** (existing): Add click event listener on `#legend` container following date tabs pattern.
- **`styles.css`** (existing): Add `cursor: pointer` to `.legend-item`.

### Data Flow
1. User clicks a legend item → event bubbles to `#legend` container
2. Click handler finds closest `.legend-item[data-vs]` → reads `dataset.vs`
3. Sets `appState.filterState.search` to the value stream name
4. Updates `searchInput.value` to reflect the new search term
5. Calls `applyCurrentFilters()` → `updateView()` → re-filters events, re-renders cards, re-renders legend, updates URL via `writeState()`

### Interfaces and Contracts
No new interfaces. Changes to existing:
- `renderLegend()` — adds `item.dataset.vs = valueStream` to each legend item (internal, no signature change)
- `initializeApp()` — adds ~8 lines for legend click listener

### Integration Points
- `app.js` ~line 203: New click listener goes after existing `dateTabs` click listener, before `searchInput` listener
- `js/renderer.js` ~line 88: Add `data-vs` attribute after creating `.legend-item` div
- `styles.css` line 156: Add `cursor: pointer` to `.legend-item`

## Error Handling
No new error paths. The click handler uses the same guard-clause pattern as date tabs — if the click doesn't land on a `[data-vs]` element, return early.

## Testing Strategy
- **Unit test**: Verify `renderLegend()` adds `data-vs` attribute to legend items
- **Integration test**: Verify clicking a legend item updates search filter and URL state
- **Edge cases**: Click on swatch (child element) — should resolve to parent `.legend-item[data-vs]`. Click on container gap — should do nothing.

## Risks
- **Legend re-renders on filter change**: After clicking, `updateView()` re-renders the legend. If the search narrows visible value streams, legend shrinks — this is correct and expected.
- **Search input sync**: Must update `searchInput.value` explicitly so the UI shows the current search term.

## Handoff

**Artifact saved**: `artifacts/2026-03-24-legend-click-search-architecture.md`

**Path signal**: unexpectedly simple (localized change, no new abstractions) → consider @ema-planner-lite instead

> 📋 **Model**: Select **Gemini 3 Flash** before invoking `@ema-planner-lite`

**Upstream artifacts**:
- None (user-described requirement)

**Context for @ema-planner**:
- Chosen approach: Event delegation with `data-vs` attribute — mirrors the existing date tabs click pattern
- Files to create: none
- Files to modify: `js/renderer.js` (add `data-vs` attribute to legend items), `app.js` (add click listener on `#legend` container), `styles.css` (add `cursor: pointer` to `.legend-item`)
- Key integration points: `app.js` `initializeApp()` after the `dateTabs` click listener (~line 203); `js/renderer.js` `renderLegend()` inside the `forEach` loop (~line 88); `styles.css` `.legend-item` rule (~line 156)
- Testing strategy: unit test for `data-vs` attribute presence; integration test for click → search update flow
- Conventions to follow: event delegation with `closest()`, `dataset.*` attributes, guard-clause early return, `applyCurrentFilters()` for triggering re-render

**Files the planner must verify exist before writing the plan**:
- `app.js` — confirm `initializeApp()` structure and existing listener patterns
- `js/renderer.js` — confirm `renderLegend()` loop structure
- `styles.css` — confirm `.legend-item` rule location

**What @ema-planner should do**:
1. Read this architecture artifact at the path above
2. Verify the listed files exist and match the descriptions
3. Produce a step-by-step plan with exact file paths, function signatures, and commit messages
4. Save plan to `artifacts/2026-03-24-legend-click-search-plan.md`
