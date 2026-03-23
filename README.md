# SAGE

## Data layout

Schedule data is committed to the repository and loaded directly by the static site.

- JSON fallback files live in `data/json/`
- Preferred CSV files live in `data/csv/`
- Logical source labels are declared in `config/sources.json`
- For each configured source, the app uses its `defaultDate` as the file stem: `data/csv/{date}.csv` first, then `data/json/{date}.json`
- CSV sources may define `name`, `value stream`, and `teams`; `name` is displayed on cards and `teams` is used only for filtering
- Existing JSON sources still use the legacy `team` + `vs` shape and are normalized at load time for backward compatibility
- Team-filtered views include activities tagged with the selected team plus activities with no assigned teams
- `config/sources.json` controls which date files are loaded, so `data/json/` may contain additional unreferenced date files
- The interface does not support file uploads; schedule updates are shipped through repository changes and releases