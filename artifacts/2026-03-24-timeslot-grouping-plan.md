## Summary

Implement 30-minute timeslot grouping for the SAGE schedule viewer using the architecture in `artifacts/2026-03-24-timeslot-grouping-architecture.md` and the requirements in `artifacts/2026-03-24-timeslot-grouping-requirements.md`.

Verified against the current codebase:
- Upstream artifacts exist:
  - `artifacts/2026-03-24-timeslot-grouping-architecture.md`
  - `artifacts/2026-03-24-timeslot-grouping-requirements.md`
- Existing source files confirmed:
  - `app.js`
  - `js/renderer.js`
  - `js/filter.js`
  - `js/time-indicator.js`
  - `styles.css`
  - `index.html`
  - `README.md`
- Existing test files confirmed that import `app.js` and will be affected by the DOM contract change:
  - `tests/clear-filter-button-spec.mjs`
  - `tests/legend-click-search-spec.mjs`
- Existing regression suite location confirmed in `tests/`

One implementation detail to carry forward from requirements: add a dedicated ARIA live region in `index.html` rather than relying only on `#rooms-container[aria-live]`, so filter-change announcements remain concise and do not conflict with status/warning messages.

## Steps

### Step 1: Add a dedicated ARIA live region for timeslot announcements
- **File**: `index.html` (modify)
- **Changes**:
  - Inside `.controls-panel` or immediately before `#rooms-container`, add a dedicated live region element:
    - `<p id="timeslotAnnouncements" class="visually-hidden" aria-live="polite" aria-atomic="true"></p>`
  - Leave `#rooms-container` in place as the render target.
  - Do not otherwise restructure the page shell.
- **Rationale**:
  - The requirements call for an ARIA live region or announcement on filter changes.
  - A dedicated hidden announcer is more reliable than reusing `#statusMessage` (which is already used for warnings/errors) and more concise than relying on full container re-renders to be announced.
- **Tests**:
  - App-level DOM tests should verify that `document.getElementById("timeslotAnnouncements")` is queried and can receive announcement text.
  - Manual QA: after changing filters, a screen reader should announce the currently shown timeslot summary once.
- **Commit message**: `feat(a11y): add dedicated timeslot live region`

### Step 2: Create pure timeslot bucketing utilities
- **File**: `js/timeslot.js` (create)
- **Changes**:
  - Add a new pure utility module containing only data/time helpers, no DOM access.
  - Implement the following exported functions:
    - `export function getBucketKey(timeString, bucketMinutes = 30)`
    - `export function formatBucketLabel(bucketKey, bucketMinutes = 30)`
    - `export function groupEventsByTimeslot(events, bucketMinutes = 30)`
    - `export function findCurrentBucketIndex(buckets, selectedDate, now = new Date())`
  - Add small internal helpers as needed, e.g.:
    - `parseTimeToMinutes(timeString)`
    - `formatMinutes(totalMinutes)`
  - `groupEventsByTimeslot(...)` should:
    - Accept already filtered events for a single date.
    - Bucket by rounded-down start time.
    - Return only non-empty buckets.
    - Preserve stable sort order within each bucket (events are already start-sorted by `filterEvents`, but add a bucket-local fallback sort by `start`, `end`, `name` for robustness).
    - Return objects shaped like:
      - `{ bucketKey, bucketLabel, events }`
  - `findCurrentBucketIndex(...)` should:
    - Return `-1` if `selectedDate` is not today.
    - Return the index of the first bucket whose `bucketKey` is greater than or equal to the current time bucket.
    - Return `-1` if all buckets are in the past.
- **Rationale**:
  - Keeps the bucketing algorithm testable and aligned with the project’s small-module pattern.
  - Allows renderer/app logic to consume a simple, predictable bucket structure.
- **Tests**:
  - New unit tests in `tests/timeslot-grouping-spec.mjs` for boundary rounding, formatting, empty inputs, and current-bucket selection.
- **Commit message**: `feat(timeslots): add pure bucket grouping utilities`

### Step 3: Extend the renderer with grouped timeslot output
- **File**: `js/renderer.js` (modify)
- **Changes**:
  - Keep existing exports (`clearContainer`, `createRoomCard`, `renderCards`, `renderLegend`) intact.
  - Add a new export:
    - `export function renderTimeslotGroups(container, buckets, colorMap, options = {})`
  - Implement renderer-local helpers as needed, for example:
    - `createTimeslotHeader(bucket, isExpanded, isCurrent)`
    - `createTimeslotGroup(bucket, colorMap, { isExpanded, isCurrent })`
  - `renderTimeslotGroups(...)` should:
    - Clear the container.
    - Add `timeslot-layout` to the container class list.
    - Render an empty state via existing `renderEmptyState(...)` when `buckets.length === 0`.
    - Build DOM with a `DocumentFragment`.
    - For each bucket, render:
      - `.timeslot-group[data-bucket="HH:MM"]`
      - `.timeslot-header` with `role="heading"`, `aria-level="3"`, `tabIndex = -1`
      - `.timeslot-label`
      - `.timeslot-count`
      - `button.timeslot-toggle` with `type="button"`, `aria-expanded`, `aria-controls`, and an `aria-label` like `Collapse 09:00 – 09:30`
      - `.timeslot-cards` containing existing `createRoomCard(...)` output
    - Apply `.timeslot-now` to the bucket at `options.currentBucketIndex`.
    - Expand/collapse initial groups based on `options.expandedCount`.
      - Expected rule: keep the first `expandedCount` upcoming buckets expanded, always keep the current/upcoming target expanded, and collapse later buckets by default.
  - Return the created `.timeslot-group` elements from `renderTimeslotGroups(...)`.
- **Rationale**:
  - Reuses the existing card renderer while introducing the grouped DOM contract required by the feature.
  - Keeps timeslot rendering isolated from app orchestration.
- **Tests**:
  - Add focused DOM-shim assertions in `tests/timeslot-grouping-spec.mjs` or `tests/requirements.spec.mjs` that `renderTimeslotGroups(...)`:
    - creates one `.timeslot-group` per bucket,
    - nests `.room-card` elements inside `.timeslot-cards`,
    - sets `aria-expanded` correctly,
    - marks the current bucket with `.timeslot-now`.
- **Commit message**: `feat(renderer): render grouped timeslot sections`

### Step 4: Adapt current-time indicator logic to grouped views
- **File**: `js/time-indicator.js` (modify)
- **Changes**:
  - Preserve the existing flat-card indicator functions for backward compatibility unless removal is trivial and safe.
  - Add grouped-view indicator helpers:
    - `export function clearTimeslotIndicator(container)`
    - `export function applyTimeslotIndicator(container, currentBucketIndex)`
    - `export function startTimeslotIndicatorUpdates(container, getCurrentBucketIndex)`
  - `applyTimeslotIndicator(...)` should:
    - Remove `.timeslot-now` from any existing group.
    - Add `.timeslot-now` to the `.timeslot-group` at the supplied index if it exists.
  - `startTimeslotIndicatorUpdates(...)` should:
    - Immediately apply the marker.
    - Re-run every 60 seconds using `window.setInterval(...)`.
    - Return the interval id so `app.js` can clear/restart it.
- **Rationale**:
  - The existing `insertIndicator(...)` assumes `.room-card` elements are direct children of the container; grouped DOM breaks that assumption.
  - A CSS-highlighted current group replaces the old inserted bar without changing the overall interaction model.
- **Tests**:
  - Add or extend DOM-shim tests to verify `.timeslot-now` moves to the expected group when the current bucket index changes.
  - Existing flat `.time-indicator` tests should remain valid if the legacy exports are preserved.
- **Commit message**: `refactor(time): support grouped current-timeslot highlighting`

### Step 5: Replace the flat-card render pipeline in `app.js`
- **File**: `app.js` (modify)
- **Changes**:
  - Update imports:
    - Remove the direct dependency on `renderCards(...)` in the main view path.
    - Import `renderTimeslotGroups(...)` from `js/renderer.js`.
    - Import `groupEventsByTimeslot(...)` and `findCurrentBucketIndex(...)` from `js/timeslot.js`.
    - Import grouped indicator helpers from `js/time-indicator.js`.
  - Extend `appState` with the minimum new state needed, e.g.:
    - `groupedBuckets: []`
    - `lastAutoScrolledDate: ""`
  - Update `getElements()` to include:
    - `announcements: document.getElementById("timeslotAnnouncements")`
  - Add focused helpers, with names along these lines:
    - `function getSelectedBuckets()`
    - `function announceCurrentTimeslot(container, announcements, bucketIndex, buckets)`
    - `function autoScrollToCurrentTimeslot(container)`
    - `function handleTimeslotToggleClick(clickEvent)`
  - Replace `updateView()` logic so it becomes:
    1. `const selectedEvents = getSelectedEvents();`
    2. `const buckets = groupEventsByTimeslot(selectedEvents, 30);`
    3. `const currentBucketIndex = findCurrentBucketIndex(buckets, appState.filterState.date);`
    4. Save `appState.groupedBuckets = buckets;`
    5. `renderTimeslotGroups(elements.rooms, buckets, appState.colors, { expandedCount: 4, currentBucketIndex });`
    6. `renderLegend(...)`
    7. `updateClearButton()`
    8. `writeState(...)`
    9. `updateTitle()`
    10. `announceCurrentTimeslot(...)`
  - Add initial auto-scroll behavior:
    - Run once on initial load after the first successful grouped render.
    - Optionally allow date-tab changes to auto-scroll only when the user switches to a date with future buckets, but do not auto-scroll on every search/filter keystroke.
  - Add delegated click handling on `rooms` for `.timeslot-toggle`:
    - Toggle `hidden` on the corresponding `.timeslot-cards`
    - Toggle `.timeslot-collapsed` on the group
    - Update `aria-expanded` and button label text/icon
  - Replace the existing timer setup in `initializeApp()`:
    - Stop calling the flat `insertIndicator(...)`/`startIndicatorUpdates(...)` path for grouped views.
    - Start the grouped timeslot indicator updater instead.
- **Rationale**:
  - This is the main orchestration step that makes grouping, toggle behavior, announcements, and auto-scroll work together.
- **Tests**:
  - Update app-level interaction tests to confirm:
    - the app still boots on `DOMContentLoaded`,
    - grouped renders still expose descendant `.room-card` counts correctly after filter changes,
    - collapse toggles exist and update `aria-expanded`,
    - announcement text is written to `#timeslotAnnouncements`,
    - auto-scroll/focus helpers do not throw in the fake DOM.
- **Commit message**: `feat(app): integrate grouped timeslot rendering pipeline`

### Step 6: Add responsive timeslot-group layout and accessibility styles
- **File**: `styles.css` (modify)
- **Changes**:
  - Add a reusable visually hidden utility used by the new live region:
    - `.visually-hidden { position: absolute; width: 1px; height: 1px; ... }`
  - Add grouped layout styles without breaking the existing base `.rooms` styles:
    - `.rooms.timeslot-layout`
    - `.timeslot-group`
    - `.timeslot-header`
    - `.timeslot-label`
    - `.timeslot-count`
    - `.timeslot-toggle`
    - `.timeslot-cards`
    - `.timeslot-collapsed`
    - `.timeslot-now .timeslot-header`
  - Mobile behavior (< 900px):
    - single-column groups
    - sticky header with `position: sticky`, `top: 0`, solid background, and `z-index`
    - cards stacked or 2-up only where already supported by existing card breakpoints
  - Desktop behavior (>= 900px):
    - `.timeslot-group { display: grid; grid-template-columns: 160px 1fr; gap: 0 20px; }`
    - header visually occupies the narrow time column
    - cards grid fills the right column
  - Ensure `.room-card` styling remains valid when cards are inside `.timeslot-cards` rather than being direct children of `.rooms`.
  - Add focus styles for `.timeslot-toggle` and `.timeslot-header:focus`.
- **Rationale**:
  - The new DOM structure requires a layout variant instead of the current flat grid.
  - Sticky header styling is the core mobile affordance in the requirements.
- **Tests**:
  - Manual QA at narrow and wide widths.
  - Browser smoke check via `test.html` or local preview to verify sticky headers and two-column layout.
- **Commit message**: `style(timeslots): add grouped responsive schedule layout`

### Step 7: Add new timeslot tests and update existing app DOM harnesses
- **File**: `tests/timeslot-grouping-spec.mjs` (create)
- **Changes**:
  - Create a focused spec for the new bucketing module and grouped renderer.
  - Cover these cases explicitly:
    - `getBucketKey("09:00") === "09:00"`
    - `getBucketKey("09:15") === "09:00"`
    - `getBucketKey("09:30") === "09:30"`
    - `getBucketKey("23:45") === "23:30"`
    - `formatBucketLabel("23:30") === "23:30 – 00:00"`
    - grouping mixed event times into the correct buckets
    - preserving per-bucket sort order
    - handling empty input
    - `findCurrentBucketIndex(...)` for non-today, future, and all-past cases
  - Include a minimal DOM shim if renderer assertions are kept in this file.
- **Rationale**:
  - This is the deterministic unit coverage explicitly requested in the requirements.
- **Tests**:
  - The file itself is the test.
- **Commit message**: `test(timeslots): add bucket grouping unit coverage`

### Step 8: Update existing app interaction tests for the grouped DOM contract
- **Files**:
  - `tests/clear-filter-button-spec.mjs` (modify)
  - `tests/legend-click-search-spec.mjs` (modify)
- **Changes**:
  - Extend each fake DOM helper to support the additional DOM APIs used by grouped rendering and auto-scroll, at minimum where needed:
    - extra selector matching for `.timeslot-group`, `.timeslot-header`, `.timeslot-toggle`, `.timeslot-now`
    - `tabIndex`
    - `setAttribute/getAttribute` if the implementation uses them
    - `focus()`
    - `scrollIntoView()`
    - `classList.remove/toggle/contains` if introduced by the implementation
  - Update app-import tests to keep asserting descendant `.room-card` counts, not direct-child assumptions.
  - Add at least one assertion per file that the grouped view contract is present after app startup, for example:
    - `rooms-container` contains `.timeslot-group`
    - first group header/toggle exists
    - announcement region text is populated after render/filter change
  - Keep each file focused on its original behavior:
    - `clear-filter-button-spec.mjs` still verifies clear-filter behavior
    - `legend-click-search-spec.mjs` still verifies legend click behavior
- **Rationale**:
  - These two existing specs import `app.js` directly and will be the first regressions to fail if the fake DOM does not understand the new grouped structure.
  - Updating them avoids false negatives and preserves existing behavior coverage.
- **Tests**:
  - Run both files after each `app.js`/renderer integration pass.
- **Commit message**: `test(app): update interaction specs for grouped schedule DOM`

### Step 9: Document the new grouping algorithm and affected files
- **File**: `README.md` (modify)
- **Changes**:
  - Add a short developer-facing subsection under `## For Developers` or `## Notes on Data layout`, for example `### Timeslot grouping implementation notes`.
  - Document:
    - bucket size default (`30` minutes)
    - primary files involved:
      - `js/timeslot.js`
      - `js/renderer.js`
      - `app.js`
      - `js/time-indicator.js`
      - `styles.css`
      - `tests/timeslot-grouping-spec.mjs`
    - the high-level algorithm:
      - filter events → group by rounded-down start time → render non-empty groups → highlight current bucket → auto-scroll on initial load
  - Keep the note short and implementation-focused.
- **Rationale**:
  - The requirements explicitly ask for a short README/notes section explaining the main algorithm and changed files.
- **Tests**:
  - No automated tests required.
  - Reviewer should verify the documentation matches the actual implementation.
- **Commit message**: `docs(timeslots): add implementation notes for grouped schedule view`

## Testing Approach

### Automated
Run tests from a local static server because several existing specs load `index.html`, config files, and committed schedule data via `fetch`.

1. Start a local server from the repo root:
   - Preferred on macOS:
     - `python3 -m http.server 8000`
2. In a second terminal, run the focused new and affected specs first:
   - `SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/timeslot-grouping-spec.mjs`
   - `SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/clear-filter-button-spec.mjs`
   - `SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/legend-click-search-spec.mjs`
3. Then run the full regression suite:
   - `SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/sage-spec-requirements.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/sage-review-followups-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/requirements.spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/name-teams-decoupling-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/scope-filter-all-events-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/date-named-sources-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/clear-filter-button-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/legend-click-search-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/scope-filter-review-followups-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/timeslot-grouping-spec.mjs`

### Manual / browser QA
Use the existing static preview (`index.html`) and validate:
1. Full dataset renders as grouped 30-minute slots.
2. No empty groups are shown after load or after filters change.
3. The first upcoming group is highlighted and auto-scrolled into view on page load when applicable.
4. Mobile viewport: sticky timeslot headers remain visible while scrolling.
5. Desktop viewport: time column remains visually separated from cards column.
6. Keyboard operation: toggle buttons are focusable and `Enter`/`Space` update `aria-expanded` correctly.
7. Announcement region updates after filter changes.
8. Edge cases: events at `:00` and `:30` land in the expected bucket; long events remain in the bucket of their start time.

## Handoff

**Artifact saved**: `artifacts/2026-03-24-timeslot-grouping-plan.md`

**Upstream artifacts**:
- Architecture: `artifacts/2026-03-24-timeslot-grouping-architecture.md`
- Requirements: `artifacts/2026-03-24-timeslot-grouping-requirements.md`

**Context for @ema-implementer**:
- 9 steps to execute
- Files to create:
  - `js/timeslot.js`
  - `tests/timeslot-grouping-spec.mjs`
- Files to modify:
  - `index.html`
  - `js/renderer.js`
  - `js/time-indicator.js`
  - `app.js`
  - `styles.css`
  - `tests/clear-filter-button-spec.mjs`
  - `tests/legend-click-search-spec.mjs`
  - `README.md`
- Test command:
  - Start server: `python3 -m http.server 8000`
  - Focused tests:
    - `SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/timeslot-grouping-spec.mjs`
    - `SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/clear-filter-button-spec.mjs`
    - `SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/legend-click-search-spec.mjs`
  - Full suite:
    - `SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/sage-spec-requirements.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/sage-review-followups-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/requirements.spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/name-teams-decoupling-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/scope-filter-all-events-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/date-named-sources-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/clear-filter-button-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/legend-click-search-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/scope-filter-review-followups-spec.mjs; SAGE_TEST_BASE_URL=http://127.0.0.1:8000/ node tests/timeslot-grouping-spec.mjs`
- Test framework: Node.js ESM specs using `node:assert/strict` + existing fake DOM harnesses + manual browser QA via static preview
- Watch for:
  - Existing `insertIndicator(...)` assumes direct-child `.room-card` nodes; grouped DOM invalidates that assumption.
  - `tests/clear-filter-button-spec.mjs` and `tests/legend-click-search-spec.mjs` import `app.js` and will need fake DOM updates for `scrollIntoView`, `focus`, new selectors, and any new class/attribute operations.
  - Do not overwrite `#statusMessage` warnings with timeslot announcements; use the dedicated live region.
  - Keep the first visible current/upcoming group expanded after every render, even when later groups default to collapsed.
  - Preserve existing legend and clear-filter behavior while moving cards into nested `.timeslot-cards` containers.

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-implementer`

**What @ema-implementer should do**:
1. Read this plan artifact at `artifacts/2026-03-24-timeslot-grouping-plan.md`
2. Read `artifacts/2026-03-24-timeslot-grouping-architecture.md` for design intent only; do not redesign the solution
3. Execute each step atomically — stage changes but do NOT commit — and run the focused tests after each relevant step
4. Re-run the full regression suite before finishing
5. Document any deviations in `artifacts/2026-03-24-timeslot-grouping-implementation.md`

