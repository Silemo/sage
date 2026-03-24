## Plan
1. Update `app.js` `updateView` call to `renderTimeslotGroups` by setting `expandedCount: Infinity`, ensuring `renderTimeslotGroups` always considers a bucket expanded by default. Only this callsite needs the change.
2. Run the project's test suite (e.g., `npm test`) or the relevant timeslot spec runner to ensure no regressions; document any failures.

