GitHub Pages: https://<your-github-username>.github.io/sage

# SAGE — Schedule & Agenda for Group Events

> *SAGE = Schedule & Agenda for Group Events* 

a lightweight webapp that renders a schedule defined in a simple CSV file.

GitHub Pages: https://silemo.github.io/sage

## What is SAGE?
**What:** A small, spreadsheet-friendly webapp that reads a CSV schedule and renders a browsable agenda and simple calendar views for group events (conferences, meetups, classes).

**Why:** Let non-technical users edit schedules in Excel/Sheets and publish a pleasant web view without editing HTML.

**Name** :
*SAGE* — Schedule & Agenda for Group Events.

**Features**
- Editable schedule source: CSV (spreadsheet-friendly).
- Human-readable agenda + optional time-grid/calendar views.
- Static-friendly: can be published to GitHub Pages or run with a tiny server.

## For Developers

### How SAGE Works (conceptual)
- A single CSV file is the source of truth: one row per event.
- The app parses the CSV (client-side or build-time) into event objects with fields such as date, start/end times, title, description, location, presenter, tags, and URL.
- Events are rendered into an agenda view and grouped/filtered by date or tag.
- For static hosting, a build step can convert CSV → JSON/HTML so GitHub Pages can serve the result.

**CSV Format (recommended)**
Use a simple header (case-insensitive):

```
time,location,topics,name,value stream,teams,type
```

Example row:

```csv
08:55 - 9:45,Auditorium N.W.,PI Objectives,Overall PI Plenary,ALL,,Plenary
```

**Project Files (where to look)**
- Frontend renderer: [js/renderer.js](js/renderer.js#L1)
- Look for: `package.json`, `index.html`, `src/`, `public/`, `app.py`, `Dockerfile`, or `.github/workflows` for build/deploy hints.

### Quick Start (local preview)
Update these commands to match the project's stack if different.

**Clone**:

```bash
git clone https://github.com/<your-org-or-username>/sage.git
cd sage
```

If this is a Node.js project (has `package.json`):

```bash
npm install
npm start
```

If the site is static (no build step), preview locally:

```bash
# Python 3
python -m http.server 8000
# or with npm
npx http-server . -p 8000
```

If you'd like, I can detect the project's stack and replace this section with exact commands.

### Contributing

- Open an issue to discuss non-trivial changes.
- Fork the repo and create a feature branch:

```bash
git checkout -b feat/brief-description
```

- Make small, focused commits and push your branch.
- Add or update tests when applicable.
- Submit a Pull Request targeting `main` (or the repository's default branch) with a clear description and links to issues.

## Notes on Data layout

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

