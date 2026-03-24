# Architecture: Exact-start grouping for irregular event times

## Summary

The current schedule groups events into synthetic 30-minute buckets. That mislabels events with irregular start times such as `08:55 - 09:45` under headers like `08:30 – 09:00`. The preferred fix is to keep the existing grouped card layout, but group by each event's exact start time and derive the group label from the real event range.

## Options considered

1. **Exact-start grouping (recommended)**
   - Keep the existing grouped card UI
   - Use the event's normalized `start` as the group key
   - Build each group label from the real `start`/`end` values in that group
   - Minimal code and test impact

2. **Calendar/timeline view**
   - Would show durations proportionally
   - Rejected because the data mixes 15-minute breaks with multi-hour sessions, which would produce poor density and mobile ergonomics

3. **Hybrid grouped view plus duration decoration**
   - Possible later, but not required to solve the incorrect labeling bug

## Chosen design

- Modify `js/timeslot.js` so `getBucketKey()` returns the exact normalized time instead of flooring to a 30-minute boundary
- Update `formatBucketLabel()` to accept a real start and end time
- Update `groupEventsByTimeslot()` to compute `bucketLabel` from the actual grouped events
- Remove the now-unused `30` argument from `app.js`
- Update `tests/timeslot-grouping-spec.mjs` to assert exact-start behavior

## Files affected

- `js/timeslot.js`
- `app.js`
- `tests/timeslot-grouping-spec.mjs`

## Handoff

**Artifact saved**: `artifacts/2026-03-24-exact-start-grouping-architecture.md`

**Path signal**: localized change, suitable for `@ema-planner-lite`

**Context for @ema-planner-lite**:
- Preferred solution: exact-start grouping, not a calendar/timeline view
- Files to modify: `js/timeslot.js`, `app.js`, `tests/timeslot-grouping-spec.mjs`
- Test command: `node tests/timeslot-grouping-spec.mjs`
- Watch for: `findCurrentBucketIndex()` should continue to work with exact `HH:MM` keys; renderer shape must stay unchanged
