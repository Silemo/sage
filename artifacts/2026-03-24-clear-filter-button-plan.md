## Summary

Implement a conditionally visible "Clear filters" button in the schedule viewer. The button appears at the bottom-right of the controls panel (within the legend row) whenever a non-default search or scope filter is active. Clicking it resets filters to "All activities" and empty search, preserving the currently selected date.

## Upstream Artifacts
- Architecture: [artifacts/2026-03-24-clear-filter-button-architecture.md](artifacts/2026-03-24-clear-filter-button-architecture.md)

## Implementation Steps

### Step 1: Update HTML structure to include the clear filters button
- **File**: [index.html](index.html)
- **Changes**:
    - Wrap the existing `#legend` div in a new `<div class="legend-row">` container.
    - Add the `<button id="clearFiltersButton" type="button" class="clear-filters-button" hidden>✕ Clear filters</button>` after the legend div inside the new container.
- **Rationale**: Provides the DOM structure for flex positioning and conditional visibility.
- **Commit message**: `feat(ui): add clear filters button to index.html`

### Step 2: Add styles for the legend row and clear button
- **File**: [styles.css](styles.css)
- **Changes**:
    - Add `.legend-row` class with `display: flex`, `justify-content: space-between`, and `margin-top: 16px`.
    - Modify `.legend` to set `margin-top: 0` (as the wrapper now handles it).
    - Add `.clear-filters-button` styles: pill shape, teal background (`var(--accent)`), white text, bold font, and hover/focus effects.
- **Rationale**: Ensures the button is visually distinct from legend items and positioned correctly at the bottom right.
- **Commit message**: `style(ui): style legend row and clear filters button`

### Step 3: Implement filter clearing and visibility logic in app.js
- **File**: [app.js](app.js)
- **Changes**:
    - Update `getElements()` to include `clearFiltersButton`.
    - Add `isFilterActive(filterState)` helper (checks if mode is not "all" or search is not empty).
    - Add `updateClearButton()` to toggle the `hidden` attribute based on `isFilterActive()`.
    - Add `clearFilters()` function to reset `appState.filterState`, update input/select values, and call `applyCurrentFilters()`.
    - Update `updateView()` to call `updateClearButton()` after rendering the legend.
    - Update `initializeApp()` to wire the `click` event listener for `clearFiltersButton`.
- **Rationale**: Bridges the UI with the application state and ensures the button's visibility is always in sync with active filters.
- **Commit message**: `feat(logic): implement clear filters functionality and visibility toggle`

### Step 4: Add smoke tests for clear filters functionality
- **File**: [test.html](test.html) (or a new test file if preferred)
- **Changes**:
    - Add a test case to verify that the clear button appears when search is entered.
    - Add a test case to verify that the clear button appears when scope is changed.
    - Add a test case to verify that clicking the button resets filters and hides the button.
- **Rationale**: Ensures the new feature works as expected and doesn't regress.
- **Commit message**: `test(ui): add smoke tests for clear filters button`

## Handoff

**Artifact saved**: `artifacts/2026-03-24-clear-filter-button-plan.md`

**Next Agent**: `@ema-implementer-lite`

**Context for @ema-implementer-lite**:
- Total steps: 4
- Primary files: `index.html`, `styles.css`, `app.js`, `test.html`
- Key logic: `appState.filterState` reset, `hidden` attribute toggling, flexbox layout for the legend row.
- Visual detail: Teal background (`#0f766e`) for the button makes it look like a primary action, distinct from grey legend items.

> 📋 **Model**: Select **Gemini 3 Flash** before invoking `@ema-implementer-lite`

**What @ema-implementer-lite should do**:
1. Follow the plan in `artifacts/2026-03-24-clear-filter-button-plan.md`.
2. Implement all steps in a single turn.
3. Verify changes by checking for lint/compile errors (though this is vanilla JS/CSS).
4. Do NOT commit changes; leave them staged.
