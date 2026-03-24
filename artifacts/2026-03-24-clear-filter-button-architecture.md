## Summary

Add a "Clear Filters" button to the controls panel, positioned at the bottom-right alongside the legend row. When clicked it resets scope to "All activities" and empties the search bar, while preserving the currently selected date. The button is conditionally visible — shown only when a non-default filter is active.

## Codebase Context

- **HTML structure** ([index.html](index.html)): The `controls-panel` section contains date tabs, a `.controls` grid (search input + scope select), an optional status message, and a `#legend` div at the bottom.
- **Legend rendering** ([js/renderer.js](js/renderer.js#L75)): `renderLegend()` populates `#legend` with `.legend-item` pill elements — colored swatches with text labels. Legend items are clickable (they populate the search bar via a delegated click handler in [app.js](app.js#L202)).
- **Filter state** ([app.js](app.js#L7)): `appState.filterState` holds `{ date, mode, value, search }`. The default/cleared state is `mode: "all"`, `value: ""`, `search: ""`.
- **URL state** ([js/url-state.js](js/url-state.js)): `writeState()` persists filter state to URL params and localStorage. Clearing filters will naturally write the default state.
- **Scope select** ([app.js](app.js#L98)): `buildScopeSelect()` builds the dropdown; the "all" option maps to mode `"all"`.
- **Styling** ([styles.css](styles.css)): Legend uses `display: flex; flex-wrap: wrap; gap: 10px; margin-top: 16px`. Legend items are pill-shaped with `border-radius: 999px`. The design language is rounded, soft, teal-accent.

## Design Approaches Considered

### Approach A: Always-visible button ✦

- **Description**: A "Clear Filters" button is always rendered in the DOM next to the legend, regardless of current filter state. It is visually present even when scope is already "All activities" and search is empty.
- **Pros**:
  - Simplest implementation — no conditional visibility logic needed.
  - The button is always in the same place so users build muscle memory.
  - No layout shift when the button appears/disappears.
- **Cons**:
  - **Unintuitive UX**: A "Clear" button that does nothing when there's nothing to clear is confusing. Users may click it expecting something to happen, or wonder what filters are active.
  - Adds visual clutter to the default view when no filters are set.
  - Violates progressive disclosure — showing actions that aren't applicable.
  - The button visually competes with the legend items for attention even when irrelevant.

### Approach B: Conditionally visible button (show only when filters are active) ⭐ (recommended)

- **Description**: The "Clear Filters" button is rendered in the DOM but hidden via a CSS class when filters are at their defaults (`mode === "all"` and `search === ""`). It appears with a subtle transition when any filter deviates from default.
- **Pros**:
  - **Clean default state**: The legend row is uncluttered when no filters are active.
  - **Intuitive affordance**: The button's presence signals "you have active filters" — it acts as both a visual indicator and an action.
  - Follows progressive disclosure: show controls when they're relevant.
  - Minimal implementation overhead — one boolean check (`isFilterActive`) toggles a CSS class.
- **Cons**:
  - Slight layout shift when the button appears/disappears (mitigated with CSS transitions).
  - Users must discover the button exists (but this is fine — it appears exactly when they need it).

### Approach C: Inline clear icons on each control

- **Description**: Instead of a single button, add small ✕ icons inside the search input and next to the scope dropdown, each clearing its own field independently.
- **Pros**:
  - Granular — users can clear search without changing scope and vice versa.
  - Follows patterns seen in many search UIs.
- **Cons**:
  - More complex: two separate clear mechanisms instead of one.
  - Doesn't solve the "reset everything" use case in one click — user must click two different things.
  - Modifying the scope `<select>` element's appearance is limited without replacing it with a custom component.
  - Doesn't match the user's stated requirement of a single "clear filter" button.

## Chosen Design

**Approach B — Conditionally visible button.** The implementation overhead is trivial (one boolean check + a CSS class toggle), and the UX is significantly better: the button's appearance signals "filters are active" while its absence keeps the default view clean. The user's own intuition was correct — always-visible would be less intuitive.

### Components

**Existing (modified):**
- [index.html](index.html) — Add a wrapper div around legend + clear button to enable flex layout. Add the button element.
- [styles.css](styles.css) — Add styles for the legend footer row (flex container), clear button styling, and hidden state.
- [app.js](app.js) — Add `clearFilters()` function, `updateClearButton()` visibility function, wire click handler, call `updateClearButton()` from `updateView()`.

**No new files needed.** This is a localized UI change touching three existing files.

### Visual Design

The button must be **visually distinct from legend items** to avoid confusion:

| Property | Legend item | Clear button |
|----------|-----------|--------------|
| Shape | Pill with color swatch | Pill with ✕ icon (text, no swatch) |
| Background | `var(--surface-muted)` (light grey) | `var(--accent)` (teal `#0f766e`) |
| Text color | `var(--text-strong)` (dark) | White (`#ffffff`) |
| Border | `1px solid var(--line)` | None |
| Font weight | Normal | 600 (semi-bold) |
| Content | `[swatch] Value Stream Name` | `✕ Clear filters` |
| Cursor | pointer | pointer |
| Hover | (none currently) | Slightly darker teal background |

This makes the button immediately recognizable as an action (teal accent = primary action in this design system) rather than a data indicator (grey legend items).

### Data Flow

```
User clicks "Clear Filters" button
  → clearFilters()
    → appState.filterState.mode = "all"
    → appState.filterState.value = ""
    → appState.filterState.search = ""
    → searchInput.value = ""
    → scopeSelect.value = "all"
    → applyCurrentFilters()
      → updateView()
        → renderCards(...)
        → renderLegend(...)
        → updateClearButton()  ← hides button since filters are now default
        → writeState(...)      ← URL updated to reflect cleared state
        → updateTitle()
```

### Interfaces and Contracts

**New function in `app.js`:**
```javascript
function isFilterActive(filterState) {
  return filterState.mode !== "all" || filterState.search !== "";
}
```

**New function in `app.js`:**
```javascript
function updateClearButton() {
  const clearButton = document.getElementById("clearFiltersButton");
  clearButton.hidden = !isFilterActive(appState.filterState);
}
```

**New function in `app.js`:**
```javascript
function clearFilters() {
  const { searchInput, scopeSelect } = getElements();
  appState.filterState.mode = "all";
  appState.filterState.value = "";
  appState.filterState.search = "";
  searchInput.value = "";
  scopeSelect.value = "all";
  applyCurrentFilters();
}
```

**HTML addition (inside `.controls-panel`, replacing the bare `#legend` div):**
```html
<div class="legend-row">
  <div id="legend" class="legend" aria-label="Value stream legend"></div>
  <button id="clearFiltersButton" type="button" class="clear-filters-button" hidden>
    ✕ Clear filters
  </button>
</div>
```

**CSS additions:**
```css
.legend-row {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  margin-top: 16px;
  gap: 12px;
}

.legend-row .legend {
  margin-top: 0;  /* override since parent handles spacing */
}

.clear-filters-button {
  flex-shrink: 0;
  align-self: flex-end;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  border: none;
  border-radius: 999px;
  background: var(--accent);
  color: #ffffff;
  font-size: 0.88rem;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.2s ease, opacity 0.2s ease;
  white-space: nowrap;
}

.clear-filters-button:hover {
  background: #0b5e58;
}

.clear-filters-button:focus {
  outline: 2px solid rgba(15, 118, 110, 0.25);
  outline-offset: 2px;
}
```

### Integration Points

- **`updateView()` in [app.js](app.js#L150)**: Add `updateClearButton()` call after `renderLegend()` so the button visibility stays in sync with filter state.
- **`getElements()` in [app.js](app.js#L24)**: Add `clearFiltersButton` to the element cache.
- **`initializeApp()` in [app.js](app.js#L173)**: Wire the click event listener on the clear button.
- **Legend `margin-top` in [styles.css](styles.css#L155)**: The `.legend` class currently has `margin-top: 16px` — this moves to the new `.legend-row` wrapper, and the `.legend` inside it gets `margin-top: 0`.

## Error Handling

- The button click handler is a simple state reset — no error paths exist. If `scopeSelect.value = "all"` fails to match (impossible since "all" is always the first option), the existing fallback in `buildScopeSelect` already handles it.
- The `hidden` attribute is used for visibility rather than CSS display toggling — this is the semantic HTML approach and is accessible by default (screen readers skip `hidden` elements).

## Testing Strategy

**Unit tests (new spec file `tests/clear-filter-button-spec.mjs`):**
1. `isFilterActive` returns `false` when mode is "all" and search is empty
2. `isFilterActive` returns `true` when mode is not "all"
3. `isFilterActive` returns `true` when search is non-empty
4. `isFilterActive` returns `true` when both mode and search are non-default

**Integration/smoke tests (browser-based in `test.html` or manual):**
1. Load the page — clear button is hidden
2. Type in search bar — clear button appears
3. Change scope dropdown — clear button appears
4. Click clear button — scope resets to "All activities", search empties, current date preserved, button hides
5. Click a legend item (which populates search) — clear button appears
6. Click clear button after legend click — search clears, button hides

**Note:** `isFilterActive` should be exported from `app.js` or extracted to a utility to enable unit testing. Alternatively, it can be tested indirectly through the DOM-based smoke tests.

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Button causes layout shift when appearing | Low | The `.legend-row` flex container accommodates the button space; `flex-shrink: 0` prevents legend reflow. The button appears at the end of the row. |
| Button not discoverable | Low | It appears exactly when filters are active — the moment users need it. Teal accent color draws attention. |
| Conflict with legend click handler | Low | The clear button is outside `#legend`, so the existing delegated `legend.addEventListener("click", ...)` won't fire for it. Separate handler on the button element. |
| Mobile responsiveness | Low | The `.legend-row` flex container wraps naturally. Button's `flex-shrink: 0` keeps it intact. Test on narrow viewports. |

## Handoff

**Artifact saved**: `artifacts/2026-03-24-clear-filter-button-architecture.md`

**Path signal**: unexpectedly simple (localized change across 3 files, no new abstractions, no new modules) → consider @ema-planner-lite instead

> 📋 **Model**: Select **Gemini 3 Flash** before invoking `@ema-planner-lite`

**Upstream artifacts**:
- None (user-provided verbal requirements)

**Context for @ema-planner**:
- Chosen approach: Conditionally visible "Clear Filters" button — shown only when filters deviate from defaults (mode !== "all" or search !== "")
- Files to create: none
- Files to modify: `index.html` (wrap legend in `.legend-row`, add button), `styles.css` (add `.legend-row` and `.clear-filters-button` styles, adjust `.legend` margin), `app.js` (add `isFilterActive()`, `updateClearButton()`, `clearFilters()`, wire handler, update `getElements()` and `updateView()`)
- Key integration points: `updateView()` at line ~155 in `app.js` — add `updateClearButton()` call; `initializeApp()` at line ~220 — add click handler; `getElements()` at line ~24 — add `clearFiltersButton`; `.legend` CSS rule at line ~155 in `styles.css` — move `margin-top` to wrapper
- Testing strategy: unit tests for `isFilterActive()`, DOM smoke tests for button visibility toggling and filter reset behavior
- Conventions to follow: `hidden` attribute for visibility, delegated event handling pattern from existing code, CSS custom properties, pill-shaped components

**Files the planner must verify exist before writing the plan**:
- `index.html` — confirm the `#legend` div location inside `.controls-panel`
- `styles.css` — confirm `.legend` styles and available CSS custom properties
- `app.js` — confirm `updateView()`, `getElements()`, `initializeApp()` structure and hook points

**What @ema-planner should do**:
1. Read this architecture artifact at the path above
2. Verify the listed files exist and match the descriptions
3. Produce a step-by-step plan with exact file paths, function signatures, and commit messages
4. Save plan to `artifacts/2026-03-24-clear-filter-button-plan.md`
