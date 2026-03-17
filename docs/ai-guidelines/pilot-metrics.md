# AI Pilot Program & Usage Metrics

EMA tracks AI-assisted development as part of an ongoing pilot program. Consistent metrics collection helps the organisation measure impact, refine tool selection, and justify continued investment.

## Pilot Program Goals

1. **Measure productivity impact** — quantify time saved and code quality changes.
2. **Identify high-value use cases** — discover where AI tools help most (scaffolding, testing, code review, debugging, documentation).
3. **Surface risks** — catch patterns of low-quality output, security near-misses, or over-reliance before they become problems.
4. **Inform tool selection** — compare tools across dimensions (quality, speed, cost, developer satisfaction).
5. **Build institutional knowledge** — create a shared evidence base for best practices with AI tools.

## What to Track

Track every **meaningful AI interaction** — one that produces a tangible work artifact or materially changes your approach. Examples:

| Track | Don't Track |
|-------|-------------|
| Code generation (new feature, module, component) | Single-line autocomplete suggestions |
| Test generation or test scaffolding | Trivial formatting suggestions |
| Code review assistance | Quick "what does this function do?" questions |
| Refactoring with AI guidance | IDE-level rename/extract refactors |
| Debugging with AI assistance | Reading AI-generated documentation |
| Architecture or design discussions that produce artifacts | Casual brainstorming with no output |

## Metrics Template

At the end of every qualifying interaction, **automatically write** a metrics entry to the `.metrics/` folder in the project root. Do NOT print metrics for copy-paste — write them directly to files.

### Automatic Recording Steps

1. Create the `.metrics/` directory if it does not exist.
2. **CSV** — append a row to `.metrics/ai-usage-log.csv`. If the file does not exist, create it with the header row first:
   ```
   Date,Category,Person,Tool,IDE,Task / Use Case,AI Usage Description,Outcome,Time Spent,Estimated Impact
   ```
   Then append your data row. Wrap any field containing commas in double quotes.
3. **Markdown** — append a table row to `.metrics/ai-usage-log.md`. If the file does not exist, create it with this header:
   ```markdown
   # AI Usage Log

   | Date | Category | Person | Tool | IDE | Task / Use Case | AI Usage Description | Outcome | Time Spent | Estimated Impact |
   |------|----------|--------|------|-----|-----------------|---------------------|---------|------------|------------------|
   ```
   Then append your data row.

### Field Descriptions

| Field | Who Fills It | Description |
|-------|-------------|-------------|
| **Date** | AI tool | Today's date (ISO 8601: `YYYY-MM-DD`) |
| **Category** | AI tool | The area this task falls under — one of: Governance, Architecture, Functional, Technical architecture and design, Development, Testing, Support |
| **Person** | Developer | Your name |
| **Tool** | AI tool | The AI tool used: `Copilot`, `Claude Code`, `Cursor AI`, `JetBrains AI`, `Codex`, `Junie` |
| **IDE** | Developer | Your IDE (e.g., VS Code, IntelliJ IDEA, Visual Studio, JetBrains Rider) |
| **Task / Use Case** | AI tool | Brief but specific description of the task — include scope and what was requested (e.g., "Add JWT validation middleware with role-based access for /api/admin endpoints" rather than just "Add middleware") |
| **AI Usage Description** | AI tool | Factual summary: files changed, tests written, issues found |
| **Outcome** | AI tool | One of the standard outcomes with context (see below) |
| **Time Spent** | Developer | Total session duration (e.g., "45 min", "2h") |
| **Estimated Impact** | AI tool (pipeline agents) / Developer (manual entries) | Percentage-based time savings estimate showing what AI accelerated vs what still requires human effort. EMA pipeline agents fill this automatically; for manual entries, estimate yourself (e.g., "Time saved ≈ 40-50% — AI handled exploration and scaffolding; developer still reviews correctness and edge cases (~1.5h AI-assisted vs ~3h fully manual)") |

### Category Selection Guide

| Category | Use when the task is primarily about... |
|----------|----------------------------------------|
| Governance | Compliance, policy enforcement, auditing, security review, code review against standards |
| Architecture | System/code architecture, component structure, integration patterns, ADRs, structural refactoring, module boundaries |
| Functional | Business logic, user-facing features, requirements-driven implementation |
| Technical architecture and design | Technical planning, API design, data modeling, infrastructure design, solution design before implementation |
| Development | Writing/modifying code, localized fixes, small refactoring, dependency changes, config changes |
| Testing | Writing tests, test coverage analysis, test infrastructure, QA validation, regression testing |
| Support | Debugging, troubleshooting, incident response, developer tooling, pipeline routing |

### Standard Outcomes

| Outcome | When to Use |
|---------|------------|
| **Working code produced** | AI output was used directly or with minor edits |
| **Significant acceleration** | AI output needed substantial editing but saved meaningful time |
| **Partial help** | AI helped with some aspects but required significant manual work |
| **Learning aid** | AI output wasn't used directly but helped understanding |
| **Unhelpful** | AI output was not useful for the task |
| **Rejected** | AI output was incorrect, insecure, or otherwise unsuitable |

## Rules for AI Tools

- Always write metrics to `.metrics/` at the end of every meaningful piece of work
- Do **not** write metrics for trivial autocomplete or quick Q&A
- If you are an EMA pipeline agent (ema-implementer, ema-tester, ema-reviewer) with a more specific Metrics Snapshot section in your own agent instructions, use that format instead of this generic template
- Fill `Date`, `Category`, `Tool`, `Task / Use Case`, `AI Usage Description`, and `Outcome` automatically
- Resolve `Person` by running `git config user.name` in the terminal — use the result if non-empty, otherwise leave `[Person]`
- Resolve `IDE` from runtime context (VS Code → `VS Code`; `.idea/` present → appropriate JetBrains IDE name; otherwise leave `[IDE]`)
- Fill `Estimated Impact` with a percentage-based time savings estimate — e.g., "Time saved ≈ 40-50% — AI handled exploration and scaffolding; developer still reviews correctness and edge cases (~1.5h AI-assisted vs ~3h fully manual)". Be honest and specific — overestimating undermines credibility
- Leave `Time Spent` as a bracket placeholder for the developer

## Reviewing Metrics

1. The AI tool writes metrics directly to `.metrics/ai-usage-log.csv` and `.metrics/ai-usage-log.md`, including an AI-generated percentage-based time savings estimate in the `Estimated Impact` column.
2. The developer fills in `Time Spent`, reviews `Person` and `IDE` (auto-resolved by the AI tool — correct if wrong), and reviews the AI-generated `Estimated Impact` — adjust if your experience suggests a different percentage or reasoning.
3. Commit the updated files with your normal workflow — no separate PR required.

## Aggregation and Review

- Metrics are reviewed **monthly** during the pilot program.
- Aggregated dashboards (if available) pull from `.metrics/ai-usage-log.csv` across repositories.
- Individual entries are **not** used for performance evaluation — they inform tool and process decisions only.
- The pilot program coordinator publishes a monthly summary to the team.

## Examples of Good Metric Entries

```csv
Date,Category,Person,Tool,IDE,Task / Use Case,AI Usage Description,Outcome,Time Spent,Estimated Impact
2026-01-15,Development,Jane Doe,Copilot,VS Code,Add JWT validation middleware with token verification and role-based access for /api/admin endpoints,"Generated auth middleware with token verification and role checks. Created middleware.ts with JwtValidation class, modified auth.ts to register middleware, updated routes.ts to apply to 5 admin endpoints",Working code produced — 3 files modified and all unit tests passing,30 min,Time saved ≈ 50-60% — AI generated middleware structure and route wiring; developer still reviewed auth logic and tested token validation (~30m AI-assisted vs ~1.5h fully manual)
2026-01-16,Testing,John Smith,Claude Code,VS Code,Write integration tests for user CRUD API covering success paths and edge cases,"Generated 12 test cases: 4 CRUD happy-path tests, 3 null/empty input tests, 2 duplicate email tests, 2 auth boundary tests, 1 pagination test. Found missing validation on email field — flagged in test report",Significant acceleration — 12 tests written with 2 critical edge cases discovered,1h,Time saved ≈ 50-60% — AI generated 12 test cases with setup and discovered edge cases; developer still validated assertions and verified coverage (~1h AI-assisted vs ~3h fully manual)
2026-01-17,Architecture,Alex Kim,Cursor AI,VS Code,Refactor Terraform modules for multi-region deployment with shared state backend,"Restructured 4 modules (vpc, compute, storage, dns) with variable extraction for region parameterization. Created shared backend config. Suggested but did not implement state migration — flagged for manual review",Partial help — module restructuring complete but state migration requires manual intervention,2h,Time saved ≈ 30-40% — AI restructured 4 modules and extracted variables; developer still validated infrastructure decisions and state migration requires manual work (~2h AI-assisted vs ~3h fully manual)
```

## Privacy

- Metrics do **not** contain code, prompts, or AI responses — only metadata about the interaction.
- Names are included for team-level coordination during the pilot; they will be anonymised in any published reports.
- Metrics files should not be sent to AI tools (`.metrics/` is included in the AI ignore patterns by default).
