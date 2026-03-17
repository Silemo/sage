---
name: dataverse-metadata-export
description: Export Dataverse table metadata for one or more tables into agent-friendly JSON and Markdown. Use when working with Microsoft Dataverse or Dynamics 365 tables and you need reliable field names, labels, data types, choice or option set values, lookup targets, or one-to-many, many-to-one, or many-to-many relationships before writing OData queries, SQL/TDS queries, mappings, validation logic, integrations, or feature code.
---

# Dataverse Metadata Export

Use this skill to ground an agent in real Dataverse metadata before it writes code that depends on table shape.

## Workflow

1. Identify the Dataverse environment URL and the logical table names needed for the task.
2. Obtain a bearer token using the team's normal auth flow.
3. Put the token in an environment variable such as `DATAVERSE_ACCESS_TOKEN`.
4. Run the exporter script for the relevant tables only.
5. Read the generated Markdown first for quick orientation.
6. Read the generated JSON when exact property names or option values matter.

Do not guess Dataverse logical names, choice values, or relationship navigation names when the exporter can confirm them.

## Script

Run the bundled exporter:

```bash
python docs/ai-guidelines/skills/dataverse-metadata-export/scripts/export_dataverse_metadata.py \
  --environment-url https://your-org.crm4.dynamics.com \
  --table account \
  --table contact \
  --output-dir artifacts/dataverse-metadata
```

The script expects a bearer token in `DATAVERSE_ACCESS_TOKEN` by default. Override with `--token-env VAR_NAME` if needed.

Important flags:

- `--table` can be repeated and also accepts comma-separated table names.
- `--table-file` reads additional table logical names from a text file.
- `--label-language` sets the LCID used when choosing labels. Default is `1033`.
- `--output-dir` controls where JSON and Markdown files are written.

## Output

The exporter writes:

- `index.json` and `index.md` with a run summary
- `<table>.json` with normalized metadata for automation
- `<table>.md` with an LLM-friendly summary

Read [output-format.md](docs/ai-guidelines/skills/dataverse-metadata-export/references/output-format.md) when you need the exact JSON shape.
Read [usage-notes.md](docs/ai-guidelines/skills/dataverse-metadata-export/references/usage-notes.md) when you need guidance for OData or SQL/TDS work.

## Agent Guidance

- Prefer exporting only the tables relevant to the current feature so the context stays small.
- Use the table-level Markdown when planning.
- Use the JSON when generating exact OData filters, `$select` lists, SQL projections, lookup handling, or choice-value mappings.
- For lookup columns, use `targets` plus the relationship sections to understand both the foreign key attribute and the navigation names.
- For choice fields, use exported integer values rather than display labels in code.
- If the script cannot run because auth is unavailable, ask for the environment URL and the preferred token acquisition path instead of inventing schema details.
