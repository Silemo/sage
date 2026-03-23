# SAGE

## Data layout

Schedule data is committed to the repository and loaded directly by the static site.

- JSON fallback files live in `data/json/`
- Preferred CSV files live in `data/csv/`
- Logical source names are declared in `config/sources.json`
- For each source, the app tries `data/csv/{name}.csv` first and falls back to `data/json/{name}.json`
- The interface does not support file uploads; schedule updates are shipped through repository changes and releases