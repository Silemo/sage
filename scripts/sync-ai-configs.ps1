#!/usr/bin/env pwsh
# sync-ai-configs.ps1 -- Generate AI tool configs from canonical docs in docs/ai-guidelines/
# Flags: --all, --reconfigure, --ide=IDE, --new-project, --wiki-only (wiki Reference pages only), --clean [--yes/-y]

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Determine repo root (parent of scripts/)
# ---------------------------------------------------------------------------
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
} else {
    $RepoRoot = (Get-Location).Path
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$GuidelinesDir = Join-Path (Join-Path $RepoRoot "docs") "ai-guidelines"

if (-not (Test-Path $GuidelinesDir) -and -not ($args -contains "--clean")) {
    Write-Error "Guidelines directory not found: $GuidelinesDir"
    exit 1
}

# ---------------------------------------------------------------------------
# Language-to-glob mapping
# ---------------------------------------------------------------------------
$Languages = [ordered]@{
    "bash"                    = @{ Globs = @("**/*.sh");                                                              Description = "Bash / Shell" }
    "csharp"                  = @{ Globs = @("**/*.cs", "**/*.csx");                                                  Description = "C#" }
    "java"                    = @{ Globs = @("**/*.java");                                                            Description = "Java" }
    "javascript-typescript"   = @{ Globs = @("**/*.js", "**/*.jsx", "**/*.ts", "**/*.tsx", "**/*.mjs", "**/*.cjs");   Description = "JavaScript / TypeScript" }
    "powershell"              = @{ Globs = @("**/*.ps1", "**/*.psm1", "**/*.psd1");                                   Description = "PowerShell" }
    "python"                  = @{ Globs = @("**/*.py");                                                              Description = "Python" }
}

# ---------------------------------------------------------------------------
# Custom agent definitions: name -> frontmatter config
# Agent-specific instructions live in docs/ai-guidelines/agents/<name>.md
# and are combined with shared guidelines by this script.
# ---------------------------------------------------------------------------
$CustomAgents = [ordered]@{
    "ema-starter" = @{
        Description      = "Smart dispatcher -- classifies your request and routes to the right agent pipeline"
        Model            = "'GPT-5 mini'"
        ToolsVSCode      = "[]"
        ToolsJetBrains   = "[]"
        ToolsVisualStudio = "[]"
        Agents           = "['ema-backlog-manager', 'ema-brainstormer', 'ema-architect', 'ema-planner-lite', 'ema-debugger', 'ema-reviewer', 'ema-security', 'ema-metrics-consolidator']"
        GuidelinesScope  = "none"
        IncludePipelineOverview = $true
        ArgumentHint     = "Describe your request (a vague idea, a feature to build, a bug to fix, or code to review)"
        Handoffs         = @(
            @{ Label = "Backlog"; Agent = "ema-backlog-manager"; Prompt = "Here is the idea. Search the project wiki for relevant context, decompose it into a SAFe hierarchy (Epics, Features, User Stories/Enablers, Tasks), save the backlog to backlog/<YYYY-MM-DD>-<slug>.json, print a summary table, and ask whether to refine further or push to ADO." }
            @{ Label = "Brainstorm"; Agent = "ema-brainstormer"; Prompt = "Here is my idea. Explore the codebase to understand existing patterns and constraints, then work through requirements with me via conversation -- propose approaches, challenge assumptions, and flag risks. Confirm the summary with me before producing the final requirements document saved to artifacts/<YYYY-MM-DD>-<topic>-requirements.md with a Handoff section for the next agent." }
            @{ Label = "Architect"; Agent = "ema-architect"; Prompt = "Here is the request. Explore the codebase, evaluate 2-3 design approaches, produce an architecture design document saved to artifacts/<YYYY-MM-DD>-<topic>-architecture.md, and include a Handoff section for @ema-planner." }
            @{ Label = "Quick plan"; Agent = "ema-planner-lite"; Prompt = "Here is the request. Read the affected files, produce a concise implementation plan saved to artifacts/<YYYY-MM-DD>-<topic>-plan.md, and include a Handoff section for @ema-implementer-lite." }
            @{ Label = "Debug"; Agent = "ema-debugger"; Prompt = "Here is the bug report. Run the full reproduce → isolate → root-cause → fix → verify cycle, save the debug report to artifacts/<YYYY-MM-DD>-<topic>-debug-report.md, and include a Handoff section for @ema-tester." }
            @{ Label = "Review"; Agent = "ema-reviewer"; Prompt = "Review the changed code against EMA guidelines. Read the plan and implementation artifacts from artifacts/ if they exist. Save the review report to artifacts/<YYYY-MM-DD>-<topic>-review-report.md and include a Pipeline Recap section." }
            @{ Label = "Security Audit"; Agent = "ema-security"; Prompt = "Run a comprehensive security audit. Complete all four phases (reconnaissance, dependency CVE scan, code pattern analysis, infrastructure review). Save the security report to artifacts/<YYYY-MM-DD>-<topic>-security-report.md." }
            @{ Label = "Consolidate Metrics"; Agent = "ema-metrics-consolidator"; Prompt = "Consolidate the .metrics/ usage log. Read all rows, group related entries by category and task similarity, and produce fewer, richer rows." }
        )
    }
    "ema-backlog-manager" = @{
        Description      = "SAFe backlog expert -- generate, refine, and publish structured Azure DevOps backlogs from natural language ideas"
        Model            = "'GPT-5.4'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "[]"
        GuidelinesScope  = "none"
        IncludePipelineOverview = $false
        ArgumentHint     = "Describe your idea, provide a backlog/*.json file to refine, or provide an ADO work item ID/URL to review"
        Handoffs         = @()
    }
    "ema-brainstormer" = @{
        Description      = "Explore codebase, brainstorm with the user, then produce structured requirements"
        Model            = "'GPT-5 mini'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "['ema-architect', 'ema-planner-lite']"
        GuidelinesScope  = "security"
        IncludePipelineOverview = $false
        ArgumentHint     = "Describe your idea or the problem you want to solve"
        Handoffs         = @(
            @{ Label = "Architect"; Agent = "ema-architect"; Prompt = "Read the Handoff section above for the requirements artifact path and context. Explore the codebase using the requirements as your guide, evaluate 2-3 design approaches, produce an architecture design document saved to artifacts/<YYYY-MM-DD>-<topic>-architecture.md, and include a Handoff section for @ema-planner." }
            @{ Label = "Plan (quick)"; Agent = "ema-planner-lite"; Prompt = "Read the Handoff section above for the requirements artifact path and context. Read the affected files, produce a concise implementation plan saved to artifacts/<YYYY-MM-DD>-<topic>-plan.md, and include a Handoff section for @ema-implementer-lite." }
        )
    }
    "ema-architect" = @{
        Description      = "Explore the codebase, evaluate design options, and produce an architecture design document"
        Model            = "'Claude Opus 4.6'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "['ema-planner']"
        GuidelinesScope  = "full"
        IncludePipelineOverview = $true
        ArgumentHint     = "Describe the feature to design, or provide the requirements path (e.g. artifacts/YYYY-MM-DD-topic-requirements.md)"
        Handoffs         = @(
            @{ Label = "Plan"; Agent = "ema-planner"; Prompt = "Read the Handoff section above for the architecture artifact path, upstream artifact paths, and key context (chosen approach, files to create/modify, integration points). Verify those files exist in the codebase, then produce a detailed step-by-step plan saved to artifacts/<YYYY-MM-DD>-<topic>-plan.md, and include a Handoff section for @ema-implementer." }
        )
    }
    "ema-planner" = @{
        Description      = "Produce a detailed step-by-step implementation plan from an architecture design"
        Model            = "'GPT-5.4'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "['ema-implementer']"
        GuidelinesScope  = "full"
        IncludePipelineOverview = $true
        ArgumentHint     = "Provide the architecture document path (e.g. artifacts/YYYY-MM-DD-topic-architecture.md)"
        Handoffs         = @(
            @{ Label = "Implement"; Agent = "ema-implementer"; Prompt = "Read the Handoff section above for the plan artifact path, all upstream artifacts (architecture, requirements), step count, files to create/modify, test command, and any watch-for notes. Execute all plan steps (test after each, stage changes but do NOT commit -- leave committing to the user), save the implementation summary to artifacts/<YYYY-MM-DD>-<topic>-implementation.md, and include a Handoff section for @ema-tester." }
        )
    }
    "ema-planner-lite" = @{
        Description      = "Quick planning for simple changes -- bug fixes, small features, config changes"
        Model            = "'Gemini 3 Flash'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "['ema-implementer-lite']"
        GuidelinesScope  = "full"
        IncludePipelineOverview = $true
        ArgumentHint     = "Describe the change to plan (bug fix, small feature, config change) or provide the requirements path"
        Handoffs         = @(
            @{ Label = "Implement"; Agent = "ema-implementer-lite"; Prompt = "Read the Handoff section above for the plan artifact path, files affected, test command, and watch-for notes. Execute all steps (test after each, stage changes but do NOT commit -- leave committing to the user), save the implementation summary to artifacts/<YYYY-MM-DD>-<topic>-implementation.md, and include a Handoff section for @ema-tester." }
        )
    }
    "ema-implementer-lite" = @{
        Description      = "Lightweight implementation for simple changes -- executes short plans from planner-lite"
        Model            = "'Gemini 3 Flash'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "['ema-tester']"
        GuidelinesScope  = "full"
        IncludePipelineOverview = $true
        ArgumentHint     = "Provide the plan document path (e.g. artifacts/YYYY-MM-DD-topic-plan.md)"
        Handoffs         = @(
            @{ Label = "Test"; Agent = "ema-tester"; Prompt = "Read the Handoff section above for the implementation artifact path, all upstream artifacts (plan, requirements), files changed, current test results, and areas needing extra coverage. Test from the SPEC (requirements), not from the code. Write additional tests, run the full suite, save the test report to artifacts/<YYYY-MM-DD>-<topic>-test-report.md, and include a Handoff section for @ema-reviewer." }
        )
    }
    "ema-implementer" = @{
        Description      = "Execute an implementation plan step-by-step -- writing code, running tests, staging changes"
        Model            = "'GPT-5.4'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "['ema-tester']"
        GuidelinesScope  = "full"
        IncludePipelineOverview = $true
        ArgumentHint     = "Provide the plan document path (e.g. artifacts/YYYY-MM-DD-topic-plan.md)"
        Handoffs         = @(
            @{ Label = "Test"; Agent = "ema-tester"; Prompt = "Read the Handoff section above for the implementation artifact path, all upstream artifacts (plan, architecture, requirements), files changed, current test results, and areas needing extra coverage. Test from the SPEC (requirements), not from the code. Write additional tests, run the full suite, save the test report to artifacts/<YYYY-MM-DD>-<topic>-test-report.md, and include a Handoff section for @ema-reviewer." }
        )
    }
    "ema-tester" = @{
        Description      = "Write tests from the spec, run the full test suite, verify coverage and quality"
        Model            = "'GPT-5.4'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "['ema-reviewer']"
        GuidelinesScope  = "full"
        IncludePipelineOverview = $true
        ArgumentHint     = "Provide the implementation summary path (e.g. artifacts/YYYY-MM-DD-topic-implementation.md), or describe what was implemented"
        Handoffs         = @(
            @{ Label = "Review"; Agent = "ema-reviewer"; Prompt = "Read the Handoff section above for the test report artifact path, all upstream artifacts (implementation, plan, architecture, requirements), suite results, bugs found, and coverage gaps. Read the plan and architecture (if exists) to understand what was supposed to be built and why. Review ALL changed files against EMA guidelines. Save the review report to artifacts/<YYYY-MM-DD>-<topic>-review-report.md and include a Pipeline Recap section." }
        )
    }
    "ema-reviewer" = @{
        Description      = "Review code against EMA guidelines, check security, quality, testing, and plan adherence"
        Model            = "'Claude Sonnet 4.6'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "['ema-security', 'ema-metrics-consolidator']"
        GuidelinesScope  = "full"
        IncludePipelineOverview = $true
        ArgumentHint     = "Provide a PR number, specific file paths, or the plan document path (e.g. artifacts/YYYY-MM-DD-topic-plan.md)"
        Handoffs         = @(
            @{ Label = "Security Audit"; Agent = "ema-security"; Prompt = "Run a comprehensive security audit on the files reviewed above. Complete all four phases (reconnaissance, dependency CVE scan, code pattern analysis, infrastructure review). Save the security report to artifacts/<YYYY-MM-DD>-<topic>-security-report.md." }
            @{ Label = "Consolidate Metrics"; Agent = "ema-metrics-consolidator"; Prompt = "Consolidate the .metrics/ usage log. Read all rows, group related entries by category and task similarity, and produce fewer, richer rows. Write the consolidated result back to both .metrics/ai-usage-log.csv and .metrics/ai-usage-log.md." }
        )
    }
    "ema-metrics-consolidator" = @{
        Description      = "Consolidate .metrics/ usage log -- group related entries into fewer, richer rows"
        Model            = "'Gemini 3 Flash'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "[]"
        GuidelinesScope  = "none"
        IncludePipelineOverview = $false
        ArgumentHint     = "Consolidate the .metrics/ usage log -- group related entries by category and task similarity"
        Handoffs         = @()
    }
    "ema-debugger" = @{
        Description      = "Systematically debug issues -- reproduce, isolate, root-cause, fix, and verify"
        Model            = "'GPT-5.4'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "['ema-tester', 'ema-reviewer']"
        GuidelinesScope  = "full"
        IncludePipelineOverview = $true
        ArgumentHint     = "Describe the bug, paste the error message or stack trace, or describe the unexpected behavior"
        Handoffs         = @(
            @{ Label = "Test"; Agent = "ema-tester"; Prompt = "Read the Handoff section above for the debug report artifact path, bug description, root cause, files changed, and areas to test for regressions. Confirm the reproduction test passes, write edge case and regression tests, run the full suite, save the test report to artifacts/<YYYY-MM-DD>-<topic>-test-report.md, and include a Handoff section for @ema-reviewer." }
            @{ Label = "Review"; Agent = "ema-reviewer"; Prompt = "Read the Handoff section above for the debug report artifact path, bug description, root cause, and files changed. Read the debug report artifact for full context. Review the fix against EMA guidelines (security, code quality, test coverage). Save the review report to artifacts/<YYYY-MM-DD>-<topic>-review-report.md and include a Pipeline Recap section." }
        )
    }
    "ema-security" = @{
        Description      = "In-depth security vulnerability analysis -- dependencies, code patterns, infrastructure"
        Model            = "'GPT-5.4'"
        ToolsVSCode      = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        ToolsJetBrains   = "['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
        ToolsVisualStudio = "['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
        Agents           = "[]"
        GuidelinesScope  = "full"
        IncludePipelineOverview = $true
        ArgumentHint     = "Describe what to audit, or provide file paths / a PR number"
        Handoffs         = @()
    }
}

# ---------------------------------------------------------------------------
# Header inserted at the top of every generated file
# ---------------------------------------------------------------------------
$GeneratedHeader = @"
<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->
<!-- Edit the source files in docs/ai-guidelines/ instead.    -->
"@

# ---------------------------------------------------------------------------
# Selection: which tools, languages, and Copilot extras to generate
# ---------------------------------------------------------------------------

$ConfigFile = Join-Path $RepoRoot ".sync-ai-configs"

$ToolIds     = @("claude",      "copilot",          "codex",                               "cursor", "jetbrains",             "junie")
$ToolLabels  = @("Claude Code", "GitHub Copilot",   "OpenAI Codex / Copilot Coding Agent", "Cursor", "JetBrains AI Assistant", "Junie")
$LangIds     = @("csharp", "java",  "python", "powershell", "javascript-typescript",   "bash")
$LangLabels  = @("C#",     "Java",  "Python", "PowerShell", "JavaScript / TypeScript", "Bash / Shell")
$ExtraIds    = @("agents",                  "prompts",                                          "skill",                     "dataverse-skill")
$ExtraLabels = @("Custom agent pipeline",   "Prompt files (review-guidelines, generate-tests)", "Agent skill (ema-standards)", "Dataverse metadata export skill")

$SelectedTools  = @()
$SelectedLangs  = @()
$SelectedExtras = @()
$CopilotAgentIde = "vscode"

function Has-Tool($id)  { $script:SelectedTools  -contains $id }
function Has-Lang($id)  { $script:SelectedLangs  -contains $id }
function Has-Extra($id) { $script:SelectedExtras -contains $id }

function Invoke-SelectFromMenu {
    param([string[]]$Ids, [string[]]$Labels)
    Write-Host "  Enter numbers separated by commas, or 'all', or press Enter to skip:"
    for ($i = 0; $i -lt $Labels.Count; $i++) {
        Write-Host ("    {0}) {1}" -f ($i + 1), $Labels[$i])
    }
    $raw = Read-Host "  >"
    if ($raw -eq "all") { return ,$Ids }
    $selected = @()
    foreach ($part in ($raw -split ',')) {
        $part = $part.Trim()
        if ($part -match '^\d+$') {
            $idx = [int]$part - 1
            if ($idx -ge 0 -and $idx -lt $Ids.Count) { $selected += $Ids[$idx] }
        }
    }
    # The comma operator prevents PowerShell from unrolling the array through the pipeline.
    # Without it, return @() delivers $null to the caller; return ,$selected with one element
    # delivers a bare string. Both cases need the comma.
    if ($selected.Count -eq 0) { return ,@() }
    return ,$selected   # comma forces array return when single element
}

function Save-Config {
    $lines = @(
        "# sync-ai-configs selection -- commit this file to share with your team.",
        "# Delete it (or run sync-ai-configs --reconfigure) to change selections.",
        "tools=$($script:SelectedTools -join ',')",
        "languages=$($script:SelectedLangs -join ',')",
        "copilot_extras=$($script:SelectedExtras -join ',')",
        "copilot_agent_ide=$($script:CopilotAgentIde)"
    )
    [System.IO.File]::WriteAllLines($ConfigFile, $lines)
    Write-Host "[sync-ai-configs] Config saved to $(Split-Path $ConfigFile -Leaf) -- commit it to share with your team."
}

function Load-Config {
    if (-not (Test-Path $ConfigFile)) { return $false }
    # Backward-compat: older configs used spaces instead of commas and may
    # contain old extra IDs (skill-ema-standards -> skill, skill-dv-export -> dataverse-skill).
    Get-Content $ConfigFile | ForEach-Object {
        if ($_ -match '^#' -or $_ -notmatch '=') { return }
        $key, $val = $_ -split '=', 2
        $key = $key.Trim()
        $val = if ($val) { $val.Trim() } else { "" }
        # Accept both comma-separated and space-separated values
        $sep = if ($val -match ',') { ',' } else { '\s+' }
        $items = if ($val) { $val -split $sep | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { @() }
        switch ($key) {
            'tools'          { $script:SelectedTools  = $items }
            'languages'      { $script:SelectedLangs  = $items }
            'copilot_extras' {
                # Migrate old extra IDs to current names
                $script:SelectedExtras = $items | ForEach-Object {
                    switch ($_) {
                        'skill-ema-standards' { 'skill' }
                        'skill-dv-export'     { 'dataverse-skill' }
                        default               { $_ }
                    }
                }
            }
            'copilot_agent_ide' { $script:CopilotAgentIde = if ($val) { $val } else { "vscode" } }
        }
    }
    return $true
}

function Invoke-Configure {
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host "  sync-ai-configs: Select what to generate"                          -ForegroundColor Cyan
    Write-Host "  Config saved to .sync-ai-configs -- commit it to share with team." -ForegroundColor Cyan
    Write-Host "  To reconfigure: delete .sync-ai-configs or pass --reconfigure"    -ForegroundColor Cyan
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Which AI tools does your team use?" -ForegroundColor Yellow
    $script:SelectedTools = Invoke-SelectFromMenu $ToolIds $ToolLabels
    Write-Host ""
    Write-Host "  Which languages does this project use?" -ForegroundColor Yellow
    $script:SelectedLangs = Invoke-SelectFromMenu $LangIds $LangLabels
    if ((Has-Tool "copilot") -or (Has-Tool "codex") -or (Has-Tool "cursor") -or (Has-Tool "jetbrains") -or (Has-Tool "junie")) {
        Write-Host ""
        Write-Host "  Extras to generate? (agents/prompts are Copilot-only; skills apply to all tools)" -ForegroundColor Yellow
        $script:SelectedExtras = Invoke-SelectFromMenu $ExtraIds $ExtraLabels
    }
    if ((Has-Tool "copilot") -and (Has-Extra "agents")) {
        Write-Host ""
        Write-Host "  Which IDE will your team use with GitHub Copilot agents?" -ForegroundColor Yellow
        Write-Host "    1) VS Code"
        Write-Host "    2) JetBrains (IntelliJ, PyCharm, Rider, WebStorm)"
        Write-Host "    3) Visual Studio (Windows) -- requires VS 2026 17.14+ preview"
        $ideAnswer = Read-Host "  > [1]"
        $script:CopilotAgentIde = switch ($ideAnswer) {
            "2" { "jetbrains" }
            "3" { "visualstudio" }
            default { "vscode" }
        }
        Write-Host "  Copilot agent IDE set to: $($script:CopilotAgentIde)"
    }
    Write-Host ""
    $newProjAnswer = Read-Host "  Is this a new project (cloned from the template)? [y/N]"
    if ($newProjAnswer -eq "y" -or $newProjAnswer -eq "Y") {
        $script:NewProject = $true
    } else {
        $script:NewProject = $false
    }
    Write-Host ""
    Save-Config
}

# Track generated files for the summary
$GeneratedFiles = [System.Collections.Generic.List[string]]::new()
$KeptFiles      = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# --clean: delete all known auto-generated outputs with confirmation
# ---------------------------------------------------------------------------
function Test-AutoGenerated {
    param([string]$FilePath)
    # Read the first 5 lines and check for the marker
    $head = Get-Content -Path $FilePath -TotalCount 5 -ErrorAction SilentlyContinue
    if ($null -eq $head) { return $false }
    return ($head -join "`n") -match "AUTO-GENERATED"
}

function Invoke-Clean {
    # Known output files (individual paths)
    $KnownFiles = @(
        "CLAUDE.md",
        ".claudeignore",
        "AGENTS.md",
        ".cursorignore",
        ".aiignore",
        ".github/copilot-instructions.md",
        ".github/workflows/copilot-setup-steps.yml"
    )

    # Known output directories (scanned recursively for AUTO-GENERATED files).
    # docs/wiki/Reference/ is intentionally excluded: wiki files are committed source
    # and should only be regenerated by sync, never deleted by --clean.
    $KnownDirs = @(
        ".github/instructions",
        ".github/agents",
        ".github/prompts",
        ".github/skills",
        ".agents",
        ".cursor/rules",
        ".cursor/skills",
        ".aiassistant",
        ".junie"
    )

    $ToDelete = [System.Collections.Generic.List[string]]::new()
    $ToSkip   = [System.Collections.Generic.List[string]]::new()

    # Check individual files
    foreach ($rel in $KnownFiles) {
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path $full -PathType Leaf)) { continue }
        if (Test-AutoGenerated $full) {
            $ToDelete.Add($rel)
        } else {
            $ToSkip.Add($rel)
        }
    }

    # Check directory contents recursively
    foreach ($relDir in $KnownDirs) {
        $fullDir = Join-Path $RepoRoot $relDir
        if (-not (Test-Path $fullDir -PathType Container)) { continue }
        foreach ($file in (Get-ChildItem -Path $fullDir -File -Recurse)) {
            $rel = $file.FullName.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
            if (Test-AutoGenerated $file.FullName) {
                $ToDelete.Add($rel)
            } else {
                $ToSkip.Add($rel)
            }
        }
    }

    # Nothing to do
    if ($ToDelete.Count -eq 0) {
        Write-Host ""
        Write-Host "[sync-ai-configs --clean] Nothing to delete (no auto-generated files found)." -ForegroundColor Green
        if ($ToSkip.Count -gt 0) {
            Write-Host ""
            Write-Host "  Skipped (manually edited):" -ForegroundColor DarkGray
            foreach ($f in $ToSkip) { Write-Host "    $f" -ForegroundColor DarkGray }
        }
        Write-Host ""
        return
    }

    # Print summary
    Write-Host ""
    Write-Host "[sync-ai-configs --clean] Will delete $($ToDelete.Count) auto-generated file(s):" -ForegroundColor Cyan
    foreach ($f in $ToDelete) { Write-Host "    $f" }
    if ($ToSkip.Count -gt 0) {
        Write-Host ""
        Write-Host "  Will skip $($ToSkip.Count) file(s) (manually edited -- AUTO-GENERATED marker removed):" -ForegroundColor Yellow
        foreach ($f in $ToSkip) { Write-Host "    $f" -ForegroundColor Yellow }
    }
    Write-Host ""

    # Confirm (skip if --yes / -y)
    if (-not $script:Yes) {
        if ($script:IsInteractive) {
            $answer = Read-Host "Delete $($ToDelete.Count) file(s)? (y/N)"
            if ($answer -ne "y" -and $answer -ne "Y") {
                Write-Host "Aborted." -ForegroundColor Yellow
                return
            }
        } else {
            Write-Host "[sync-ai-configs --clean] Non-interactive: pass --yes to confirm deletion." -ForegroundColor Yellow
            return
        }
    }

    # Delete files
    $deleted = 0
    foreach ($rel in $ToDelete) {
        $full = Join-Path $RepoRoot $rel
        if (Test-Path $full -PathType Leaf) {
            Remove-Item -Force $full
            Write-Host "  x deleted $rel"
            $deleted++
        }
    }

    # Remove empty directories (deepest first), then check parent dirs
    $allDirs = $KnownDirs | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path $_ -PathType Container }
    foreach ($dir in ($allDirs | Sort-Object { $_.Length } -Descending)) {
        if (Test-Path $dir -PathType Container) {
            Get-ChildItem -Path $dir -Directory -Recurse |
                Sort-Object { $_.FullName.Length } -Descending |
                ForEach-Object {
                    if ((Get-ChildItem -Path $_.FullName -Force | Measure-Object).Count -eq 0) {
                        Remove-Item -Force $_.FullName
                    }
                }
            if ((Get-ChildItem -Path $dir -Force | Measure-Object).Count -eq 0) {
                Remove-Item -Recurse -Force $dir
            }
        }
    }
    # Also remove parent directories that became empty (e.g. .cursor after both
    # .cursor/rules and .cursor/skills are deleted but .cursor itself is not in $KnownDirs)
    $parentDirs = $KnownDirs |
        ForEach-Object { ($_ -replace '[\\/][^\\/]+$', '') } |
        Where-Object { $_ -and ($KnownDirs -notcontains $_) } |
        Sort-Object -Unique
    foreach ($rel in $parentDirs) {
        $full = Join-Path $RepoRoot $rel
        if ((Test-Path $full -PathType Container) -and
            (Get-ChildItem -Path $full -Force | Measure-Object).Count -eq 0) {
            Remove-Item -Recurse -Force $full
        }
    }

    Write-Host ""
    Write-Host "[sync-ai-configs --clean] Done. $deleted file(s) deleted." -ForegroundColor Green
    Write-Host ""
}

function Read-GuidelineFile {
    param([string]$FileName)
    $FilePath = Join-Path $GuidelinesDir $FileName
    if (-not (Test-Path $FilePath)) {
        Write-Warning "Source file not found, skipping: $FilePath"
        return $null
    }
    # Read as raw text, normalise line endings to LF
    $raw = [System.IO.File]::ReadAllText($FilePath)
    $raw = $raw -replace "`r`n", "`n"
    return $raw.TrimEnd("`n") + "`n"
}

# Interactive choice when a manually-edited file conflicts with generated content.
# Sets $script:syncChoice to "r" (replace) or "k" (keep).
# Defaults to "k" in non-interactive mode.
function Get-SyncMergeChoice {
    param(
        [string]$RelativePath,
        [string]$ExistingPath,
        [string]$NewContent
    )

    $script:syncChoice = "k"  # safe default

    # --all: auto-replace without prompting
    if ($GenerateAll) {
        $script:syncChoice = "r"
        return
    }

    # Non-interactive (CI / piped): keep by default
    $isInteractiveSession = [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected)
    if (-not $isInteractiveSession) {
        return
    }

    Write-Host ""
    Write-Host "  [conflict] $RelativePath -- file exists and differs from generated version" -ForegroundColor Yellow

    while ($true) {
        $choice = Read-Host "    (r)eplace with generated / (k)eep existing / (m)erge -- show diff"
        switch ($choice.ToLower()) {
            "r" {
                $script:syncChoice = "r"
                return
            }
            "k" {
                $script:syncChoice = "k"
                return
            }
            "m" {
                Write-Host ""
                $tempNew = [System.IO.Path]::GetTempFileName()
                $tempExisting = [System.IO.Path]::GetTempFileName()
                $savedPref = $ErrorActionPreference
                try {
                    # Normalise to LF for diff
                    $normalized = $NewContent -replace "`r`n", "`n"
                    [System.IO.File]::WriteAllText($tempNew, $normalized)
                    Copy-Item -Force $ExistingPath $tempExisting
                    $ErrorActionPreference = "Continue"
                    if (Get-Command git -ErrorAction SilentlyContinue) {
                        git diff --no-index --color -- $tempExisting $tempNew 2>$null
                        if ($LASTEXITCODE -gt 1) {
                            Write-Host "        (diff failed)" -ForegroundColor Gray
                        }
                    } else {
                        Write-Host "        (diff unavailable -- git not found)" -ForegroundColor Gray
                    }
                } catch {
                    Write-Host "        (diff unavailable)" -ForegroundColor Gray
                } finally {
                    $ErrorActionPreference = $savedPref
                    Remove-Item $tempNew, $tempExisting -ErrorAction SilentlyContinue
                }
                Write-Host ""
                # Loop back to prompt
            }
            default {
                Write-Host "    Please enter r, k, or m." -ForegroundColor Gray
            }
        }
    }
}

function Write-GeneratedFile {
    param(
        [string]$RelativePath,
        [string]$Content
    )
    $FullPath = Join-Path $RepoRoot $RelativePath
    $normalizedNew = $Content -replace "`r`n", "`n"

    if (Test-Path $FullPath -PathType Leaf) {
        # Single read: normalise CRLF so comparison works on Windows
        $existing = ([System.IO.File]::ReadAllText($FullPath)) -replace "`r`n", "`n"

        # Detect AUTO-GENERATED marker from the first 5 lines of the read content
        $headLines = ($existing -split "`n" | Select-Object -First 5) -join "`n"
        $isAuto = $headLines -match "AUTO-GENERATED"

        # Check if content actually differs
        if ($existing -eq $normalizedNew) {
            Write-Host "  [unchanged] $RelativePath" -ForegroundColor DarkGray
            return
        }

        if ($isAuto) {
            # Auto-generated: check if differences are whitespace-only
            $existingTrimmed = ($existing -split "`n" | ForEach-Object { $_.TrimEnd() }) -join "`n"
            $newTrimmed = ($normalizedNew -split "`n" | ForEach-Object { $_.TrimEnd() }) -join "`n"
            if ($existingTrimmed -eq $newTrimmed) {
                # Only whitespace/formatting differences -- replace silently
                $Dir = Split-Path -Parent $FullPath
                if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
                [System.IO.File]::WriteAllText($FullPath, $normalizedNew)
                $GeneratedFiles.Add($RelativePath)
                Write-Host "  `u{2713} [updated] $RelativePath" -ForegroundColor Cyan
            } else {
                # Real content differences -- prompt for confirmation
                Get-SyncMergeChoice $RelativePath $FullPath $Content
                switch ($script:syncChoice) {
                    "r" {
                        $Dir = Split-Path -Parent $FullPath
                        if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
                        [System.IO.File]::WriteAllText($FullPath, $normalizedNew)
                        $GeneratedFiles.Add($RelativePath)
                        Write-Host "  `u{2713} [updated] $RelativePath" -ForegroundColor Cyan
                    }
                    "k" {
                        $KeptFiles.Add($RelativePath)
                        Write-Host "  `u{2298} [kept] $RelativePath" -ForegroundColor DarkGray
                    }
                }
            }
        } else {
            # Not auto-generated -- prompt for confirmation
            Get-SyncMergeChoice $RelativePath $FullPath $Content
            switch ($script:syncChoice) {
                "r" {
                    $Dir = Split-Path -Parent $FullPath
                    if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
                    [System.IO.File]::WriteAllText($FullPath, $normalizedNew)
                    $GeneratedFiles.Add($RelativePath)
                    Write-Host "  `u{2713} [replaced] $RelativePath" -ForegroundColor Cyan
                }
                "k" {
                    $KeptFiles.Add($RelativePath)
                    Write-Host "  `u{2298} [kept] $RelativePath (not auto-generated -- delete file to regenerate)" -ForegroundColor DarkGray
                }
            }
        }
        return
    }

    # New file -- create it
    $Dir = Split-Path -Parent $FullPath
    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($FullPath, $normalizedNew)
    $GeneratedFiles.Add($RelativePath)
    Write-Host "  `u{2713} $RelativePath"
}

function Extract-IgnorePatterns {
    $content = Read-GuidelineFile "ignore-patterns.md"
    if ($null -eq $content) { return $null }
    # Match the first ```gitignore ... ``` fence
    if ($content -match '(?s)```gitignore\s*\n(.*?)```') {
        return $Matches[1].TrimEnd("`n") + "`n"
    }
    Write-Warning "No ```gitignore code fence found in ignore-patterns.md"
    return $null
}

# ---------------------------------------------------------------------------
# Read core source files
# ---------------------------------------------------------------------------
$PolicyIndex           = Read-GuidelineFile "index.md"
$GeneralRules          = Read-GuidelineFile "general-rules.md"
$SecurityAndCompliance = Read-GuidelineFile "security-and-compliance.md"
$Testing               = Read-GuidelineFile "testing.md"

$CoreContent = @($PolicyIndex, $GeneralRules, $SecurityAndCompliance, $Testing) | Where-Object { $null -ne $_ }
$CoreContentJoined = ($CoreContent -join "`n`n")

# ---------------------------------------------------------------------------
# Wiki examples directory and slug-to-filename mapping
# ---------------------------------------------------------------------------
$WikiExamplesDir = Join-Path (Join-Path (Join-Path $RepoRoot "docs") "wiki") "Examples"

# Map language slug to wiki example filename
$ExampleFileMap = @{
    "javascript-typescript" = "TypeScript.md"
}

function Read-LangContent {
    param([string]$Slug)
    $content = Read-GuidelineFile "$Slug.md"
    if ($null -eq $content) { return $null }

    # Look for matching wiki example file
    $exampleFileName = if ($ExampleFileMap.ContainsKey($Slug)) { $ExampleFileMap[$Slug] } else { "$Slug.md" }
    $examplePath = Join-Path $WikiExamplesDir $exampleFileName
    if (Test-Path $examplePath) {
        $exampleRaw = [System.IO.File]::ReadAllText($examplePath)
        $exampleRaw = $exampleRaw -replace "`r`n", "`n"
        $exampleRaw = $exampleRaw.TrimEnd("`n") + "`n"
        $content += "`n" + $exampleRaw
    }
    return $content
}

# ---------------------------------------------------------------------------
# Wiki reference page generation
# ---------------------------------------------------------------------------

function Generate-WikiPages {
    $WikiDir = Join-Path $RepoRoot "docs/wiki"
    $WikiRefDir = Join-Path $WikiDir "Reference"
    if (-not (Test-Path $WikiRefDir)) { New-Item -ItemType Directory -Path $WikiRefDir -Force | Out-Null }

    $WikiHeader = @"
<!-- AUTO-GENERATED from docs/ai-guidelines/ by sync-ai-configs. -->
<!-- Edit the source file in docs/ai-guidelines/, then re-run the sync script. -->

"@

    # Core guideline pages: source filename -> wiki filename
    $WikiCoreMappings = [ordered]@{
        "index.md"                   = "AI-Usage-Policy.md"
        "general-rules.md"           = "Coding-Standards.md"
        "security-and-compliance.md" = "Security-and-Compliance.md"
        "testing.md"                 = "Testing-Guidelines.md"
        "copilot-features.md"        = "Copilot-Configuration.md"
        "ignore-patterns.md"         = "Ignore-Patterns.md"
        "pilot-metrics.md"           = "Pilot-Metrics.md"
    }

    foreach ($mapping in $WikiCoreMappings.GetEnumerator()) {
        $content = Read-GuidelineFile $mapping.Key
        if ($null -ne $content) {
            $body = $WikiHeader + "`n" + $content
            Write-GeneratedFile "docs/wiki/Reference/$($mapping.Value)" $body
        }
    }

    # Map language slug to Title-Case for wiki filenames
    $LangTitleCase = @{
        "csharp"                  = "CSharp"
        "java"                    = "Java"
        "python"                  = "Python"
        "powershell"              = "PowerShell"
        "javascript-typescript"   = "JavaScript-TypeScript"
        "bash"                    = "Bash"
    }

    # Language-specific pages (guideline + wiki example)
    foreach ($slug in $Languages.Keys) {
        $sourcePath = Join-Path $GuidelinesDir "$slug.md"
        if (Test-Path $sourcePath) {
            $content = Read-LangContent $slug
            if ($null -ne $content) {
                $body = $WikiHeader + "`n" + $content
                $titleSlug = if ($LangTitleCase.ContainsKey($slug)) { $LangTitleCase[$slug] } else { $slug }
                Write-GeneratedFile "docs/wiki/Reference/Lang-$titleSlug.md" $body
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Argument parsing and configuration
# ---------------------------------------------------------------------------

$GenerateAll   = $args -contains "--all"
$Reconfigure   = $args -contains "--reconfigure"
$IdeOverride   = ($args | Where-Object { $_ -match '^--ide=' } | Select-Object -First 1) -replace '^--ide=', ''
$NewProject    = $args -contains "--new-project"
$WikiOnly      = $args -contains "--wiki-only"
$Clean         = $args -contains "--clean"
$Yes           = ($args -contains "--yes") -or ($args -contains "-y")
$IsInteractive = [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected)

if ($Clean) { Invoke-Clean; exit 0 }

Write-Host "[sync-ai-configs] Source directory: $GuidelinesDir"

if (-not (Test-Path $GuidelinesDir)) {
    Write-Error "[sync-ai-configs] ERROR: docs/ai-guidelines/ directory not found!"
    exit 1
}

# --- Wiki-only mode: skip tool config entirely ---
if ($WikiOnly) {
    $WikiDir = Join-Path $RepoRoot "docs/wiki"
    if (Test-Path $WikiDir) {
        Write-Host ""
        Write-Host "[sync-ai-configs] Wiki-only mode -- generating docs/wiki/Reference/ pages."
        Generate-WikiPages
        Write-Host ""
        Write-Host "Done. Wiki reference pages generated."
    } else {
        Write-Error "[sync-ai-configs] ERROR: docs/wiki/ directory not found!"
        exit 1
    }
    exit 0
}

if ($GenerateAll) {
    Load-Config | Out-Null   # preserve copilot_agent_ide from saved config if present
    $SelectedTools  = $ToolIds
    $SelectedLangs  = $LangIds
    $SelectedExtras = $ExtraIds
} elseif ($Reconfigure) {
    Invoke-Configure
} elseif (Load-Config) {
    if ($IsInteractive) {
        Write-Host ""
        Write-Host "Current config ($(Split-Path $ConfigFile -Leaf)):"
        Write-Host "  Tools    : $(if ($SelectedTools)  { $SelectedTools  -join ', ' } else { 'none' })"
        Write-Host "  Languages: $(if ($SelectedLangs)  { $SelectedLangs  -join ', ' } else { 'none' })"
        Write-Host "  Extras   : $(if ($SelectedExtras) { $SelectedExtras -join ', ' } else { 'none' })"
        if (Has-Tool "copilot") {
            $ideLabel = switch ($script:CopilotAgentIde) {
                "jetbrains"    { "JetBrains" }
                "visualstudio" { "Visual Studio (Windows)" }
                default        { "VS Code" }
            }
            Write-Host "  Agent IDE: $ideLabel"
        }
        $answer = Read-Host "Use this config? [Y/n/ide]"
        if ($answer -eq "n" -or $answer -eq "N") {
            Invoke-Configure
        } elseif ($answer.ToLower() -eq "ide") {
            Write-Host ""
            Write-Host "  Select agent IDE:"
            Write-Host "    1) VS Code (default)"
            Write-Host "    2) JetBrains"
            Write-Host "    3) Visual Studio (Windows)"
            $ideChoice = Read-Host "  Choice [1-3]"
            $script:CopilotAgentIde = switch ($ideChoice) {
                "2" { "jetbrains" }
                "3" { "visualstudio" }
                default { "vscode" }
            }
            Write-Host "  Agent IDE set to: $($script:CopilotAgentIde)"
            Save-Config
        }
    }
} elseif ($IsInteractive) {
    Invoke-Configure
} else {
    Write-Host "[sync-ai-configs] Non-interactive: generating all configs."
    Load-Config | Out-Null   # preserve copilot_agent_ide from saved config if present
    $SelectedTools  = $ToolIds
    $SelectedLangs  = $LangIds
    $SelectedExtras = $ExtraIds
}

# --- Apply --ide override if provided ---
if ($IdeOverride) {
    $validIdes = @("vscode", "jetbrains", "visualstudio")
    if ($validIdes -contains $IdeOverride) {
        if ($script:CopilotAgentIde -ne $IdeOverride) {
            $script:CopilotAgentIde = $IdeOverride
            Write-Host "[sync-ai-configs] Agent IDE switched to: $IdeOverride"
            Save-Config
        }
    } else {
        Write-Host "[sync-ai-configs] WARNING: Unknown IDE '$IdeOverride'. Valid values: vscode, jetbrains, visualstudio" -ForegroundColor Yellow
        Write-Host "[sync-ai-configs] Continuing with current IDE: $($script:CopilotAgentIde)" -ForegroundColor Yellow
    }
}

# Filter $Languages to selected languages only
$filteredLangs = [ordered]@{}
foreach ($key in $Languages.Keys) {
    if (Has-Lang $key) { $filteredLangs[$key] = $Languages[$key] }
}
$Languages = $filteredLangs

# ---------------------------------------------------------------------------
# Clean up stale outputs from deselected tools
# Only remove files that still contain the AUTO-GENERATED marker.
# Manually edited files (marker removed) are left untouched.
# ---------------------------------------------------------------------------
$cleaned = 0
$skipped = 0

function Remove-GeneratedFile {
    param([string]$RelPath)
    $full = Join-Path $RepoRoot $RelPath
    if (-not (Test-Path $full -PathType Leaf)) { return }
    if (Test-AutoGenerated $full) {
        Remove-Item -Force $full
        Write-Host "  `u{2717} removed $RelPath"
        $script:cleaned++
    } else {
        Write-Host "  `u{2298} kept $RelPath (manually edited)"
        $script:skipped++
    }
}

function Remove-GeneratedDir {
    param([string]$RelPath)
    $full = Join-Path $RepoRoot $RelPath
    if (-not (Test-Path $full -PathType Container)) { return }
    $kept = 0
    # Use foreach statement (not ForEach-Object) so $kept shares this scope
    foreach ($file in (Get-ChildItem -Path $full -File -Recurse)) {
        $rel = $file.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
        if (Test-AutoGenerated $file.FullName) {
            Remove-Item -Force $file.FullName
            Write-Host "  `u{2717} removed $rel"
            $script:cleaned++
        } else {
            Write-Host "  `u{2298} kept $rel (manually edited)"
            $script:skipped++
            $kept++
        }
    }
    if ($kept -eq 0) {
        Remove-Item -Recurse -Force $full -ErrorAction SilentlyContinue
    } else {
        # Remove empty directories left behind
        foreach ($dir in (Get-ChildItem -Path $full -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending)) {
            if ((Get-ChildItem -Path $dir.FullName -Force | Measure-Object).Count -eq 0) {
                Remove-Item -Force $dir.FullName
            }
        }
    }
}

if (-not (Has-Tool "claude")) {
    Remove-GeneratedFile "CLAUDE.md"
    Remove-GeneratedFile ".claudeignore"
}
if (-not (Has-Tool "copilot")) {
    Remove-GeneratedFile ".github/copilot-instructions.md"
    Remove-GeneratedDir  ".github/instructions"
    Remove-GeneratedFile ".github/workflows/copilot-setup-steps.yml"
    Remove-GeneratedDir  ".github/skills"
    if (-not (Has-Extra "agents"))  { Remove-GeneratedDir ".github/agents" }
    if (-not (Has-Extra "prompts")) { Remove-GeneratedDir ".github/prompts" }
}
if (-not (Has-Tool "copilot") -and -not (Has-Tool "codex")) {
    Remove-GeneratedFile "AGENTS.md"
}
if (-not (Has-Tool "codex")) {
    Remove-GeneratedDir ".agents"
}
if (-not (Has-Tool "cursor")) {
    Remove-GeneratedDir  ".cursor/rules"
    Remove-GeneratedDir  ".cursor/skills"
    Remove-GeneratedFile ".cursorignore"
}
if (-not (Has-Tool "jetbrains")) {
    Remove-GeneratedDir  ".aiassistant"
    Remove-GeneratedFile ".aiignore"
}
if (-not (Has-Tool "junie")) {
    Remove-GeneratedDir ".junie"
}
if (-not (Has-Extra "agents")) {
    Remove-GeneratedDir ".github/agents"
}
if (-not (Has-Extra "prompts")) {
    Remove-GeneratedDir ".github/prompts"
}

if ($cleaned -gt 0 -or $skipped -gt 0) {
    Write-Host "[sync-ai-configs] Cleanup: $cleaned removed, $skipped kept (manually edited)."
}

Write-Host ""
Write-Host "[sync-ai-configs] Generating..."

# ---------------------------------------------------------------------------
# 0. AI-SYNC.md -- re-sync instructions at the project root
# ---------------------------------------------------------------------------
$aiSyncBody = @"
$GeneratedHeader

# AI Config Sync

This project uses the **EMA AI Scaffolding** to generate AI tool configurations (Copilot agents, prompt files, coding standards, etc.) from a single source of truth.

## How to Re-Sync

Run this command from the **project root** whenever you want to regenerate all AI configs:

**Windows (PowerShell):**
``````powershell
pwsh scripts/sync-ai-configs.ps1
``````

**macOS / Linux (bash):**
``````bash
bash scripts/sync-ai-configs.sh
``````

The script reads your saved config (`.sync-ai-configs`) and regenerates all files automatically.

## Common Options

| Flag | What it does |
|---|---|
| *(no flags)* | Re-generate using saved config — the default |
| `--reconfigure` | Change which tools, languages, or extras are enabled |
| `--ide=IDE` | Switch agent IDE (vscode, jetbrains, visualstudio) and re-save config |
| `--all` | Generate for all tools and languages (useful for CI) |
| `--wiki-only` | Regenerate only the `docs/wiki/Reference/` pages |
| `--clean` | Remove all generated files (dry run for a fresh setup) |

## What Gets Generated

All generated files have this header:

``````
<!-- AUTO-GENERATED from docs/ai-guidelines/ by sync-ai-configs. -->
``````

**Do not edit generated files directly** — your changes will be overwritten on the next sync. Edit the source files in `docs/ai-guidelines/` instead, then re-run the sync.

## Updating the Scaffolding

To pull in the latest EMA scaffolding improvements:

``````powershell
# SSH
git clone --depth=1 git@ssh.dev.azure.com:v3/euemadev/IRISplatform/EMA.AI.Scaffolding .ema-scaffold
# HTTPS
git clone --depth=1 https://euemadev@dev.azure.com/euemadev/IRISplatform/_git/EMA.AI.Scaffolding .ema-scaffold

& ".ema-scaffold\scripts\setup-existing-project.ps1"
Remove-Item -Recurse -Force .ema-scaffold
``````
"@
Write-GeneratedFile "AI-SYNC.md" $aiSyncBody

# ---------------------------------------------------------------------------
# Build skills summary (shared across generators)
# ---------------------------------------------------------------------------
$CachedSkillLines = @()
# ema-standards skill (generated from core content)
if (Has-Extra "skill") {
    $CachedSkillLines += "- **ema-standards** -- Apply EMA coding standards and security guidelines to code review and generation"
}
# Scan docs/ai-guidelines/skills/*/SKILL.md for additional skills
$skillsSrcDir = Join-Path $GuidelinesDir "skills"
if (Test-Path $skillsSrcDir) {
    Get-ChildItem -Path $skillsSrcDir -Directory | ForEach-Object {
        $skillMdPath = Join-Path $_.FullName "SKILL.md"
        if (Test-Path $skillMdPath) {
            $skillRaw = [System.IO.File]::ReadAllText($skillMdPath)
            $sname = if ($skillRaw -match '(?m)^name:\s*(.+)$') { $Matches[1].Trim() } else { $null }
            $sdesc = if ($skillRaw -match '(?m)^description:\s*"?(.+?)"?\s*$') { $Matches[1].Trim() } else { "" }
            # Skip ema-standards (handled above) and unselected extras
            if ($sname -and $sname -ne "ema-standards") {
                $extraId = switch ($sname) {
                    "dataverse-metadata-export" { "dataverse-skill" }
                    default                     { $sname }
                }
                if (Has-Extra $extraId) {
                    $CachedSkillLines += "- **$sname** -- $sdesc"
                }
            }
        }
    }
}
$CachedSkillsSummary = ""
if ($CachedSkillLines.Count -gt 0) {
    $CachedSkillsSummary = @"
# Available Skills

The following skills are available for your AI tools. Each tool receives a self-contained copy with scripts and references. Read the skill's ``SKILL.md`` for full usage instructions.

$($CachedSkillLines -join "`n")
"@
}

# ---------------------------------------------------------------------------
# 1. CLAUDE.md
# ---------------------------------------------------------------------------
if (Has-Tool "claude") {
# Build Claude content: core + selected language conventions ONLY (no worked examples).
# Claude Code can read docs/wiki/examples/ on demand -- inlining them
# bloats CLAUDE.md past the performance threshold.
$claudeParts = [System.Collections.Generic.List[string]]::new()
$claudeParts.Add($CoreContentJoined)

# Append selected language convention files (alphabetically sorted)
foreach ($lang in ($Languages.Keys | Sort-Object)) {
    $langContent = Read-GuidelineFile "$lang.md"
    if ($null -ne $langContent) { $claudeParts.Add($langContent) }
}

# Add a reference note so Claude Code knows where to find examples
$claudeParts.Add(@"
# Worked Examples

For language-specific worked examples (prompts, expected output, review checklists), see the files in ``docs/wiki/Examples/``. Read them on demand when generating, reviewing, or refactoring code in a specific language.
"@)

# Append skills summary
if ($CachedSkillsSummary) { $claudeParts.Add($CachedSkillsSummary) }

$claudeBody = @"
$GeneratedHeader

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

$($claudeParts -join "`n`n")
"@
Write-GeneratedFile "CLAUDE.md" $claudeBody
}

# ---------------------------------------------------------------------------
# 2. AGENTS.md
# ---------------------------------------------------------------------------
if (Has-Tool "copilot" -or Has-Tool "codex") {
$agentsContent = if ($CachedSkillsSummary) { "$CoreContentJoined`n`n$CachedSkillsSummary" } else { $CoreContentJoined }
$agentsBody = @"
$GeneratedHeader

$agentsContent
"@
Write-GeneratedFile "AGENTS.md" $agentsBody
}

# ---------------------------------------------------------------------------
# 3. .github/copilot-instructions.md
# ---------------------------------------------------------------------------
if (Has-Tool "copilot") {
$copilotContent = if ($CachedSkillsSummary) { "$CoreContentJoined`n`n$CachedSkillsSummary" } else { $CoreContentJoined }
$copilotBody = @"
$GeneratedHeader

$copilotContent
"@
Write-GeneratedFile ".github/copilot-instructions.md" $copilotBody

# ---------------------------------------------------------------------------
# 4. .github/instructions/<lang>.instructions.md
# ---------------------------------------------------------------------------
foreach ($lang in $Languages.Keys) {
    $langContent = Read-LangContent $lang
    if ($null -eq $langContent) { continue }

    $globList = ($Languages[$lang].Globs -join ",")
    $desc = $Languages[$lang].Description
    $body = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
applyTo: "$globList"
---
$GeneratedHeader

$langContent
"@
    Write-GeneratedFile ".github/instructions/$lang.instructions.md" $body
}
}

# ---------------------------------------------------------------------------
# 5. .cursor/rules/general.mdc
# ---------------------------------------------------------------------------
if (Has-Tool "cursor") {
$cursorContent = if ($CachedSkillsSummary) { "$CoreContentJoined`n`n$CachedSkillsSummary" } else { $CoreContentJoined }
$cursorGeneralBody = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
description: "General AI coding standards, security, and testing guidelines"
alwaysApply: true
---
$cursorContent
"@
Write-GeneratedFile ".cursor/rules/general.mdc" $cursorGeneralBody

# ---------------------------------------------------------------------------
# 6. .cursor/rules/<lang>.mdc
# ---------------------------------------------------------------------------
foreach ($lang in $Languages.Keys) {
    $langContent = Read-LangContent $lang
    if ($null -eq $langContent) { continue }

    $desc = $Languages[$lang].Description
    # Build JSON-style glob array
    $globItems = $Languages[$lang].Globs | ForEach-Object { "`"$_`"" }
    $globArray = "[" + ($globItems -join ", ") + "]"

    $body = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
description: "$desc coding conventions"
globs: $globArray
alwaysApply: false
---
$langContent
"@
    Write-GeneratedFile ".cursor/rules/$lang.mdc" $body
}
}

# ---------------------------------------------------------------------------
# 7. .aiassistant/rules/general-standards.md
# ---------------------------------------------------------------------------
if (Has-Tool "jetbrains") {
$aiAssistantContent = if ($CachedSkillsSummary) { "$CoreContentJoined`n`n$CachedSkillsSummary" } else { $CoreContentJoined }
$aiAssistantGeneralBody = @"
$GeneratedHeader

$aiAssistantContent
"@
Write-GeneratedFile ".aiassistant/rules/general-standards.md" $aiAssistantGeneralBody

# ---------------------------------------------------------------------------
# 8. .aiassistant/rules/<lang>.md
# ---------------------------------------------------------------------------
foreach ($lang in $Languages.Keys) {
    $langContent = Read-LangContent $lang
    if ($null -eq $langContent) { continue }

    $body = @"
$GeneratedHeader

$langContent
"@
    Write-GeneratedFile ".aiassistant/rules/$lang.md" $body
}
}

# ---------------------------------------------------------------------------
# 9. .junie/guidelines.md  --  ALL docs concatenated
# ---------------------------------------------------------------------------
if (Has-Tool "junie") {
$allParts = [System.Collections.Generic.List[string]]::new()
if ($null -ne $PolicyIndex)           { $allParts.Add($PolicyIndex) }
if ($null -ne $GeneralRules)          { $allParts.Add($GeneralRules) }
if ($null -ne $SecurityAndCompliance) { $allParts.Add($SecurityAndCompliance) }
if ($null -ne $Testing)               { $allParts.Add($Testing) }

# Language files in alphabetical order (sort explicitly for cross-script parity)
foreach ($lang in ($Languages.Keys | Sort-Object)) {
    $langContent = Read-LangContent $lang
    if ($null -ne $langContent) { $allParts.Add($langContent) }
}

# Append skills summary
if ($CachedSkillsSummary) { $allParts.Add($CachedSkillsSummary) }

$junieBody = @"
$GeneratedHeader

$($allParts -join "`n`n")
"@
Write-GeneratedFile ".junie/guidelines.md" $junieBody
}

# ---------------------------------------------------------------------------
# 10. .github/agents/<name>.agent.md -- specialized custom agents
# ---------------------------------------------------------------------------
if (Has-Tool "copilot" -and Has-Extra "agents") {
$AgentsDir = Join-Path $GuidelinesDir "agents"

# Read pipeline overview (agents/README.md) -- shared across all agents
$pipelineOverview = ""
$pipelineReadmePath = Join-Path $AgentsDir "README.md"
if (Test-Path $pipelineReadmePath) {
    $pipelineOverview = [System.IO.File]::ReadAllText($pipelineReadmePath)
    $pipelineOverview = $pipelineOverview -replace "`r`n", "`n"
    $pipelineOverview = $pipelineOverview.TrimEnd("`n") + "`n"
}

foreach ($agentName in $CustomAgents.Keys) {
    $agentConfig = $CustomAgents[$agentName]

    # Read the agent-specific instructions
    $agentSourcePath = Join-Path $AgentsDir "$agentName.md"
    if (-not (Test-Path $agentSourcePath)) {
        Write-Warning "Agent source not found, skipping: $agentSourcePath"
        continue
    }
    $agentInstructions = [System.IO.File]::ReadAllText($agentSourcePath)
    $agentInstructions = $agentInstructions -replace "`r`n", "`n"
    $agentInstructions = $agentInstructions.TrimEnd("`n") + "`n"

    # Build model YAML -- single model value per agent (no arrays)
    $modelYaml = "model: $($agentConfig.Model)"

    # Build argument-hint YAML
    $argumentHintYaml = ""
    if ($agentConfig.ContainsKey("ArgumentHint") -and $agentConfig.ArgumentHint) {
        $argumentHintYaml = "`nargument-hint: `"$($agentConfig.ArgumentHint)`""
    }

    # Build handoffs YAML
    $handoffsYaml = ""
    if ($agentConfig.Handoffs.Count -gt 0) {
        $handoffLines = @("handoffs:")
        foreach ($h in $agentConfig.Handoffs) {
            $handoffLines += "  - label: `"$($h.Label)`""
            $handoffLines += "    agent: $($h.Agent)"
            $handoffLines += "    prompt: `"$($h.Prompt)`""
        }
        $handoffsYaml = "`n" + ($handoffLines -join "`n")
    } else {
        $handoffsYaml = "`nhandoffs: []"
    }

    # Pick tools for the selected Copilot IDE
    $agentTools = switch ($script:CopilotAgentIde) {
        "jetbrains"    { $agentConfig.ToolsJetBrains }
        "visualstudio" { $agentConfig.ToolsVisualStudio }
        default        { $agentConfig.ToolsVSCode }
    }

    # Build agents YAML
    $agentsYaml = "agents: $($agentConfig.Agents)"

    # Select guidelines based on scope
    $guidelinesContent = $CoreContentJoined
    if ($agentConfig.GuidelinesScope -eq "none") {
        $guidelinesContent = ""
    } elseif ($agentConfig.GuidelinesScope -eq "security") {
        # Security scope = policy index + security-and-compliance (no general-rules or testing)
        $securityParts = @($PolicyIndex, $SecurityAndCompliance) | Where-Object { $null -ne $_ }
        $guidelinesContent = ($securityParts -join "`n`n")
    }
    # Append skills summary to agent guidelines (skip for "none" scope — dispatcher doesn't need skills)
    if ($CachedSkillsSummary -and $agentConfig.GuidelinesScope -ne "none") {
        $guidelinesContent += "`n`n$CachedSkillsSummary"
    }

    $pipelineSection = ""
    if ($agentConfig.ContainsKey("IncludePipelineOverview") -and $agentConfig.IncludePipelineOverview) {
        $pipelineSection = $pipelineOverview
    }

    $guidelinesSection = ""
    if ($guidelinesContent) {
        $guidelinesSection = @"

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

$guidelinesContent
"@
    }

    $agentBody = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: "$agentName"
description: "$($agentConfig.Description)"$argumentHintYaml
$modelYaml
tools: $($agentTools)
$agentsYaml$handoffsYaml
---
$GeneratedHeader

$agentInstructions

$pipelineSection
$guidelinesSection
"@
    Write-GeneratedFile ".github/agents/$agentName.agent.md" $agentBody
}
}

# ---------------------------------------------------------------------------
# 11. .github/copilot-setup-steps.yml (only if not customized)
# ---------------------------------------------------------------------------
if (Has-Tool "copilot") {
    $setupStepsBody = @"
# AUTO-GENERATED by sync-ai-configs.
# Customize this workflow for your project's environment setup.
# Once customized, remove the "# AUTO-GENERATED" line above so
# future sync runs preserve your changes.
#
# This workflow runs before Copilot coding agent sessions to prepare
# the development environment. Only file/artifact changes persist
# (not system-level changes like apt-get installs or exported env vars).
#
# Requirements:
#   - Job must be named "copilot-setup-steps"
#   - Trigger must be "workflow_dispatch"
#   - Keep setup fast to avoid delaying the agent
#
# See: https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-environment
# See: docs/ai-guidelines/copilot-features.md for full documentation and examples

name: "Copilot Setup Steps"

on: workflow_dispatch

jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      # -- Add your environment setup steps below --
      #
      # Uncomment and adapt the examples for your stack.
      # Combine multiple blocks for multi-language projects.
      #
      # -- Node.js / TypeScript --
      # - name: Set up Node.js
      #   uses: actions/setup-node@v4
      #   with:
      #     node-version: "20"
      #     cache: "npm"
      # - name: Install dependencies
      #   run: npm ci
      # - name: Build
      #   run: npm run build
      #
      # -- Python --
      # - name: Set up Python
      #   uses: actions/setup-python@v5
      #   with:
      #     python-version: "3.12"
      # - name: Install dependencies
      #   run: |
      #     python -m pip install --upgrade pip
      #     pip install -r requirements.txt
      #
      # -- .NET / C# --
      # - name: Set up .NET
      #   uses: actions/setup-dotnet@v4
      #   with:
      #     dotnet-version: "8.0.x"
      # - name: Restore and build
      #   run: dotnet restore && dotnet build --no-restore
      #
      # -- Java / Maven --
      # - name: Set up Java
      #   uses: actions/setup-java@v4
      #   with:
      #     distribution: "temurin"
      #     java-version: "21"
      #     cache: "maven"
      # - name: Build
      #   run: mvn -B package --file pom.xml
      #
      # -- Docker Compose (databases / services) --
      # - name: Start services
      #   run: docker compose -f docker-compose.dev.yml up -d
      # - name: Wait for database
      #   run: |
      #     until docker compose -f docker-compose.dev.yml exec -T db pg_isready; do
      #       sleep 2
      #     done
      # - name: Run migrations
      #   run: npm run db:migrate
      #
      # Note: Only file changes in the workspace persist into the
      # agent session. System-level changes (apt-get, global installs,
      # exported env vars) do NOT persist.
"@
    Write-GeneratedFile ".github/workflows/copilot-setup-steps.yml" $setupStepsBody
}

# ---------------------------------------------------------------------------
# 12. .github/prompts/review-guidelines.prompt.md
# ---------------------------------------------------------------------------
if (Has-Tool "copilot" -and Has-Extra "prompts") {
    $reviewPromptBody = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
description: "Review code against EMA AI development guidelines"
agent: "ask"
---
$GeneratedHeader

Review the following code against the EMA coding standards. Check for:

1. **Security**: No hardcoded credentials, parameterized queries, input validation
2. **Code quality**: Readability, single responsibility, meaningful names, no deep nesting
3. **Testing**: Behavior-focused tests, descriptive names, Arrange/Act/Assert pattern
4. **Git practices**: Atomic changes, meaningful commit messages
5. **Documentation**: Comments explain WHY not WHAT, docs updated if behavior changed

Highlight any violations and suggest specific fixes.

`${selection}
"@
    Write-GeneratedFile ".github/prompts/review-guidelines.prompt.md" $reviewPromptBody
}

# ---------------------------------------------------------------------------
# 13. .github/prompts/generate-tests.prompt.md
# ---------------------------------------------------------------------------
if (Has-Tool "copilot" -and Has-Extra "prompts") {
    $testsPromptBody = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
description: "Generate tests following EMA testing guidelines"
agent: "agent"
---
$GeneratedHeader

Generate tests for the selected code following EMA testing guidelines:

- Test behavior, not implementation
- Use descriptive names (Given/When/Then or Should format)
- One assertion concept per test
- Arrange/Act/Assert pattern
- Test edge cases: nulls, empty collections, boundary values
- Don't mock what you don't own -- wrap external dependencies
- Use meaningful test data variable names

`${file}
"@
    Write-GeneratedFile ".github/prompts/generate-tests.prompt.md" $testsPromptBody
}

# ---------------------------------------------------------------------------
# 14a. .github/prompts/generate-backlog.prompt.md
# ---------------------------------------------------------------------------
if (Has-Tool "copilot" -and Has-Extra "prompts" -and Has-Extra "agents") {
    $generateBacklogPromptBody = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
agent: agent
description: "Generate a SAFe-structured backlog from a high-level idea, or refine an existing backlog JSON file."
tools: ['edit/editFiles', 'azure-devops/*']
---
$GeneratedHeader

# Generate or Refine a SAFe Backlog

You are a SAFe product management expert. You operate in two modes:

- **Generate** -- decompose a new idea into a SAFe backlog hierarchy and save it as a JSON file.
- **Refine** -- load an existing backlog JSON file and improve, extend, or restructure it based on the user's feedback.

## Step 0 -- Determine Mode

1. If the message references an existing file (e.g. a path starting with ``backlog/``, or phrases like "refine", "update", "improve", "expand", "rework"), set mode to **Refine**.
2. Otherwise set mode to **Generate**.

## Generate mode

1. Search the project wiki (2-3 keyword queries) for relevant architecture decisions and team standards.
2. Identify initiative type: business, technical, or mixed.
3. Decompose into 1-3 Epics with Features, Stories/Enablers, and Tasks. Apply Fibonacci sizing for stories (1, 2, 3, 5, 8, 13).
4. Save to ``backlog/YYYY-MM-DD-{slug}.json``.
5. Print a summary table (counts by SAFe level) and ask: *"Would you like to refine this further, or shall I push it to ADO?"*

## Refine mode

1. Read the file and show current structure (counts by type).
2. Confirm what the user wants to change unless already stated.
3. Apply changes and overwrite the same file.
4. End with: *"Anything else to refine, or are you ready to push to ADO?"*

## SAFe rules (always apply)

- Title formats: Epic ``[Domain] -- [Strategic Goal]``, Feature ``[Action verb] [capability]``, User Story ``As a [persona], I want [goal], so that [outcome]``
- Acceptance criteria: Given/When/Then notation on all items except Tasks
- Valid status values: ``not-started``, ``in-progress``, ``ready``, ``review``, ``done``, ``blocked``
- Schema: ``templates/safe-backlog-schema.json``
"@
    Write-GeneratedFile ".github/prompts/generate-backlog.prompt.md" $generateBacklogPromptBody
}

# ---------------------------------------------------------------------------
# 14b. .github/prompts/push-to-ado.prompt.md
# ---------------------------------------------------------------------------
if (Has-Tool "copilot" -and Has-Extra "prompts") {
    $pushToAdoPromptBody = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
agent: agent
description: "Push a staged backlog JSON file to Azure DevOps. Creates all SAFe work items with correct hierarchy and parent-child links."
tools: ['azure-devops/*']
---
$GeneratedHeader

# Push Backlog to Azure DevOps

Parse the backlog JSON file the user specified. If no file is given, list ``backlog/`` and ask which file to push.

## Step 1 -- Resolve Area Path and Iteration Path

Resolve in this precedence order (highest first):
1. ``backlog.config.json`` (workspace root, gitignored) -- read ``areaPath`` and ``iterationPath``.
2. Root fields in the backlog JSON file.
3. Individual item field overrides.
4. Ask the user if still unresolved.

Direct the user to copy ``backlog.config.example.json`` to ``backlog.config.json`` and fill in their values.

## Step 2 -- Pre-flight summary

Print a summary table showing counts by work item type and the resolved Area Path and Iteration Path.
Ask: *"I will create N work items. Shall I proceed? (yes/no)"* -- wait for explicit confirmation.

## Step 3 -- Create work items top-down

Process items in order: Epics first, then Features, then Stories/Enablers, then Tasks.
Capture the returned ADO ID for every created item -- you need IDs to link parent-child relationships.
Establish parent-child links after all items at each level are created.

## Step 4 -- Results table

Print a results table with ADO ID, type, title, and direct URL for every created item.
"@
    Write-GeneratedFile ".github/prompts/push-to-ado.prompt.md" $pushToAdoPromptBody
}

# ---------------------------------------------------------------------------
# 14c. .github/prompts/review-work-item.prompt.md
# ---------------------------------------------------------------------------
if (Has-Tool "copilot" -and Has-Extra "prompts") {
    $reviewWorkItemPromptBody = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
agent: agent
description: "Review an existing Azure DevOps work item -- fetches the item, its children, and siblings, then proposes SAFe-aligned improvements."
tools: ['azure-devops/*']
---
$GeneratedHeader

# Review Existing Work Item

The user provides a work item ID or URL. If none given, ask for one.

## Step 1 -- Fetch the work item

Fetch the item, its parent, its children, and its siblings using the ADO MCP tools.
Record: type, title, description, acceptanceCriteria, storyPoints / estimatedHours, state, areaPath, iterationPath, parent ID.

## Step 2 -- Search the project wiki

Search the project wiki (2-3 keyword queries from the title/description) for architecture decisions, standards, and related components.

## Step 3 -- Structural summary

Print a context card before analysis:
``````
Work Item: #<ID> -- <Title>
Type: <type>  |  State: <state>  |  Parent: #<parentId> -- <parentTitle>
Children: <N>  |  Siblings: <N>
``````

## Step 4 -- Evaluate across 7 SAFe dimensions

1. **Title format** -- matches the pattern for its type?
2. **Description quality** -- 2-4 sentences, business or technical value clear?
3. **Acceptance criteria** -- Given/When/Then notation, measurable outcomes?
4. **Sizing** -- Fibonacci story points or reasonable estimated hours?
5. **Hierarchy placement** -- correct SAFe level for its scope?
6. **Sibling consistency** -- titles and AC at a similar level of detail and format?
7. **Area / Iteration paths** -- valid and consistent with siblings?

## Step 5 -- Improvement proposals

Present numbered proposals with current value → suggested value and a one-sentence rationale.
Ask: *"Apply all, apply #N, or skip?"*
"@
    Write-GeneratedFile ".github/prompts/review-work-item.prompt.md" $reviewWorkItemPromptBody
}

# ---------------------------------------------------------------------------
# 14. Unified skill generation for all tools
# ---------------------------------------------------------------------------

# Helper: copy a source skill directory to a destination
function Copy-SourceSkill {
    param([string]$SrcDir, [string]$DestDir)
    $skillMdPath = Join-Path $SrcDir "SKILL.md"
    if (Test-Path $skillMdPath) {
        $content = [System.IO.File]::ReadAllText($skillMdPath) -replace "`r`n", "`n"
        # Rewrite absolute paths so SKILL.md references scripts/references relative
        # to its own location, not the canonical authoring source.
        $skillName = Split-Path $SrcDir -Leaf
        $safeRepl = $DestDir.Replace('$', '$$') + '/'
        $content = $content -replace [regex]::Escape("docs/ai-guidelines/skills/$skillName/"), $safeRepl
        # Inject AUTO-GENERATED marker so --clean can detect the file.
        if ($content.StartsWith("---")) {
            $content = $content -replace "^---", "---`n# AUTO-GENERATED by sync-ai-configs. Do not edit directly."
        } else {
            $content = "<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->`n$content"
        }
        Write-GeneratedFile "$DestDir/SKILL.md" $content
    }
    $scriptsDir = Join-Path $SrcDir "scripts"
    if (Test-Path $scriptsDir) {
        Get-ChildItem -Path $scriptsDir -File | ForEach-Object {
            $fc = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
            # Add AUTO-GENERATED marker (use # for scripts, <!-- --> for .md)
            $marker = if ($_.Extension -eq ".md") { "<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->" } else { "# AUTO-GENERATED by sync-ai-configs. Do not edit directly." }
            Write-GeneratedFile "$DestDir/scripts/$($_.Name)" "$marker`n$fc"
        }
    }
    $refsDir = Join-Path $SrcDir "references"
    if (Test-Path $refsDir) {
        Get-ChildItem -Path $refsDir -File | ForEach-Object {
            $fc = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
            # Add AUTO-GENERATED marker (use <!-- --> for .md, # for scripts)
            $marker = if ($_.Extension -in ".py", ".sh", ".ps1") { "# AUTO-GENERATED by sync-ai-configs. Do not edit directly." } else { "<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->" }
            Write-GeneratedFile "$DestDir/references/$($_.Name)" "$marker`n$fc"
        }
    }
}

# Helper: extract SKILL.md body (after YAML frontmatter)
function Get-SkillBody {
    param([string]$FilePath)
    $lines = [System.IO.File]::ReadAllText($FilePath) -replace "`r`n", "`n" -split "`n"
    $inFrontmatter = $false; $pastFrontmatter = $false; $body = @()
    foreach ($line in $lines) {
        if (-not $pastFrontmatter -and $line -eq '---') {
            if ($inFrontmatter) { $pastFrontmatter = $true; continue }
            else { $inFrontmatter = $true; continue }
        }
        if ($pastFrontmatter) { $body += $line }
    }
    # If no frontmatter found, return all content as-is
    if (-not $pastFrontmatter) { return ($lines -join "`n") }
    return ($body -join "`n")
}

# ema-standards: only for tools where core content is NOT already in general config
if (Has-Extra "skill") {
    $emaDesc = "Apply EMA coding standards and security guidelines to code review and generation. Use this skill when reviewing code, generating new code, or refactoring existing code to ensure compliance with EMA development guidelines."
    $emaSkill = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: ema-standards
description: "$emaDesc"
---
$GeneratedHeader

$CoreContentJoined
"@
    if (Has-Tool "copilot") { Write-GeneratedFile ".github/skills/ema-standards/SKILL.md" $emaSkill }
    if (Has-Tool "codex")   { Write-GeneratedFile ".agents/skills/ema-standards/SKILL.md" $emaSkill }
}

# Source-based skills (from docs/ai-guidelines/skills/)
$skillsSrcRoot = Join-Path $GuidelinesDir "skills"
if (Test-Path $skillsSrcRoot) {
    Get-ChildItem -Path $skillsSrcRoot -Directory | ForEach-Object {
        $skillName = $_.Name
        $skillMdPath = Join-Path $_.FullName "SKILL.md"
        if (-not (Test-Path $skillMdPath)) { return }

        # Map skill directory name to extras ID
        $extraId = switch ($skillName) {
            "dataverse-metadata-export" { "dataverse-skill" }
            default { $skillName }
        }
        if (-not (Has-Extra $extraId)) { return }

        # Read skill metadata for rule-based tools
        $skillRaw = [System.IO.File]::ReadAllText($skillMdPath)
        $sDesc = if ($skillRaw -match '(?m)^description:\s*"?(.+?)"?\s*$') { $Matches[1].Trim() } else { "" }

        # SKILL.md-format tools (full directory copy)
        if (Has-Tool "copilot") { Copy-SourceSkill $_.FullName ".github/skills/$skillName" }
        if (Has-Tool "codex")   { Copy-SourceSkill $_.FullName ".agents/skills/$skillName" }
        if (Has-Tool "junie")   { Copy-SourceSkill $_.FullName ".junie/skills/$skillName" }

        # Cursor: Agent Requested rule + self-contained scripts/references
        if (Has-Tool "cursor") {
            $skillBodyText = Get-SkillBody $skillMdPath
            $cursorDestDir = ".cursor/skills/$skillName"
            $safeRepl = $cursorDestDir.Replace('$', '$$') + '/'
            $skillBodyText = $skillBodyText -replace [regex]::Escape("docs/ai-guidelines/skills/$skillName/"), $safeRepl
            $cursorRule = @"
---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
description: "$sDesc"
alwaysApply: true
---
$skillBodyText
"@
            Write-GeneratedFile ".cursor/rules/skill-$skillName.mdc" $cursorRule
            # Copy scripts and references so the skill is self-contained
            $srcScriptsDir = Join-Path $_.FullName "scripts"
            if (Test-Path $srcScriptsDir) {
                Get-ChildItem -Path $srcScriptsDir -File | ForEach-Object {
                    $fc = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
                    $marker = if ($_.Extension -eq ".md") { "<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->" } else { "# AUTO-GENERATED by sync-ai-configs. Do not edit directly." }
                    Write-GeneratedFile "$cursorDestDir/scripts/$($_.Name)" "$marker`n$fc"
                }
            }
            $srcRefsDir = Join-Path $_.FullName "references"
            if (Test-Path $srcRefsDir) {
                Get-ChildItem -Path $srcRefsDir -File | ForEach-Object {
                    $fc = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
                    $marker = if ($_.Extension -in ".py", ".sh", ".ps1") { "# AUTO-GENERATED by sync-ai-configs. Do not edit directly." } else { "<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->" }
                    Write-GeneratedFile "$cursorDestDir/references/$($_.Name)" "$marker`n$fc"
                }
            }
        }

        # JetBrains AI Assistant: rule file + self-contained scripts/references
        if (Has-Tool "jetbrains") {
            $skillBodyText = Get-SkillBody $skillMdPath
            $jbDestDir = ".aiassistant/skills/$skillName"
            $safeRepl = $jbDestDir.Replace('$', '$$') + '/'
            $skillBodyText = $skillBodyText -replace [regex]::Escape("docs/ai-guidelines/skills/$skillName/"), $safeRepl
            $aiRule = @"
$GeneratedHeader

$skillBodyText
"@
            Write-GeneratedFile ".aiassistant/rules/skill-$skillName.md" $aiRule
            # Copy scripts and references so the skill is self-contained
            $srcScriptsDir = Join-Path $_.FullName "scripts"
            if (Test-Path $srcScriptsDir) {
                Get-ChildItem -Path $srcScriptsDir -File | ForEach-Object {
                    $fc = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
                    $marker = if ($_.Extension -eq ".md") { "<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->" } else { "# AUTO-GENERATED by sync-ai-configs. Do not edit directly." }
                    Write-GeneratedFile "$jbDestDir/scripts/$($_.Name)" "$marker`n$fc"
                }
            }
            $srcRefsDir = Join-Path $_.FullName "references"
            if (Test-Path $srcRefsDir) {
                Get-ChildItem -Path $srcRefsDir -File | ForEach-Object {
                    $fc = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
                    $marker = if ($_.Extension -in ".py", ".sh", ".ps1") { "# AUTO-GENERATED by sync-ai-configs. Do not edit directly." } else { "<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->" }
                    Write-GeneratedFile "$jbDestDir/references/$($_.Name)" "$marker`n$fc"
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 15. Ignore files (.aiignore, .claudeignore, .cursorignore)
# ---------------------------------------------------------------------------
$ignorePatterns = Extract-IgnorePatterns
if ($null -ne $ignorePatterns) {
    $ignoreHeader = "# AUTO-GENERATED by sync-ai-configs. Do not edit directly.`n# Edit the source file in docs/ai-guidelines/ignore-patterns.md instead.`n`n"
    $ignoreBody = $ignoreHeader + $ignorePatterns
    if (Has-Tool "claude")    { Write-GeneratedFile ".claudeignore" $ignoreBody }
    if (Has-Tool "cursor")    { Write-GeneratedFile ".cursorignore" $ignoreBody }
    if (Has-Tool "jetbrains") { Write-GeneratedFile ".aiignore"     $ignoreBody }
} else {
    Write-Warning "Skipping ignore files: could not extract patterns."
}

# ---------------------------------------------------------------------------
# 16. Wiki reference pages (always generated when docs/wiki/ exists)
# ---------------------------------------------------------------------------
$WikiDir = Join-Path $RepoRoot "docs/wiki"
if (Test-Path $WikiDir) {
    Generate-WikiPages
}

# ---------------------------------------------------------------------------
# New-project setup (detach from template origin)
# ---------------------------------------------------------------------------
if ($NewProject) {
    try {
        $originUrl = git -C $RepoRoot remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0 -and $originUrl -and ($originUrl -match "EMA.*Scaffolding" -or $originUrl -match "scaffolding")) {
            git -C $RepoRoot remote remove origin
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to remove origin remote."
            } else {
                Write-Host "[sync-ai-configs] Removed template origin."
                Write-Host "  Set your project's remote with:  git remote add origin <your-repo-url>"
            }
        } elseif ($LASTEXITCODE -eq 0 -and $originUrl) {
            Write-Host "[sync-ai-configs] Origin does not point to the template repo -- keeping it."
        }
    } catch { Write-Warning "git command failed: $_" }
} elseif (-not $GenerateAll -and $IsInteractive) {
    try {
        $originUrl = git -C $RepoRoot remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0 -and $originUrl -and ($originUrl -match "EMA.*Scaffolding" -or $originUrl -match "scaffolding")) {
            Write-Host ""
            $answer = Read-Host "Origin points to the template repo. Remove it? [y/N]"
            if ($answer -eq "y" -or $answer -eq "Y") {
                git -C $RepoRoot remote remove origin
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Failed to remove origin remote."
                } else {
                    Write-Host "[sync-ai-configs] Removed template origin."
                    Write-Host "  Set your project's remote with:  git remote add origin <your-repo-url>"
                }
            }
        }
    } catch { Write-Warning "git command failed: $_" }
}

# ---------------------------------------------------------------------------
# Ensure artifacts/ directory exists (agents save work here)
# ---------------------------------------------------------------------------
$ArtifactsDir = Join-Path $RepoRoot "artifacts"
if (-not (Test-Path $ArtifactsDir)) {
    New-Item -ItemType Directory -Path $ArtifactsDir -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $ArtifactsDir ".gitkeep") -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Ensure backlog support files exist (ema-backlog-manager)
# ---------------------------------------------------------------------------
if (Has-Extra "agents") {
    # templates/safe-backlog-schema.json -- JSON schema for backlog files
    $TemplatesDir = Join-Path $RepoRoot "templates"
    $SchemaSource = Join-Path $RepoRoot "templates" "safe-backlog-schema.json"
    $SchemaDest   = Join-Path $TemplatesDir "safe-backlog-schema.json"
    if ($SchemaSource -and (Test-Path $SchemaSource) -and -not (Test-Path $SchemaDest)) {
        if (-not (Test-Path $TemplatesDir)) {
            New-Item -ItemType Directory -Path $TemplatesDir -Force | Out-Null
        }
        Copy-Item -Path $SchemaSource -Destination $SchemaDest -Force
        Write-Host "  + created templates/safe-backlog-schema.json"
    }

    # .vscode/mcp.json -- Azure DevOps MCP server config (needed for azure-devops/* tools in ema-backlog-manager)
    $VsCodeDir = Join-Path $RepoRoot ".vscode"
    $McpJsonPath = Join-Path $VsCodeDir "mcp.json"
    if (-not (Test-Path $McpJsonPath)) {
        if (-not (Test-Path $VsCodeDir)) {
            New-Item -ItemType Directory -Path $VsCodeDir -Force | Out-Null
        }
        $mcpContent = @"
{
  "servers": {
    "azure-devops": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp", "euemadev", "--domains", "work-items,core"]
    }
  }
}
"@
        [System.IO.File]::WriteAllText($McpJsonPath, $mcpContent)
        Write-Host "  + created .vscode/mcp.json (Azure DevOps MCP server for ema-backlog-manager)"
        Write-Host "    Requires Node.js / npx. First use will prompt for OAuth in VS Code." -ForegroundColor Cyan
    }

    # Remind about .gitignore entries
    $GitIgnorePath = Join-Path $RepoRoot ".gitignore"
    if (Test-Path $GitIgnorePath) {
        $gitIgnoreContent = Get-Content $GitIgnorePath -Raw
        if ($gitIgnoreContent -notmatch "backlog/\*\.json") {
            Write-Host ""
            Write-Host "  [backlog-manager] Add these entries to .gitignore to avoid committing local backlog files:" -ForegroundColor Yellow
            Write-Host "    backlog/*.json"
            Write-Host "    backlog.config.json"
            Write-Host ""
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
if ($KeptFiles.Count -gt 0) {
    Write-Host "Done. $($GeneratedFiles.Count) files generated, $($KeptFiles.Count) kept (manually edited)." -ForegroundColor Green
} else {
    Write-Host "Done. $($GeneratedFiles.Count) files generated." -ForegroundColor Green
}
