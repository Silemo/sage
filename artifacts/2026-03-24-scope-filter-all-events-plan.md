## Summary
Modify the Scope filter so shared activities tagged with `vs === "ALL"` are treated as part of the global scope in two places: the `Plenary` scope option should show all `ALL` value-stream events, and each `All [VS]` scope option should include both the selected value stream and the shared `ALL` events. Based on the current codebase, this is a limited change centered on filter semantics in [js/filter.js](c:/Users/manfredig/IdeaProjects/sage/js/filter.js) with targeted regression updates in [tests/requirements.spec.mjs](c:/Users/manfredig/IdeaProjects/sage/tests/requirements.spec.mjs) and [tests/name-teams-decoupling-spec.mjs](c:/Users/manfredig/IdeaProjects/sage/tests/name-teams-decoupling-spec.mjs).

## Steps

### Step 1: Broaden global-scope matching from “global plenary” to “shared ALL event” semantics
- **File**: `js/filter.js` (modify)
- **Changes**:
	- Introduce a helper such as `isAllValueStreamEvent(event)` that returns `event.vs === "ALL"`.
	- Keep `isGlobalPlenary(event)` unchanged if other call sites still need to distinguish actual plenary-type events, but stop using it as the sole inclusion rule for scope modes that are meant to include all shared activities.
	- Update `filterEvents(events, filterState)` so the scope branches behave as follows:
		- `mode === "plenary"`: return every event on the selected date whose `vs === "ALL"`, regardless of `type`. This must include items like `Overall PI Plenary`, `Coffee break`, and `Lunch`.
		- `mode === "vs"`: return every event on the selected date where `event.vs === "ALL" || event.vs === filterState.value`.
		- `mode === "team"`: leave current team behavior intact, meaning it should still include shared `ALL` events and teamless cards. Prefer switching the shared-event clause from `isGlobalPlenary(event)` to the new `isAllValueStreamEvent(event)` helper so the behavior is consistent across all scope modes.
	- Preserve date scoping, search filtering, and event sorting exactly as they work now.
	- Do not change hierarchy building or scope option generation in this step; the current dropdown construction in [app.js](c:/Users/manfredig/IdeaProjects/sage/app.js) already emits `Plenary` plus `All [VS]` options, and the requested change is behavioral rather than structural.
- **Rationale**: The current implementation incorrectly equates the `Plenary` scope with `type === "Plenary"`, even though shared schedule items are modeled by `vs === "ALL"`. The root fix is to use the value-stream field as the source of truth for shared scope membership.
- **Tests**:
	- Add unit-style assertions proving that `filterEvents()` with `mode: "plenary"` returns all shared `ALL` events, not just the actual plenary-type ones.
	- Add assertions proving that `filterEvents()` with `mode: "vs", value: "PLM"` returns `ALL` items plus `PLM` items, and excludes unrelated streams like `MON`.
	- Add one regression assertion proving search still applies after the broader scope match, for example by filtering `mode: "plenary"` with a search term that only matches `Lunch`.
- **Commit message**: `fix(filter): include shared ALL events in scope filters`

### Step 2: Rewrite the focused requirements regression to encode the new Scope filter contract
- **File**: `tests/requirements.spec.mjs` (modify)
- **Changes**:
	- Replace or rename the existing test `testRendererIgnoresTypeWhilePlenaryFilterStillUsesType()` so it reflects the new contract instead of preserving the old one.
	- Update the expectations for the current two-event fixture (`Overall PI Plenary` and `Coffee break`) so `mode: "plenary"` returns both events rather than only the plenary-type item.
	- Extend that same fixture or add a nearby test case to include a value-stream event such as `VS PLM Plenary`, then assert that `mode: "vs", value: "PLM"` returns:
		- shared `ALL` items like `Overall PI Plenary` and `Coffee break`
		- the `PLM` event(s)
		- no unrelated stream events
	- Keep the renderer/color assertions untouched except where the test name or setup no longer matches the new behavior.
- **Rationale**: [tests/requirements.spec.mjs](c:/Users/manfredig/IdeaProjects/sage/tests/requirements.spec.mjs) currently locks in the exact behavior you want changed. That test must be updated first-class, otherwise implementation will look like a regression even when it is correct.
- **Tests**:
	- Run `node tests/requirements.spec.mjs` and confirm the renamed/updated scope-filter assertions pass.
	- Verify the updated suite still covers the existing color behavior for shared `ALL` events.
- **Commit message**: `test(requirements): update scope filter expectations for ALL events`

### Step 3: Add committed-data regression coverage for real CSV schedule behavior
- **File**: `tests/name-teams-decoupling-spec.mjs` (modify)
- **Changes**:
	- Add a focused test using `loadAllSources(config/sources.json)` against the committed data and assert that, for `date: "2026-03-17"`:
		- `mode: "plenary"` includes `Overall PI Plenary`, `Coffee break`, and `Lunch`
		- `mode: "vs", value: "MON"` includes `Coffee break` and `Lunch` in addition to `MON` events such as `VS MON Plenary` or `Alpha`
		- unrelated value-stream events like `VS PLM Plenary` are excluded from the `MON` scope result unless they are `vs === "ALL"`
	- Keep the existing team-filter tests unchanged except for any helper reuse needed to avoid duplicated filtering setup.
- **Rationale**: The in-memory requirement fixture catches the logic change, but the committed CSV regression guards against drifting data assumptions and verifies the exact user-visible examples mentioned in the request.
- **Tests**:
	- Run `node tests/name-teams-decoupling-spec.mjs` after the new assertions are added.
	- Confirm the test uses committed data only and does not mutate fixtures.
- **Commit message**: `test(filter): cover ALL events in committed scope results`

## Testing Approach
Run the smallest relevant regression set first, then the broader suites if the implementer wants extra confidence.

1. Primary verification:
	 - `node tests/requirements.spec.mjs`
	 - `node tests/name-teams-decoupling-spec.mjs`
2. Optional broader smoke run if changes in [js/filter.js](c:/Users/manfredig/IdeaProjects/sage/js/filter.js) unexpectedly affect other schedule flows:
	 - `node tests/date-named-sources-spec.mjs`
	 - `node tests/sage-review-followups-spec.mjs`
3. Manual browser verification:
	 - Open the schedule for `2026-03-17`.
	 - Select `Plenary` in Scope and confirm `Overall PI Plenary`, `Coffee break`, and `Lunch` are shown.
	 - Select `All MON` and confirm shared `ALL` events remain visible alongside `MON` items.

## Handoff

**Artifact saved**: `artifacts/2026-03-24-scope-filter-all-events-plan.md`

**Upstream artifacts**:
- Requirements: none (user request in conversation)
- Architecture: none required for this limited change

**Context for @ema-implementer**:
- 3 steps to execute
- Files to create: none
- Files to modify: `js/filter.js`, `tests/requirements.spec.mjs`, `tests/name-teams-decoupling-spec.mjs`
- Files to keep unchanged unless implementation reveals an unexpected dependency: `app.js`, `js/renderer.js`, `js/loader.js`, `config/sources.json`, committed CSV data files
- Test command: `node tests/requirements.spec.mjs && node tests/name-teams-decoupling-spec.mjs`
- Test framework: custom Node assertion scripts using `node:assert/strict`
- Watch for:
	- `team` mode should keep its existing inclusion of shared/teamless events
	- search filtering must still apply after broadening the scope predicate
	- the current helper name `isGlobalPlenary` may become semantically misleading if reused too broadly; avoid silently changing its contract unless all tests and call sites are updated deliberately

> 📋 **Model**: Select **GPT-5.4** before invoking `@ema-implementer`

**Recommendation on path**:
This is limited enough for the lightweight implementation path. If `@ema-implementer-lite` is available in your environment, use it; otherwise `@ema-implementer` can execute this plan directly.

**What the implementer should do**:
1. Read this plan artifact at the path above.
2. Implement Step 1 in [js/filter.js](c:/Users/manfredig/IdeaProjects/sage/js/filter.js) without widening the change beyond scope filtering.
3. Update the targeted regression suites in [tests/requirements.spec.mjs](c:/Users/manfredig/IdeaProjects/sage/tests/requirements.spec.mjs) and [tests/name-teams-decoupling-spec.mjs](c:/Users/manfredig/IdeaProjects/sage/tests/name-teams-decoupling-spec.mjs).
4. Run the primary tests, then note any deviations in an implementation summary artifact.
