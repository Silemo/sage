## Summary

Add client-side 30-minute timeslot grouping to the SAGE schedule viewer. Events are bucketed by their start time (rounded down to the nearest 30 minutes), rendered as collapsible groups with accessible headers, and displayed in a responsive two-column (desktop) / sticky-header (mobile) layout. Empty buckets are hidden, and the page auto-scrolls to the first upcoming timeslot on load. A new pure-logic module `js/timeslot.js` handles grouping; rendering changes live in `js/renderer.js`; orchestration in `app.js`; layout in `styles.css`.

## Codebase Context

- **Entry point** ([app.js](../app.js)): Bootstraps the app, holds `appState` (`allEvents`, `colors`, `hierarchy`, `filterState`, `indicatorTimer`). The render pipeline is: `filterEvents()` → `renderCards()` → `renderLegend()` → `insertIndicator()` → `writeState()` → `updateTitle()`, all called from `updateView()`.
- **Rendering** ([js/renderer.js](../js/renderer.js)): `renderCards(container, events, colorMap)` clears the container and appends flat `.room-card` article elements. `createRoomCard(event, colorMap)` builds each card with `.card-time`, `.card-team`, detail rows, and `.card-type`.
- **Filtering** ([js/filter.js](../js/filter.js)): `filterEvents()` returns events sorted by start time (string comparison `"08:55" < "09:00"`). Events have `{ date, start, end, name, teams, vs, topics, location, type, source, id }`. Times are `"HH:MM"` strings.
- **Time indicator** ([js/time-indicator.js](../js/time-indicator.js)): `insertIndicator()` queries `.room-card` elements in the container and inserts a "Now" bar between cards. It uses `container.insertBefore(indicator, target)` where `target` is a direct child — this **breaks** with nested group containers because cards would no longer be direct children of the container.
- **Layout** ([styles.css](../styles.css)): `.rooms` is a CSS grid (`1fr` → `repeat(2, 1fr)` → `repeat(3, 1fr)` at 600px/900px breakpoints). Cards have fade-in animation and hover lift.
- **DOM** ([index.html](../index.html)): `<section id="rooms-container" class="rooms" aria-live="polite">` is the render target. It already has `aria-live="polite"` for assistive tech announcements.
- **Testing** ([tests/](../tests/)): Node-based tests using `node:assert/strict` with a minimal DOM shim (`installMinimalDom()`). Browser-based smoke tests in `test.html`. Tests import directly from `js/` modules.
- **Existing patterns**: Small, focused ES modules (~50-130 lines each). Pure functions where possible. Constructor-less functional style. No build step — raw ES modules loaded via `<script type="module">`.

## Design Approaches Considered

### Approach A: New `js/timeslot.js` module with grouped rendering ⭐ (recommended)

- **Description**: Create a new pure module `js/timeslot.js` containing the grouping/bucketing logic (no DOM dependencies). Add a new `renderTimeslotGroups()` function to `js/renderer.js` that produces the grouped DOM structure. Modify `app.js` to call the new functions instead of `renderCards()`. Replace the time indicator with a "now" marker on the current group header. Add responsive CSS for desktop two-column and mobile sticky-header layouts.
- **Pros**:
  - **Testable**: Grouping logic is pure (input: events array → output: buckets array). Unit tests don't need DOM shims.
  - **Follows existing conventions**: Each `js/` module has a single responsibility; this adds one new module rather than inflating existing ones.
  - **Clean integration**: `app.js` orchestration changes are minimal — swap `renderCards()` for `renderTimeslotGroups()`.
  - **Time indicator replacement is natural**: The "now" group header serves the same purpose as the inserted indicator bar, but works correctly with nested DOM.
- **Cons**:
  - Adds a new file to the project (but small and focused).
  - `renderTimeslotGroups()` is more complex than `renderCards()` (~50 more lines).

### Approach B: Grouping and rendering combined in `renderer.js`

- **Description**: Add both the bucketing logic and the grouped rendering to `renderer.js`. No new modules.
- **Pros**:
  - No new files — all rendering-related code stays in one place.
  - Fewer imports in `app.js`.
- **Cons**:
  - **`renderer.js` doubles in size** (currently 104 lines → ~200+), mixing pure data logic with DOM manipulation.
  - **Harder to test**: Grouping logic is entangled with DOM creation, requiring DOM shims for what should be pure function tests.
  - **Violates single-responsibility**: The existing modules are tightly focused; this would be the first "fat" module.

### Approach C: CSS-only grouping via data attributes

- **Description**: Keep `renderCards()` flat but add `data-bucket` attributes to each card. Use CSS to visually group cards (borders, spacing, pseudo-element headers) and JavaScript only for collapse toggles.
- **Pros**:
  - Minimal JS changes — rendering stays flat.
  - CSS-only grouping is lightweight.
- **Cons**:
  - **Cannot produce real group headers with event counts and collapse controls** — CSS pseudo-elements can't contain interactive buttons or dynamic text (event count).
  - **Sticky headers impossible** without a real DOM element to position.
  - **Accessibility gaps**: No semantic grouping for screen readers; no `aria-expanded` toggles.
  - Doesn't meet the requirements for collapse behavior, event counts, or ARIA roles.

## Chosen Design

**Approach A — New `js/timeslot.js` module with grouped rendering.** It follows the project's established pattern of small focused modules, keeps grouping logic pure and testable, and cleanly replaces the time indicator (which would break with nested DOM anyway). The modest file addition is justified by the testability and separation-of-concerns benefits.

### Components

**New:**
- `js/timeslot.js` — Pure grouping logic: `groupEventsByTimeslot()`, `getBucketKey()`, `formatBucketLabel()`, `findCurrentBucketIndex()`

**Modified:**
- `js/renderer.js` — Add `renderTimeslotGroups()` function that creates the grouped DOM structure; existing `renderCards()` and `createRoomCard()` remain (the latter is reused inside groups)
- `app.js` — Replace `renderCards()` call with grouped rendering pipeline; add auto-scroll logic; adapt time indicator integration; wire collapse toggle event delegation
- `styles.css` — Add `.timeslot-group`, `.timeslot-header`, `.timeslot-label`, `.timeslot-count`, `.timeslot-toggle`, `.timeslot-cards`, `.timeslot-now` styles; responsive layout rules; collapse animation
- `js/time-indicator.js` — Adapt `insertIndicator()` to mark the current timeslot group header instead of inserting between cards (or add a parallel `highlightCurrentTimeslot()` function and deprecate the insert approach for grouped views)

### Data Flow

```
filterEvents(allEvents, filterState)
  → sorted events array (existing, unchanged)

groupEventsByTimeslot(sortedEvents, 30)
  → [ { bucketKey: "08:30", bucketLabel: "08:30 – 09:00", events: [...] },
       { bucketKey: "09:00", bucketLabel: "09:00 – 09:30", events: [...] },
       ... ]
  (empty buckets never created — only events that exist produce buckets)

findCurrentBucketIndex(buckets, now, selectedDate)
  → index of first bucket where bucketKey >= current time bucket (or -1 if past)

renderTimeslotGroups(container, buckets, colorMap, { expandedCount: 4, currentBucketIndex })
  → builds DOM:
     .timeslot-group[data-bucket="08:30"]
       .timeslot-header (role="heading", aria-level="3")
         .timeslot-label "08:30 – 09:00"
         .timeslot-count "3 events"
         button.timeslot-toggle (aria-expanded="true/false")
       .timeslot-cards
         article.room-card (reuses existing createRoomCard)
         article.room-card
         ...

autoScrollToCurrentTimeslot(container, currentBucketIndex)
  → smooth-scrolls to the first upcoming group; moves focus to its header
  → announces via aria-live: "Showing events from 09:00 – 09:30, 3 events"

Collapse toggle click (delegated on container):
  → toggles .timeslot-cards visibility
  → updates aria-expanded on button
```

### Interfaces and Contracts

**`js/timeslot.js` — new module:**

```javascript
/**
 * Rounds a "HH:MM" time string down to the nearest bucket boundary.
 * getBucketKey("09:15", 30) → "09:00"
 * getBucketKey("09:30", 30) → "09:30"
 * getBucketKey("09:00", 30) → "09:00"
 */
export function getBucketKey(timeString, bucketMinutes = 30) → string

/**
 * Formats a bucket key into a human-readable range label.
 * formatBucketLabel("09:00", 30) → "09:00 – 09:30"
 * formatBucketLabel("23:30", 30) → "23:30 – 00:00"
 */
export function formatBucketLabel(bucketKey, bucketMinutes = 30) → string

/**
 * Groups a sorted array of events into 30-minute timeslot buckets.
 * Returns only non-empty buckets, sorted by bucketKey.
 *
 * @param {Array<Event>} events — pre-sorted by start time
 * @param {number} bucketMinutes — bucket size (default 30)
 * @returns {Array<{ bucketKey: string, bucketLabel: string, events: Array<Event> }>}
 */
export function groupEventsByTimeslot(events, bucketMinutes = 30) → Array<Bucket>

/**
 * Finds the index of the first bucket that is >= the current time bucket.
 * Returns -1 if all buckets are in the past or selectedDate is not today.
 *
 * @param {Array<Bucket>} buckets
 * @param {string} selectedDate — "YYYY-MM-DD"
 * @param {Date} now — current time (injectable for testing)
 */
export function findCurrentBucketIndex(buckets, selectedDate, now = new Date()) → number
```

**`js/renderer.js` — new function (addition):**

```javascript
/**
 * Renders events grouped by timeslot into the container.
 *
 * @param {HTMLElement} container — the #rooms-container element
 * @param {Array<Bucket>} buckets — from groupEventsByTimeslot()
 * @param {Object} colorMap — from config/colors.json
 * @param {Object} options
 * @param {number} options.expandedCount — number of upcoming groups to expand (default 4)
 * @param {number} options.currentBucketIndex — index of the "now" bucket (-1 if none)
 * @returns {Array<HTMLElement>} — the created .timeslot-group elements
 */
export function renderTimeslotGroups(container, buckets, colorMap, options = {}) → Array<HTMLElement>
```

**`app.js` — modified `updateView()`:**

```javascript
function updateView() {
  const elements = getElements();
  const selectedEvents = getSelectedEvents();
  const buckets = groupEventsByTimeslot(selectedEvents);
  const currentBucketIndex = findCurrentBucketIndex(
    buckets, appState.filterState.date
  );
  renderTimeslotGroups(elements.rooms, buckets, appState.colors, {
    expandedCount: 4,
    currentBucketIndex,
  });
  renderLegend(elements.legend, appState.colors, selectedEvents);
  updateClearButton();
  // Time indicator replaced by currentBucketIndex highlighting in renderTimeslotGroups
  writeState(appState.filterState);
  updateTitle();
}
```

**`app.js` — new auto-scroll function (called once after initial render):**

```javascript
function autoScrollToCurrentTimeslot(container) {
  const nowGroup = container.querySelector(".timeslot-now");
  if (!nowGroup) return;
  nowGroup.scrollIntoView({ behavior: "smooth", block: "start" });
  const header = nowGroup.querySelector(".timeslot-header");
  if (header) header.focus({ preventScroll: true });
  // ARIA announcement via existing aria-live on container
}
```

### DOM Structure

```html
<section id="rooms-container" class="rooms timeslot-layout" aria-live="polite">

  <div class="timeslot-group timeslot-now" data-bucket="09:00">
    <div class="timeslot-header" role="heading" aria-level="3">
      <span class="timeslot-label">09:00 – 09:30</span>
      <span class="timeslot-count">3 events</span>
      <button class="timeslot-toggle" aria-expanded="true" aria-label="Collapse 09:00 – 09:30">
        ▾
      </button>
    </div>
    <div class="timeslot-cards">
      <article class="room-card"><!-- existing card structure --></article>
      <article class="room-card"><!-- ... --></article>
    </div>
  </div>

  <div class="timeslot-group" data-bucket="09:30">
    <div class="timeslot-header" role="heading" aria-level="3">
      <span class="timeslot-label">09:30 – 10:00</span>
      <span class="timeslot-count">1 event</span>
      <button class="timeslot-toggle" aria-expanded="true" aria-label="Collapse 09:30 – 10:00">
        ▾
      </button>
    </div>
    <div class="timeslot-cards">
      <article class="room-card"><!-- ... --></article>
    </div>
  </div>

  <!-- collapsed group (5th+ from "now") -->
  <div class="timeslot-group timeslot-collapsed" data-bucket="11:00">
    <div class="timeslot-header" role="heading" aria-level="3">
      <span class="timeslot-label">11:00 – 11:30</span>
      <span class="timeslot-count">2 events</span>
      <button class="timeslot-toggle" aria-expanded="false" aria-label="Expand 11:00 – 11:30">
        ▸
      </button>
    </div>
    <div class="timeslot-cards" hidden>
      <!-- cards exist but hidden -->
    </div>
  </div>

</section>
```

### CSS Layout Strategy

**Desktop (≥ 900px):**
```
.timeslot-group:
  display: grid
  grid-template-columns: 160px 1fr
  gap: 0 20px
  align-items: start

.timeslot-header:
  position: sticky
  top: 0
  align-self: start
  (sits in left column, stays visible while scrolling through tall groups)

.timeslot-cards:
  display: grid
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr))
  gap: 15px
  (fills right column with responsive card grid)
```

**Mobile (< 900px):**
```
.timeslot-group:
  display: block

.timeslot-header:
  position: sticky
  top: 0
  z-index: 10
  background: var(--surface)  (solid background to cover scrolling cards)
  (full-width sticky bar with time label, count, toggle)

.timeslot-cards:
  display: grid
  grid-template-columns: 1fr  (or repeat(2, 1fr) at 600px+)
  gap: 15px
```

**"Now" group highlighting:**
```
.timeslot-now .timeslot-header:
  border-left: 4px solid var(--accent)
  background: var(--accent-soft)
```

**Collapse animation:**
```
.timeslot-collapsed .timeslot-cards:
  display: none  (or hidden attribute for a11y)
```

### Integration Points

- **`updateView()` in [app.js](../app.js#L174)**: Replace `renderCards()` with `groupEventsByTimeslot()` + `renderTimeslotGroups()`. Remove `insertIndicator()` call (replaced by `currentBucketIndex` highlighting).
- **`initializeApp()` in [app.js](../app.js#L198)**: After `applyCurrentFilters()`, call `autoScrollToCurrentTimeslot()` once. Wire collapse toggle delegation on `rooms` container.
- **`startIndicatorUpdates()` in [app.js](../app.js#L257)**: Adapt or replace. Instead of re-inserting a time indicator every 60s, update the `.timeslot-now` class on the correct group every 60s.
- **`renderCards()` in [js/renderer.js](../js/renderer.js#L62)**: Keep existing function untouched (reuse `createRoomCard()` from it). Add `renderTimeslotGroups()` alongside.
- **`.rooms` CSS in [styles.css](../styles.css#L212)**: The `.rooms` grid rules are superseded when `.timeslot-layout` is present. Use `.rooms.timeslot-layout` selector to avoid breaking existing styles if `renderCards()` is ever used without grouping.

### Time Indicator Adaptation

The existing `insertIndicator()` uses `container.insertBefore(indicator, target)` where `target` must be a direct child of `container`. With grouped DOM, cards are nested inside `.timeslot-cards` containers, so this call would fail.

**Solution**: Replace the time indicator with a "now" class on the current timeslot group header:
1. `renderTimeslotGroups()` adds `.timeslot-now` to the current group based on `currentBucketIndex`.
2. A periodic updater (replacing `startIndicatorUpdates`) re-evaluates `findCurrentBucketIndex()` every 60s and moves the `.timeslot-now` class if the bucket has changed.
3. The `.timeslot-now` header gets a distinct visual treatment (accent border + soft background), functionally replacing the "Now - HH:MM" bar.

The existing `time-indicator.js` functions remain available for backward compatibility but are no longer called from the grouped view path.

## Error Handling

- **No events after filtering**: `groupEventsByTimeslot([])` returns `[]`. `renderTimeslotGroups()` delegates to existing `renderEmptyState()` when buckets array is empty.
- **Invalid time strings**: `getBucketKey()` uses a guard clause — if the time doesn't match `HH:MM`, the event is placed in a "??" fallback bucket. Events with validation errors are already filtered out by `normalizeRecord()` in the loader.
- **Auto-scroll target missing**: `autoScrollToCurrentTimeslot()` checks for `.timeslot-now` existence; if not found (all events in the past or future date selected), no scroll occurs.
- **Collapse toggle on missing element**: Event delegation checks `event.target.closest(".timeslot-toggle")` — no-op if no toggle found.

## Testing Strategy

**Unit tests** (new file `tests/timeslot-grouping-spec.mjs`):
1. `getBucketKey` — rounds times correctly: `"09:00"` → `"09:00"`, `"09:15"` → `"09:00"`, `"09:30"` → `"09:30"`, `"09:29"` → `"09:00"`, `"23:45"` → `"23:30"`
2. `formatBucketLabel` — produces correct range: `"09:00"` → `"09:00 – 09:30"`, `"23:30"` → `"23:30 – 00:00"`
3. `groupEventsByTimeslot` with mixed start times — correct bucket assignment, correct sorting within buckets, no empty buckets
4. `groupEventsByTimeslot` with empty array — returns empty array
5. `groupEventsByTimeslot` with events exactly on bucket boundaries — `"09:00"` goes in `"09:00"` bucket, `"09:30"` goes in `"09:30"` bucket
6. `findCurrentBucketIndex` — returns correct index for "now" between buckets; returns -1 for non-today dates; returns 0 when all buckets are in the future; returns -1 when all buckets are in the past

**Integration / manual tests:**
1. Load page with full dataset → events appear in timeslot groups, no empty buckets visible
2. Apply a filter that hides some events → groups with no remaining visible events disappear entirely
3. On mobile, scroll within a group → timeslot header sticks to top of viewport
4. Desktop layout → time labels on left, cards on right
5. Keyboard: tab to collapse toggle → Enter/Space toggles group → `aria-expanded` updates
6. Auto-scroll: load page on a day with future events → view scrolls to first upcoming group

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Sticky headers broken by parent `overflow` | Medium | Ensure no ancestor of `.timeslot-group` sets `overflow: hidden/auto/scroll` that would break `position: sticky`. The `.page-shell` and `body` use default `overflow: visible`. Test explicitly. |
| Time indicator regression | Low | Keep `time-indicator.js` functions intact; only change the call site in `app.js`. If grouped rendering is disabled, the old path still works. |
| Auto-scroll is jarring on page load | Low | Use `behavior: "smooth"` for scroll. Only auto-scroll on initial load, not on filter changes. Focus the header after scroll for screen readers. |
| Timezone mismatch in bucket computation | Medium | `getBucketKey()` operates on `"HH:MM"` strings from the data, which are already in the schedule's display timezone. The `findCurrentBucketIndex()` function uses `new Date().toTimeString().slice(0, 5)` which returns local time. If the browser timezone differs from the schedule timezone, the "now" highlight will be wrong. Document this assumption; no timezone conversion is needed if users are in the same timezone as the event. |
| Filter change leaves collapsed "now" group | Low | `renderTimeslotGroups()` always expands the first N upcoming groups on every render. User collapse overrides are not preserved across filter changes (re-render resets them). |
| Card animation flicker on re-render | Low | Use `DocumentFragment` for batch DOM insertion. Existing `fadeIn` animation on `.room-card` applies naturally. |
| Layout shift when groups collapse/expand | Low | Use `hidden` attribute on `.timeslot-cards` for collapse (instant, no layout animation needed). `aria-expanded` stays in sync. |

## Handoff

**Artifact saved**: `artifacts/2026-03-24-timeslot-grouping-architecture.md`

**Path signal**: full → @ema-planner (multiple files, new module, DOM restructuring, CSS layout changes, time indicator adaptation)

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-planner`

**Upstream artifacts**:
- Requirements: `artifacts/2026-03-24-timeslot-grouping-requirements.md`

**Context for @ema-planner**:
- Chosen approach: New `js/timeslot.js` pure module for grouping logic + `renderTimeslotGroups()` in `renderer.js` + orchestration in `app.js` + responsive CSS
- Files to create: `js/timeslot.js` (pure grouping functions), `tests/timeslot-grouping-spec.mjs` (unit tests for grouping)
- Files to modify: `js/renderer.js` (add `renderTimeslotGroups()`), `app.js` (replace `renderCards()` call, add auto-scroll, wire collapse toggles, adapt time indicator), `styles.css` (add timeslot group layout, sticky headers, collapse styles, "now" highlight, responsive rules)
- Key integration points: `updateView()` at line ~174 in `app.js` — replace `renderCards()` + `insertIndicator()` with grouped pipeline; `initializeApp()` at line ~211 — add auto-scroll after first render + collapse toggle delegation; `createRoomCard()` at line ~21 in `renderer.js` — reused inside groups; `.rooms` CSS at line ~212 in `styles.css` — add `.timeslot-layout` variant
- Testing strategy: unit tests for `getBucketKey`, `formatBucketLabel`, `groupEventsByTimeslot`, `findCurrentBucketIndex` + manual QA for sticky headers, auto-scroll, collapse, responsive layout
- Conventions to follow: ES module exports, pure functions where possible, `node:assert/strict` for tests, existing CSS custom properties (`--accent`, `--surface`, `--text-muted`, etc.), `hidden` attribute for visibility, delegated event handling, `aria-expanded` / `role="heading"` for accessibility

**Files the planner must verify exist before writing the plan**:
- `app.js` — confirm `updateView()` structure (renderCards → renderLegend → insertIndicator → writeState → updateTitle) and `initializeApp()` hook points
- `js/renderer.js` — confirm `renderCards()`, `createRoomCard()`, `clearContainer()` signatures
- `js/filter.js` — confirm `filterEvents()` returns sorted events with `start` as `"HH:MM"` string
- `js/time-indicator.js` — confirm `insertIndicator()` and `startIndicatorUpdates()` signatures for adaptation
- `styles.css` — confirm `.rooms` grid rules and responsive breakpoints at 600px/900px
- `index.html` — confirm `#rooms-container` has `aria-live="polite"`

**What @ema-planner should do**:
1. Read this architecture artifact at the path above
2. Read the requirements at `artifacts/2026-03-24-timeslot-grouping-requirements.md`
3. Verify the listed files exist and match the descriptions
4. Produce a step-by-step plan with exact file paths, function signatures, and commit messages
5. Save plan to `artifacts/2026-03-24-timeslot-grouping-plan.md`

