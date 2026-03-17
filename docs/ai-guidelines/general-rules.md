# General AI Coding Standards

Language-agnostic standards that apply to all AI-assisted development at EMA.

## Code Quality

- Prefer readability over cleverness -- code is read far more often than it is written
- Follow existing project conventions; do not introduce a new style mid-project
- Keep functions focused on a single responsibility
- Apply DRY (Don't Repeat Yourself), but do not over-abstract -- duplication is cheaper than the wrong abstraction
- Avoid deep nesting; prefer early returns and guard clauses
- Use meaningful names for variables, functions, and types

## Security

- Never generate hardcoded credentials, secrets, or tokens
- Never disable security features (SSL verification, authentication checks, CSRF protection)
- Always parameterize database queries -- no string concatenation for SQL
- Sanitize and validate all user inputs
- Follow the principle of least privilege in all generated code

## Reviews

- All AI-generated code requires human review before merge
- The reviewer must understand **what the code does** -- not merely that it compiles or passes tests
- Flag AI-generated or AI-assisted code in pull request descriptions for transparency and audit
- Reviewers should pay special attention to edge cases, error handling, and security implications

## Git Practices

- Write meaningful commit messages that explain the _why_, not just the _what_
- Make atomic commits -- one logical change per commit
- Never commit files that belong in `.gitignore` (build artifacts, secrets, IDE configs)
- Keep branches short-lived and focused

## Dependencies

- Prefer well-maintained libraries with active communities
- Check license compatibility before suggesting or adding new dependencies
- Pin dependency versions for reproducible builds
- Avoid pulling in large frameworks for small tasks

## Documentation

- Explain **why** in comments, not **what** -- the code already says what it does
- Update existing documentation when changing behavior
- Keep README and architectural docs in sync with the codebase
- Document non-obvious design decisions and trade-offs

## AI Usage Metrics

EMA tracks AI-assisted development during the pilot program. At the end of every meaningful AI interaction (code generation, refactoring, test writing, code review, debugging), **automatically write** a metrics entry to the `.metrics/` folder in the project root.

**Automatic metrics recording — do NOT ask the developer to copy-paste:**

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

**Category selection** — choose the category that best describes what the task is primarily about:

| Category | Use when the task is primarily about... |
|----------|----------------------------------------|
| Governance | Compliance, policy enforcement, auditing, security review, code review against standards |
| Architecture | System/code architecture, component structure, integration patterns, ADRs, structural refactoring, module boundaries |
| Functional | Business logic, user-facing features, requirements-driven implementation |
| Technical architecture and design | Technical planning, API design, data modeling, infrastructure design, solution design before implementation |
| Development | Writing/modifying code, localized fixes, small refactoring, dependency changes, config changes |
| Testing | Writing tests, test coverage analysis, test infrastructure, QA validation, regression testing |
| Support | Debugging, troubleshooting, incident response, developer tooling, pipeline routing |

**Rules:**
- Always write metrics at the end of every meaningful piece of work (not for trivial autocomplete or quick Q&A)
- If you are an EMA pipeline agent (ema-implementer, ema-tester, ema-reviewer) with a more specific Metrics Snapshot section in your own agent instructions, use that format instead of this generic template
- Fill `Date` with today's date (ISO 8601: `YYYY-MM-DD`)
- Fill `Category` by selecting the most appropriate category from the table above based on the task context
- Fill `Tool` with the AI tool name (Copilot, Claude Code, Cursor AI, JetBrains AI, Codex, Junie)
- Fill `Task / Use Case` with a specific description of the task including scope and what was requested (e.g., "Add JWT validation middleware with role-based access control for /api/admin endpoints" rather than just "Add middleware")
- Fill `AI Usage Description` with a detailed factual summary of what you did — files created/modified, functions/classes added, tests written, issues found, architectural decisions made
- Fill `Outcome` using one of the standard outcomes with context: "Working code produced — all N steps completed, N files modified, tests passing" or "Partial help — N of M steps completed, blocked on [reason]"
- Fill `Estimated Impact` with a percentage-based time savings estimate — e.g., "Time saved ≈ 40-50% — AI handled codebase exploration and component scaffolding in minutes; developer still reviews correctness, validates edge cases, and adjusts conventions (~1.5h AI-assisted vs ~3h fully manual)". Be honest and specific — overestimating undermines credibility. Consider: what AI genuinely accelerated (exploration, generation, systematic checking) vs what still requires human judgment (correctness validation, business context, edge cases, conventions)
- Leave `Person`, `IDE`, and `Time Spent` as bracket placeholders for the developer to fill in
