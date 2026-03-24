## Summary
Add click-to-search functionality to the value stream legend. Clicking on a legend item will update the search filter to that value stream's name, update the search input field, and refresh the view.

## Steps

### Step 1: Add data-vs attribute to legend items
- **File**: `js/renderer.js` (modify)
- **Changes**: Inside the `renderLegend` function, set the `data-vs` attribute on the `item` element to the current `valueStream` name.
- **Rationale**: Enables event delegation by providing a way to identify the clicked value stream.
- **Tests**: Verify that the legend items in the DOM now have a `data-vs` attribute.
- **Commit message**: `feat(legend): add data-vs attribute to legend items`

### Step 2: Add click listener for legend in app.js
- **File**: `app.js` (modify)
- **Changes**: In the `initializeApp` function, get the `legend` element from `getElements()` and add a "click" event listener. Use `closest('.legend-item[data-vs]')` to handle clicks on the item or its children (like the swatch or label). If found, update `appState.filterState.search`, update `searchInput.value`, and call `applyCurrentFilters()`.
- **Rationale**: Implements the click behavior using efficient event delegation, mirroring the pattern used for date tabs.
- **Tests**: Click on a legend item and verify that the search input updates and the view filters accordingly.
- **Commit message**: `feat(legend): add click-to-search behavior to legend items`

### Step 3: Add pointer cursor to legend items
- **File**: `styles.css` (modify)
- **Changes**: Add `cursor: pointer;` and `user-select: none;` to the `.legend-item` class.
- **Rationale**: Provides visual feedback that the items are interactive.
- **Tests**: Hover over a legend item and verify the cursor changes to a pointer.
- **Commit message**: `style(legend): add pointer cursor to legend items`

## Testing Approach
Manual verification:
1. Open the application.
2. Hover over a legend item (e.g., "MON") and verify the pointer cursor.
3. Click the legend item.
4. Verify the search input field now contains "MON".
5. Verify the activities are filtered to only show those matching "MON".
6. Verify the URL is updated with `search=MON`.
7. Click a different value stream and verify the filter updates.

Automated verification (if applicable):
- Run existing tests to ensure no regressions: `npm test` (or equivalent test command found in the codebase).

## Handoff

**Artifact saved**: `artifacts/2026-03-24-legend-click-search-plan.md`

**Upstream artifacts**:
- Architecture: `artifacts/2026-03-24-legend-click-search-architecture.md`

**Context for @ema-implementer-lite**:
- 3 steps to execute.
- Files affected: `js/renderer.js`, `app.js`, `styles.css`.
- Test command: Manual verification in the browser is primary; check console for errors.
- Watch for: Ensure `searchInput.value` is updated along with `appState` to keep the UI in sync. The click listener should be added to the `legend` container obtained from `getElements()`.

> 📋 **Model**: Select **Gemini 3 Flash** before invoking `@ema-implementer-lite`

**What @ema-implementer-lite should do**:
1. Read the plan artifact at `artifacts/2026-03-24-legend-click-search-plan.md`.
2. Execute each step sequentially.
3. Verify the changes visually or via tests.
4. Save implementation summary to `artifacts/2026-03-24-legend-click-search-implementation.md`.
