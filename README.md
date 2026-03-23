# SAGE

## Data layout

Schedule data is committed to the repository and loaded directly by the static site.

- JSON fallback files live in `data/json/`
- Preferred CSV files live in `data/csv/`
- Logical source labels are declared in `config/sources.json`
- For each configured source, the app uses its `defaultDate` as the file stem: `data/csv/{date}.csv` first, then `data/json/{date}.json`
- `config/sources.json` controls which date files are loaded, so `data/json/` may contain additional unreferenced date files
- The interface does not support file uploads; schedule updates are shipped through repository changes and releases