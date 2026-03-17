# GitHub Copilot Configuration Guide

This document covers all GitHub Copilot configuration features available in this scaffolding, including custom instructions, agents, prompt files, skills, and the coding agent environment.

## Custom Instructions

### Global Instructions
- **`.github/copilot-instructions.md`** is always injected into Copilot Chat context, code review, and the coding agent.
- This is the primary way to provide project-wide guidance to Copilot.

### Path-Scoped Instructions
- **`.github/instructions/*.instructions.md`** files provide path-scoped rules using an `applyTo` glob in the frontmatter.
- Frontmatter fields:
  - `applyTo` — required glob pattern determining which files trigger these instructions (e.g., `"**/*.cs"`)
  - `name` — optional display name for the instruction set
  - `description` — optional summary of what the instructions cover
  - `excludeAgent` (optional) — exclude from `"code-review"` or `"coding-agent"`
- To make a rule always-on across all files, use `applyTo: "**"`.
- Code review reads only the first 4,000 characters of each instruction file.

## Custom Agents

- **`.github/agents/*.agent.md`** files define custom agents that can be invoked by name in Copilot Chat.
- Frontmatter fields:
  - `name` — the name used to invoke the agent (e.g., `@my-agent`)
  - `description` — summary of what the agent does
  - `tools` — array of tool names the agent can use, or `["*"]` for all tools
  - `model` (optional) — specify a particular model for the agent
  - `target` (optional) — target environment
- The body contains Markdown instructions (max 30,000 characters).

## Prompt Files

- **`.github/prompts/*.prompt.md`** files define reusable prompts that appear as slash commands in Copilot Chat.
- Frontmatter fields:
  - `description` — shown in the slash command picker
  - `agent` — which agent handles the prompt: `ask`, `edit`, `agent`, or a custom agent name
  - `model` — specify a model for the prompt
  - `tools` — tools available to the prompt
- Variables available in prompt body:
  - `${selection}` — the currently selected text in the editor
  - `${file}` — the currently open file
  - `${input:variableName}` — prompt the user for input at invocation time
- Available in VS Code, Visual Studio, and JetBrains IDEs.

## Agent Skills

- **`.github/skills/<skill-name>/SKILL.md`** files define reusable skills that Copilot loads on demand.
- Frontmatter fields:
  - `name` (required) — skill display name
  - `description` (required) — tells Copilot when to use this skill
  - `license` — license information
  - `user-invocable` — whether users can invoke directly
  - `disable-model-invocation` — prevent automatic invocation by the model
- Skill directories can contain scripts, templates, and examples alongside `SKILL.md`.
- Copilot loads skills on demand based on the prompt and the skill description.

### Adding Custom Skills

To create a new skill for your project:

1. Create a directory: `.github/skills/<your-skill-name>/`
2. Add `SKILL.md` with frontmatter (`name` and `description` are required)
3. Add any supporting files (scripts, templates, examples) in the same directory
4. Copilot will automatically discover and use the skill based on its description

## Coding Agent Environment

**`.github/workflows/copilot-setup-steps.yml`** is a GitHub Actions workflow that runs **before** every Copilot coding agent session to prepare the development environment.

### How It Works

1. When a Copilot coding agent session starts (e.g., from a GitHub issue or PR), GitHub triggers this workflow via `workflow_dispatch`.
2. The workflow runs on an `ubuntu-latest` runner and executes your setup steps.
3. **Only file/artifact changes in the workspace persist** into the agent's session. System-level changes (e.g., `apt-get install`, environment variables set via `export`) do **not** persist.
4. After the workflow completes, the coding agent begins its work with the prepared environment.

### Requirements

- The job **must** be named `copilot-setup-steps`.
- The workflow trigger **must** be `workflow_dispatch`.
- Keep setup fast — long-running steps delay the agent's start.

### What Persists vs. What Doesn't

| Persists | Does NOT Persist |
|----------|-----------------|
| Files created/modified in the workspace | System packages installed via `apt-get` |
| Dependencies installed into workspace (e.g., `node_modules/`, `.venv/`) | Environment variables set via `export` |
| Built artifacts and compiled output | Global tool installations (e.g., `npm install -g`) |
| Configuration files written to the repo | Shell profile changes |

### Customization

The sync-ai-configs script generates a starter template. Once you customize the file, **remove the `# AUTO-GENERATED` first line** and the sync script will preserve your changes on future runs. Editing the workflow without removing that first line is not enough; the next sync will regenerate the file.

### Examples

Below are common setup patterns. Combine the ones relevant to your project.

#### Node.js / TypeScript

```yaml
      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Build project
        run: npm run build
```

#### Python

```yaml
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
```

#### .NET / C\#

```yaml
      - name: Set up .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Restore dependencies
        run: dotnet restore

      - name: Build
        run: dotnet build --no-restore
```

#### Java / Maven

```yaml
      - name: Set up Java
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '21'
          cache: 'maven'

      - name: Build with Maven
        run: mvn -B package --file pom.xml
```

#### Multi-Language Project

```yaml
      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install all dependencies
        run: |
          npm ci
          pip install -r requirements.txt
```

#### Docker Compose (for databases / services)

```yaml
      - name: Start services
        run: docker compose -f docker-compose.dev.yml up -d

      - name: Wait for services
        run: |
          until docker compose -f docker-compose.dev.yml exec -T db pg_isready; do
            sleep 2
          done

      - name: Run migrations
        run: npm run db:migrate
```

### Troubleshooting

- **Agent can't find dependencies**: Ensure you install them into the workspace, not globally.
- **Setup is slow**: Use caching actions (`actions/setup-node` with `cache`, `actions/setup-python` with `cache: 'pip'`) and avoid unnecessary build steps.
- **Agent can't access a service**: Use Docker Compose to start services. The agent runs on the same runner, so `localhost` works.
- **Changes not taking effect after sync**: The sync script only skips this workflow after you remove the `# AUTO-GENERATED` first line. If you edit the workflow but leave that line in place, the next sync will overwrite it.

## Context Injection Summary

| File | When Injected |
|------|--------------|
| `.github/copilot-instructions.md` | Always (Chat, code review, coding agent) |
| `.github/instructions/*.instructions.md` | When editing files matching `applyTo` glob |
| `AGENTS.md` | Coding agent and Codex CLI sessions |
| `.github/agents/*.agent.md` | When agent is invoked by name |
| `.github/prompts/*.prompt.md` | When user invokes via slash command |
| `.github/skills/*/SKILL.md` | On demand (Copilot decides from description) |
