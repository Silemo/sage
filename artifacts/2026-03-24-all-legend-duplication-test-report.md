## Test Summary
- **Test goal**: verify whether `getEventColor()` gives `ALL` a distinct color from `_default`, and determine why the UI currently shows two visible `ALL` legend tags
- **Result**: `ALL` does use a distinct color; the duplicate visible `ALL` labels are caused by legend bucketing and labeling logic, not by the color map fallback
- **Code changes made**: none

## Runtime Check Performed
A direct Node.js runtime check was executed against the live code in [js/renderer.js](c:/Users/manfredig/IdeaProjects/sage/js/renderer.js) and the current color configuration in [config/colors.json](c:/Users/manfredig/IdeaProjects/sage/config/colors.json).

### Command
```bash
node --input-type=module -e "import { getEventColor } from './js/renderer.js'; import colorMap from './config/colors.json' with { type: 'json' }; const allPlenary = { name: 'Overall PI Plenary', vs: 'ALL', type: 'Plenary' }; const allNonPlenary = { name: 'Some ALL Event', vs: 'ALL', type: 'Session' }; const unrelated = { name: 'Unknown', vs: 'UNKNOWN', type: 'Session' }; const plenaryColor = getEventColor(allPlenary, colorMap); const nonPlenaryColor = getEventColor(allNonPlenary, colorMap); const defaultColor = getEventColor(unrelated, colorMap); console.log(JSON.stringify({ plenaryColor, nonPlenaryColor, defaultColor, plenaryDiffers: JSON.stringify(plenaryColor) !== JSON.stringify(defaultColor), nonPlenaryDiffers: JSON.stringify(nonPlenaryColor) !== JSON.stringify(defaultColor) }, null, 2));"
```

### Output
```json
{
  "plenaryColor": {
    "bg": "#ECEFF1",
    "border": "#455A64"
  },
  "nonPlenaryColor": {
    "bg": "#ECEFF1",
    "border": "#455A64"
  },
  "defaultColor": {
    "bg": "#FFFFFF",
    "border": "#9E9E9E"
  },
  "plenaryDiffers": true,
  "nonPlenaryDiffers": true
}
```

## Findings

### 1. `ALL` does not fall back to the default color
The current implementation in [js/renderer.js](c:/Users/manfredig/IdeaProjects/sage/js/renderer.js) behaves as follows:

- `getEventColor(event, colorMap)` returns `colorMap.ALL ?? colorMap._default` for global plenaries
- otherwise it returns `colorMap[event.vs] ?? colorMap._default`

Since [config/colors.json](c:/Users/manfredig/IdeaProjects/sage/config/colors.json) defines both `ALL` and `_default`, and they are different, `ALL` events correctly receive a non-default color.

### 2. The duplicate `ALL` labels come from two distinct internal buckets
The legend logic in [js/renderer.js](c:/Users/manfredig/IdeaProjects/sage/js/renderer.js) maps events into legend buckets like this:

- global plenaries become `_plenary`
- all other events keep `event.vs`

Then the legend label is rendered like this:

- `_plenary` is displayed as `ALL`
- literal `ALL` is also displayed as `ALL`

This creates two visible legend entries with the same label whenever the event set contains both:

- a global plenary event that is normalized into `_plenary`
- a non-plenary event whose `vs` is literally `ALL`

### 3. The current data contains both cases
The data search confirmed that the repository currently ships both types of events:

- global plenary examples with `vs: "ALL"` and `type: "Plenary"` in:
  - [data/csv/2026-03-17.csv](c:/Users/manfredig/IdeaProjects/sage/data/csv/2026-03-17.csv)
  - [data/csv/2026-03-18.csv](c:/Users/manfredig/IdeaProjects/sage/data/csv/2026-03-18.csv)
- non-plenary shared events that also use `vs: "ALL"`, such as Coffee, Lunch, and Drinks, in:
  - [data/csv/2026-03-17.csv](c:/Users/manfredig/IdeaProjects/sage/data/csv/2026-03-17.csv)
  - [data/csv/2026-03-18.csv](c:/Users/manfredig/IdeaProjects/sage/data/csv/2026-03-18.csv)

## Root Cause
The visible duplication is caused by an architectural mismatch between:

- the **data model**, which currently uses `vs: "ALL"` for at least two different semantics:
  - global plenary sessions
  - non-plenary shared activities such as breaks and lunch
- the **presentation model**, which introduces a separate internal `_plenary` bucket for legend rendering but still labels that bucket as `ALL`

That means the UI is effectively exposing two categories with the same display name:

- `_plenary` shown as `ALL`
- `ALL` shown as `ALL`

## Architectural Implication For `@ema-architect`
This is not primarily a color issue. It is a categorization and display-contract issue. The next architecture change should decide which semantic model the UI should expose.

## Recommended Design Decision Areas
`@ema-architect` should evaluate one of these approaches:

### Approach A: Merge `_plenary` and `ALL` into a single displayed legend category
- Treat all events with global scope as one legend concept
- Keep one visible `ALL` label only
- Likely simplest UX
- Risk: collapses a meaningful distinction if plenaries should remain visually distinct from shared breaks/lunch

### Approach B: Keep separate internal categories but give them distinct visible labels
- Example: `_plenary` displays as `Global Plenary`
- literal `ALL` displays as `Shared / All Streams`
- Preserves semantics
- Risk: adds another user-facing term that may need product approval

### Approach C: Change the source data contract so non-plenary shared events no longer use `vs: "ALL"`
- Example: introduce a dedicated shared/common classification for breaks, lunch, drinks
- Makes the data model clearer and reduces special-case UI logic
- Risk: broadest change because it affects data files, normalization rules, and backward compatibility

## Recommendation
Start with **Approach B** in architecture unless product explicitly wants a single collapsed `ALL` category.

Reasoning:
- It preserves the current underlying semantics
- It explains the UI truthfully instead of hiding it
- It avoids data migration as a first step
- It gives a clean migration path later if the team decides to normalize the data contract more aggressively

## Suggested Handoff For `@ema-architect`
- Investigate the legend/display contract around `_plenary` versus literal `ALL`
- Define whether the UI should expose one global category or two distinct categories
- If two categories remain, assign distinct user-facing labels and color semantics
- If one category is preferred, define the merge rule centrally so `getEventColor()` and `renderLegend()` use the same conceptual bucket
- Review whether the data contract should continue using `vs: "ALL"` for non-plenary shared activities
