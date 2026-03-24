## Goal
Establish a clear time hierarchy and timeslot grouping so users can quickly see what comes next on both mobile and desktop. Use 30-minute buckets, hide empty slots by default, and design for moderate lists (up to ~200 items) with accessible, responsive UI patterns.

## Codebase Context
- The app is a static site that loads schedule data from `data/csv/` and `data/json/` per `config/sources.json` (see `README.md`).
- Rendering and interaction logic likely live in `app.js`, `script.js`, and/or `js/` — these are the primary places to add grouping logic and rendering changes.
- Styles are in `styles.css`; responsive breakpoints and layout changes should be added there.
- No runtime server: changes must operate at client-side load time; schedule updates are delivered through repository changes.
- Existing artifacts and docs in `artifacts/` show prior UI work and patterns for documenting architecture / implementation.
- Testing uses the static site (manual + unit tests are appropriate); aim for a small number of deterministic unit tests around grouping logic.

## Scope
Included
- Compute 30-minute timeslot buckets from the loaded event list (client-side).
- Render timeslot groups with a prominent timeslot header (e.g., "09:00 — 09:30") and event cards under each group.
- Hide buckets that contain zero visible events (respecting current filters).
- Responsive layouts:
  - Desktop: two-column layout with a narrow time column (time labels) and a cards column (events).
  - Mobile: stacked single-column layout, with sticky timeslot headers during scroll.
- Auto-scroll on page load to the first upcoming timeslot ("Now") if any events are in the future.
- Minimal collapse behavior: keep the first N upcoming groups expanded (default N = 4), allow user to expand/collapse other groups via a small toggle in the header.
- Accessibility: focusable controls, ARIA roles for group headings and toggles, and an ARIA live region or announcement on filter changes that affect visible groups.
- Performance: handle moderate lists without virtualization; grouping code should be O(n) + sort, and DOM updates batched (update per group).
- Documentation: add a short README/notes showing which files to change and the main algorithm.

Excluded (Out of Scope)
- Full vertical timeline layout with duration-proportional heights (complex redesign).
- Server-side changes or new endpoints (static site only).
- Persistent user preferences (e.g., saved collapse state) or a subscription system.
- Virtualization for very large datasets (>200 items) — assume moderate lists as requested.

## Constraints
- Must operate client-side with the existing static data model and loading flow.
- Must not add heavy new dependencies; prefer pure JS + CSS.
- Must be responsive: work well on narrow mobile viewports and wide desktops.
- Do not block rendering: updates must not delay page load; perform grouping and rendering after data load with minimal reflow.
- Keep changes small and reviewable (one or two file changes for JS and CSS, plus small template updates).

## Approach
Chosen approach: Timeslot grouping with sticky headers (Approach A).
Why: Balances scanability, implementation effort, and mobile friendliness. Provides an immediate sense of "what's next" while remaining straightforward to implement with existing client-side logic.

Implementation strategy (high level)
1. Add an event grouping function that:
   - Normalizes event start times to the configured timezone used by the app.
   - Rounds start time down to the nearest 30-minute bucket (00 or 30 minutes).
   - Uses a map keyed by bucket timestamp; each bucket's events are sorted by start time.
2. Decide visible groups:
   - Filter buckets to those with at least one visible event after applying current filters (teams, sources).
   - Determine current time bucket and auto-scroll to the first bucket that starts >= now.
3. Render:
   - For each visible bucket produce a `timeslot-group` element with:
     - `timeslot-header` (text label, count of events, collapse/expand control).
     - `timeslot-cards` container for event cards.
   - Desktop: Render a left column `time-column` showing sticky labels aligned with groups; right column shows cards.
   - Mobile: Single-column stack; `timeslot-header` is `position: sticky` so header remains visible when its group is scrolled.
4. Collapse rules:
   - Expand up to N upcoming buckets (default N = 4).
   - Later buckets start collapsed; toggles are available to expand per-bucket or “expand all”.
5. Accessibility:
   - Mark `timeslot-header` as heading (e.g., `role="heading"`, `aria-level="3"`) and provide a `button` for collapse toggles with `aria-expanded`.
   - Expose the initial scroll target via focus (move keyboard focus to the first upcoming group after scroll) and announce via ARIA live region: "Showing events from 09:00 — 09:30, 3 items".
6. Performance:
   - Keep grouping and sorting fast (single pass to populate buckets, then sort each bucket).
   - Batch DOM insertion (create fragments per group then append).
7. Tests:
   - Unit tests for grouping function: ensure correct assignment to 30-minute buckets, correct sorting, and handling of events exactly on bucket boundaries.
   - Integration/manual tests: filtering should hide empty groups; auto-scroll target is correct.

## Success Criteria
- Visual and functional:
  - Page renders grouped timeslots in 30-minute buckets.
  - Empty timeslots are hidden after loading and after filters are applied.
  - On page load the view auto-scrolls to the first upcoming timeslot when applicable.
  - Desktop shows a clear two-column layout; mobile shows sticky headers while scrolling.
  - Collapse/expand controls work and are keyboard operable.
- Accessibility:
  - Timeslot headers are exposed to assistive tech as headings; collapse toggle has correct ARIA attributes.
  - ARIA live region updates when the visible timeslot changes due to filters or initial auto-scroll.
- Performance:
  - Page responsiveness remains acceptable with up to ~200 events; no blocking long tasks during initial render.
- Tests:
  - Unit tests for grouping/sorting pass.
  - One manual QA checklist (see below) completed.

Manual QA checklist (example)
- Load page with full dataset → No empty time buckets shown; first upcoming bucket visible and focused.
- Toggle a filter that hides some events → Any group that becomes empty hides automatically.
- On mobile, scroll within a group → timeslot header remains visible (sticky).
- Keyboard navigation: tab to a collapse toggle and press Enter / Space → group expands/collapses; ARIA state updates.
- Edge cases: events starting exactly at :00 or :30 are placed in the correct bucket; events spanning buckets remain shown in the start-time bucket.

## Risks and Considerations
- Timezone normalization: schedules may be in a specific timezone; ensure bucket rounding happens within the correct timezone context to avoid off-by-hour errors.
- Sticky headers: CSS `position: sticky` behavior varies only by parent overflow; ensure containers do not inadvertently disable sticky positioning.
- Auto-scroll: jumping the viewport can be jarring. Provide smooth scroll, and ensure keyboard focus moves appropriately for screen-reader users.
- Filtering + collapse: ensure filters do not leave the user with an unexpected collapsed result (e.g., first visible upcoming group collapsed). Keep the first visible upcoming group always expanded.
- Large datasets: if the dataset grows beyond moderate sizes, consider virtualization later.

## Open Questions
- None remain — the requested defaults were explicit (30-minute buckets, hide empty buckets, moderate lists). If you want a different default for N (expanded groups), we used N = 4; changeable later.

## Handoff

**Artifact saved**: `artifacts/2026-03-24-timeslot-grouping-requirements.md`  
(Absolute path in your workspace: /Users/nickelsilver/WebstormProjects/sage/artifacts/2026-03-24-timeslot-grouping-requirements.md)

**Complexity signal**: simple → use @ema-planner-lite

> 📋 Model: Select **Gemini 3 Flash** before invoking `@ema-planner-lite`

Context for next agent / implementer
- Goal: Add client-side 30-minute timeslot grouping with sticky headers, hide empty buckets by default, auto-scroll to first upcoming bucket.
- Approach: Add `groupEventsByBucket(30min)`, filter empty buckets, render groups, sticky headers on mobile, time column on desktop, collapse defaults (first 4 expanded).
- Key constraints: client-side only, no heavy dependencies, must work with existing static data loading.
- Success criteria: grouped UI, hidden empty buckets, auto-scroll target, keyboard/ARIA for collapse, acceptable perf up to ~200 events.
- Risks: timezone normalization, sticky positioning issues, and large datasets.

What the next agent should do
- Read this requirements doc at `/Users/nickelsilver/WebstormProjects/sage/artifacts/2026-03-24-timeslot-grouping-requirements.md`.
- Inspect `app.js`, `script.js`, `js/*`, and `styles.css` to find the current rendering pipeline and card markup.
- Implement the grouping function and rendering changes in one JS file and add small CSS for `.timeslot-group`, `.timeslot-header`, `.time-column`, and `.cards-column`.
- Add unit tests for the grouping function and one integration/manual QA run.
