# GitHub Copilot Custom Agents

Thirteen specialized agents forming a chained development workflow. Each agent has a model selected to maximize efficacy while minimizing premium request consumption.

## Workflow

```
Backlog track: @ema-backlog-manager  (pre-development, outputs to ADO — standalone)
Full path:     @ema-brainstormer → @ema-architect → @ema-planner → @ema-implementer → @ema-tester → @ema-reviewer
Complex path:  @ema-architect → @ema-planner → @ema-implementer → @ema-tester → @ema-reviewer
Quick path:    @ema-planner-lite → @ema-implementer-lite → @ema-tester → @ema-reviewer
Debug path:    @ema-debugger → @ema-tester → @ema-reviewer
Review only:   @ema-reviewer
Security path: @ema-security
Metrics cleanup: @ema-metrics-consolidator
```

Invoke the first agent in the path you need directly. `@ema-starter` (free dispatcher) is available if you're unsure which path fits — it classifies and routes automatically, but costs one extra call.

Agents are connected via `handoffs:` frontmatter (VS Code / IDE feature). Each produces structured markdown output consumed by the next agent.

## Agents

### `ema-backlog-manager` — SAFe Backlog Manager

| Property | Value |
|----------|-------|
| **Model** | `GPT-5.4` (1x) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'editFiles', 'azure-devops/*']` |
| **Guidelines** | None (product management, not development) |
| **Handoffs** | None (terminal — outputs to Azure DevOps) |

Pre-development product management agent. Transforms high-level ideas into SAFe-structured Azure DevOps backlogs (Epics → Features → User Stories → Tasks). Supports four modes: generate a new backlog from an idea, refine an existing backlog JSON file, push a staged backlog to ADO, and review an existing ADO work item with improvement proposals. Requires `backlog.config.json` (gitignored) for org, project, area path, and iteration path. Schema: `templates/safe-backlog-schema.json`.

---

### `ema-starter` — Smart Dispatcher

| Property | Value |
|----------|-------|
| **Model** | `GPT-5 mini` (free) |
| **Tools** | `[]` (conversation only) |
| **Guidelines** | None (routing only) |
| **Handoffs** | → `@ema-backlog-manager`, → `@ema-brainstormer`, → `@ema-architect`, → `@ema-planner-lite`, → `@ema-debugger`, → `@ema-reviewer`, → `@ema-security`, → `@ema-metrics-consolidator` |

Optional dispatcher that classifies requests by clarity and complexity, then routes to the correct pipeline path. Useful for new users who aren't yet familiar with the agents — but experienced users should invoke the target agent directly to save a call.

### `ema-brainstormer` — Requirements Brainstorming

| Property | Value |
|----------|-------|
| **Model** | `GPT-5 mini` (free) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'fileSearch', 'textSearch']` |
| **Guidelines** | Security only |
| **Handoffs** | → `@ema-architect`, → `@ema-planner-lite` |

Explores the codebase thoroughly, then works through requirements via genuine conversation — proposes approaches with trade-offs, challenges overcomplicated scope, flags risks, and pushes back when there's a simpler way. Confirms the summary with the user before producing the document. Cheap model (GPT-5 mini) means more turns are fine.

### `ema-architect` — Software Architecture Design

| Property | Value |
|----------|-------|
| **Model** | `Claude Opus 4.6` (3x) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'usages', 'fileSearch', 'textSearch']` |
| **Handoffs** | → `@ema-planner` |

Explores the codebase, presents 2-3 design approaches with trade-offs, asks the user for preferences within the turn, produces an architecture design document.

### `ema-planner` — Implementation Planning

| Property | Value |
|----------|-------|
| **Model** | `GPT-5.4` (1x) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'usages', 'fileSearch', 'textSearch']` |
| **Handoffs** | → `@ema-implementer` |

Produces a detailed, self-contained implementation plan from an architecture design. Each step includes exact file paths, function signatures, and change descriptions.

### `ema-planner-lite` — Quick Planning

| Property | Value |
|----------|-------|
| **Model** | `Gemini 3 Flash` (0.33x) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'usages', 'fileSearch', 'textSearch']` |
| **Handoffs** | → `@ema-implementer-lite` |

Lightweight variant for simple changes — bug fixes, small features, config changes. Skips deep architectural analysis. Uses Gemini 3 Flash as primary to minimize cost on routine work (~80% of tasks). Hands off to `@ema-implementer-lite` (not the full implementer).

### `ema-implementer-lite` — Lightweight Code Implementation

| Property | Value |
|----------|-------|
| **Model** | `Gemini 3 Flash` (0.33x) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand']` |
| **Handoffs** | → `@ema-tester` |

Lightweight implementer for the quick path. Executes short plans (1-5 steps) from `@ema-planner-lite` — bug fixes, config changes, small features. Uses Gemini 3 Flash as primary since the detailed plan provides enough specificity for a lighter model. Escalates to `@ema-implementer` if the work turns out more complex than expected.

### `ema-implementer` — Code Implementation

| Property | Value |
|----------|-------|
| **Model** | `GPT-5.4` (1x) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand']` |
| **Handoffs** | → `@ema-tester` |

Executes the plan step-by-step. Follows the plan strictly, runs tests after each change, and stages changes for the user to commit. Used for complex plans from `@ema-planner` that require stronger reasoning.

### `ema-tester` — Test Specialist

| Property | Value |
|----------|-------|
| **Model** | `GPT-5.4` (1x) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand']` |
| **Handoffs** | → `@ema-reviewer` |

Tests against the REQUIREMENTS and DESIGN, not the implementation. Catches what implementer's tests miss due to confirmation bias. Does not fix bugs — reports them.

### `ema-reviewer` — Code Review

| Property | Value |
|----------|-------|
| **Model** | `Claude Sonnet 4.6` (1x) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'changes', 'usages', 'problems', 'fileSearch', 'textSearch']` |
| **Handoffs** | → `@ema-security` (optional deep dive), → `@ema-metrics-consolidator` (optional, when 5+ metrics rows) |

Reviews code against EMA guidelines and the original plan. Reports only genuine issues with specific fix suggestions.

### `ema-debugger` — Systematic Debugging

| Property | Value |
|----------|-------|
| **Model** | `GPT-5.4` (1x) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand']` |
| **Handoffs** | → `@ema-tester`, → `@ema-reviewer` |

Systematic debugging: reproduce → isolate → root-cause → fix → verify. Prevents shotgun debugging by requiring understanding before fixing.

### `ema-security` — Security Vulnerability Analyst

| Property | Value |
|----------|-------|
| **Model** | `GPT-5.4` (1x) |
| **Tools** | `['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand']` |
| **Handoffs** | None (terminal — report only) |

Multi-phase security analysis: reconnaissance → dependency CVE scan (CLI tools) → code pattern analysis → infrastructure review. Produces a severity-rated vulnerability report with OWASP/CWE references and specific remediation guidance.

### `ema-metrics-consolidator` — Metrics Consolidation

| Property | Value |
|----------|-------|
| **Model** | `Gemini 3 Flash` (0.33x) |
| **Tools** | `['read', 'edit', 'search', 'fileSearch', 'textSearch']` |
| **Guidelines** | None (no code interaction) |
| **Handoffs** | None (terminal agent) |

Standalone utility that consolidates accumulated `.metrics/` rows by grouping semantically related entries within the same category into fewer, richer rows. Can also be invoked from `@ema-reviewer` when metrics accumulate (5+ rows).

## Behavioral Principles

All non-brainstormer, non-dispatcher agents follow these to maximize value per premium request. `ema-brainstormer` is intentionally excluded from the strict run-to-completion principle because it works through genuine multi-turn conversation — exploring the codebase, proposing approaches, and iterating with the user before producing the requirements document. Since it uses a free model, more turns are encouraged.

1. **Run to completion** — do not stop mid-task; stopping wastes the premium request
2. **Be autonomous** — make reasonable decisions independently; prefer action over asking
3. **Clarify within the turn** — ask questions only within the same turn (no new premium request); never force a new prompt
4. **Structured handoff** — produce well-defined output so the next agent starts immediately

## Model Diversity Rationale

The pipeline intentionally uses **different model families** for implementation and review. Models from the same family tend to share blind spots — a model reviewing code generated by its own family is less likely to catch certain patterns than a model from a different family.

The pipeline now uses three model families: GPT (planning, testing, debugging, heavy implementation), Gemini (lightweight planning and implementation), and Claude (review). The quick path (`planner-lite → implementer-lite`) uses Gemini for execution while Claude reviews the output — maximizing cross-family diversity where it matters most.

Apply this principle when creating your own agents: if you have a code-writing agent and a code-review agent, consider assigning them to different model families.

## Cost Analysis

| Workflow | Premium Cost | Cycles per 300/month |
|----------|-------------|---------------------|
| Full path (Opus architect) | 7x | ~43 |
| Full path (GPT-5.4 throughout) | 4x | ~75 |
| Quick path (planner-lite → implementer-lite → tester → reviewer) | 2.66x | ~113 |
| Quick path (all Gemini/free models) | ~0.99x | ~300 |
| Debug path | 1x-2x | ~150-300 |
| Security audit | 1x | ~300 |
| Minimal (known plan, Gemini implementer-lite) | 1.33x | ~225 |
| Metrics cleanup | 0.33x | ~900 |

`@ema-starter` is free (GPT-5 mini), adding zero premium cost — but it still consumes one call. Skip it when you know which path you need.

Use `@ema-planner-lite` for routine work (~80% of tasks) — the quick path now costs 2.66x per cycle (down from 3.33x) thanks to Gemini 3 Flash on planner-lite and implementer-lite. Reserve `@ema-architect` + `@ema-planner` + `@ema-implementer` for complex architectural changes.

## Authoring

Agent-specific instructions are hand-authored in `docs/ai-guidelines/agents/<name>.md`. The sync scripts (`scripts/sync-ai-configs.ps1` / `.sh`) combine these with shared EMA guidelines and generate the final `.github/agents/<name>.agent.md` files.

| Source | Generated |
|--------|-----------|
| `docs/ai-guidelines/agents/ema-starter.md` | `.github/agents/ema-starter.agent.md` |
| `docs/ai-guidelines/agents/ema-backlog-manager.md` | `.github/agents/ema-backlog-manager.agent.md` |
| `docs/ai-guidelines/agents/ema-brainstormer.md` | `.github/agents/ema-brainstormer.agent.md` |
| `docs/ai-guidelines/agents/ema-architect.md` | `.github/agents/ema-architect.agent.md` |
| `docs/ai-guidelines/agents/ema-planner.md` | `.github/agents/ema-planner.agent.md` |
| `docs/ai-guidelines/agents/ema-planner-lite.md` | `.github/agents/ema-planner-lite.agent.md` |
| `docs/ai-guidelines/agents/ema-implementer.md` | `.github/agents/ema-implementer.agent.md` |
| `docs/ai-guidelines/agents/ema-implementer-lite.md` | `.github/agents/ema-implementer-lite.agent.md` |
| `docs/ai-guidelines/agents/ema-tester.md` | `.github/agents/ema-tester.agent.md` |
| `docs/ai-guidelines/agents/ema-reviewer.md` | `.github/agents/ema-reviewer.agent.md` |
| `docs/ai-guidelines/agents/ema-debugger.md` | `.github/agents/ema-debugger.agent.md` |
| `docs/ai-guidelines/agents/ema-security.md` | `.github/agents/ema-security.agent.md` |
| `docs/ai-guidelines/agents/ema-metrics-consolidator.md` | `.github/agents/ema-metrics-consolidator.agent.md` |

Brainstormer gets security guidelines only (conversation agent, no code context). All others get the full EMA guidelines (general rules + security + testing).

## Platform Compatibility

| Feature | VS Code | Visual Studio | JetBrains |
|---------|---------|--------------|-----------|
| `@name` invocation | Yes | Yes (v18.4+) | Yes (Copilot plugin) |
| `model:` frontmatter | Yes | Yes | **Not supported** — [tracking issue](https://github.com/microsoft/copilot-intellij-feedback/issues/1461). Select model manually; agents include model hints in handoff output. |
| `handoffs:` | Yes | Yes | Verify per version |
| `tools:` filtering | Yes | Yes | Verify per version |

Unknown tool names are silently ignored per platform.

### JetBrains: automatic model selection does not work

JetBrains IDEs currently ignore the `model:` frontmatter in agent definitions. Every agent invocation uses whichever model is selected in the IDE's Copilot settings — there is no per-agent model override. This means:

- The cost table above does not apply as-is — all calls use the same model tier regardless of which agent you invoke.
- **Skipping unnecessary agents matters more on JetBrains.** Since every call costs the same (whatever your IDE model is set to), each extra agent in the chain is a wasted call at full price. Invoke the target agent directly rather than routing through `@ema-starter` or other intermediaries you don't need.
