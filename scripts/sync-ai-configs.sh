#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# sync-ai-configs.sh
#
# Reads canonical Markdown from docs/ai-guidelines/ and generates native
# config files for 6 AI coding tools:
#   - Claude Code    (CLAUDE.md)
#   - GitHub Copilot (.github/copilot-instructions.md + per-language
#                     + agents, prompts, skills, setup steps)
#   - Cursor         (.cursor/rules/)
#   - JetBrains AI   (.aiassistant/rules/)
#   - Junie          (.junie/guidelines.md)
#   - AGENTS.md
#   - Ignore files   (.aiignore, .claudeignore, .cursorignore)
#
# Flags:
#   --all           Generate configs for all tools/languages (skip prompts)
#   --reconfigure   Re-run the tool/language selection menu
#   --ide=IDE       Switch agent IDE (vscode, jetbrains, visualstudio) and re-save config
#   --new-project   Detach from template origin after generation
#   --wiki-only     Generate only docs/wiki/Reference/ pages (no tool configs)
#   --clean         Delete all auto-generated outputs (with confirmation)
#   --yes / -y      Skip confirmation prompt (use with --clean)
#
# No external dependencies -- only bash builtins + mkdir, cat, sed, tr.
# Idempotent -- safe to run repeatedly.
# Compatible with macOS's stock Bash 3.2 (no mapfile, no ${var,,}).
###############################################################################

# Bash 3.2 compatible lowercase conversion (${var,,} requires Bash 4.0+)
_to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Resolve project root (one level up from scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DOCS_DIR="$PROJECT_ROOT/docs/ai-guidelines"

# Language definitions: slug | display name | globs (comma-separated)
LANGUAGES=(
  "csharp|C#|**/*.cs,**/*.csx"
  "java|Java|**/*.java"
  "python|Python|**/*.py"
  "powershell|PowerShell|**/*.ps1,**/*.psm1,**/*.psd1"
  "javascript-typescript|JavaScript / TypeScript|**/*.js,**/*.jsx,**/*.ts,**/*.tsx,**/*.mjs,**/*.cjs"
  "bash|Bash / Shell|**/*.sh"
)

###############################################################################
# Selection: which tools, languages, and Copilot extras to generate
###############################################################################

CONFIG_FILE="$PROJECT_ROOT/.sync-ai-configs"

TOOL_IDS=(    "claude"      "copilot"          "codex"                               "cursor" "jetbrains"             "junie"        )
TOOL_LABELS=( "Claude Code" "GitHub Copilot"   "OpenAI Codex / Copilot Coding Agent" "Cursor" "JetBrains AI Assistant" "Junie"        )
LANG_IDS=(    "csharp" "java"  "python" "powershell" "javascript-typescript"    "bash"         )
LANG_LABELS=( "C#"     "Java"  "Python" "PowerShell" "JavaScript / TypeScript"  "Bash / Shell" )
EXTRA_IDS=(    "agents"                 "prompts"                                   "skill"                     "dataverse-skill"                 )
EXTRA_LABELS=( "Custom agent pipeline" "Prompt files (review-guidelines, generate-tests)" "Agent skill (ema-standards)" "Dataverse metadata export skill" )

SELECTED_TOOLS=()
SELECTED_LANGS=()
SELECTED_EXTRAS=()
NEW_PROJECT=false
COPILOT_AGENT_IDE="vscode"

# The "${arr[@]+"${arr[@]}"}" pattern safely handles empty arrays under set -u on bash < 4.4.
has_tool()  { local t; for t in "${SELECTED_TOOLS[@]+"${SELECTED_TOOLS[@]}"}";  do [[ "$t" == "$1" ]] && return 0; done; return 1; }
has_lang()  { local l; for l in "${SELECTED_LANGS[@]+"${SELECTED_LANGS[@]}"}";  do [[ "$l" == "$1" ]] && return 0; done; return 1; }
has_extra() { local e; for e in "${SELECTED_EXTRAS[@]+"${SELECTED_EXTRAS[@]}"}"; do [[ "$e" == "$1" ]] && return 0; done; return 1; }

# Populate the named result array from a numbered menu.
# Caller sets _MENU_IDS and _MENU_LABELS before calling.
_select_from_menu() {
  local result_var="$1"
  echo "  Enter numbers separated by commas, or 'all', or press Enter to skip:"
  local i
  for i in "${!_MENU_LABELS[@]}"; do
    printf "    %d) %s\n" "$((i+1))" "${_MENU_LABELS[$i]}"
  done
  read -r input
  local selected=()
  if [[ "$(_to_lower "$input")" == "all" ]]; then
    selected=("${_MENU_IDS[@]}")
  elif [[ -n "$input" ]]; then
    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
      part="${part//[[:space:]]/}"
      if [[ "$part" =~ ^[0-9]+$ ]] && (( part >= 1 && part <= ${#_MENU_IDS[@]} )); then
        selected+=("${_MENU_IDS[$((part-1))]}")
      fi
    done
  fi
  # Safe empty-array eval: eval "${result_var}=("${arr[@]}")" crashes under set -u when arr is empty.
  if [[ ${#selected[@]} -gt 0 ]]; then
    eval "${result_var}=(\"${selected[@]}\")"
  else
    eval "${result_var}=()"
  fi
}

save_config() {
  {
    echo "# sync-ai-configs selection -- commit this file to share with your team."
    echo "# Delete it (or run sync-ai-configs --reconfigure) to change selections."
    printf "tools=%s\n"          "$(IFS=','; printf '%s' "${SELECTED_TOOLS[*]:-}")"
    printf "languages=%s\n"      "$(IFS=','; printf '%s' "${SELECTED_LANGS[*]:-}")"
    printf "copilot_extras=%s\n" "$(IFS=','; printf '%s' "${SELECTED_EXTRAS[*]:-}")"
    printf "copilot_agent_ide=%s\n" "$COPILOT_AGENT_IDE"
  } > "$CONFIG_FILE"
  echo "[sync-ai-configs] Config saved to $(basename "$CONFIG_FILE") -- commit it to share with your team."
}

load_config() {
  [[ ! -f "$CONFIG_FILE" ]] && return 1
  # Backward-compat: older configs used spaces instead of commas and may
  # contain old extra IDs (skill-ema-standards -> skill, skill-dv-export -> dataverse-skill).
  _parse_csv_or_space() {
    local val="$1"
    # Accept both comma-separated and space-separated values
    local -a items
    if [[ "$val" == *,* ]]; then
      IFS=',' read -ra items <<< "$val"
    else
      IFS=' ' read -ra items <<< "$val"
    fi
    # Trim whitespace from each item
    local -a result=()
    for item in "${items[@]}"; do
      item="${item//[[:space:]]/}"
      [[ -n "$item" ]] && result+=("$item")
    done
    # Guard: printf '%s\n' with no args outputs a blank line under Bash 3.2
    [[ ${#result[@]} -gt 0 ]] && printf '%s\n' "${result[@]}"
    return 0
  }
  _migrate_extra_ids() {
    # Map old extra IDs to current ones
    local -a migrated=()
    for id in "$@"; do
      case "$id" in
        skill-ema-standards) migrated+=("skill") ;;
        skill-dv-export)     migrated+=("dataverse-skill") ;;
        *)                   migrated+=("$id") ;;
      esac
    done
    [[ ${#migrated[@]} -gt 0 ]] && printf '%s\n' "${migrated[@]}"
    return 0
  }
  while IFS='=' read -r key val; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    key="${key//[[:space:]]/}"
    [[ -z "$key" ]] && continue
    val="${val## }"; val="${val%% }"
    case "$key" in
      tools)
        if [[ -n "$val" ]]; then
          SELECTED_TOOLS=()
          while IFS= read -r _item; do SELECTED_TOOLS+=("$_item"); done < <(_parse_csv_or_space "$val")
        fi ;;
      languages)
        if [[ -n "$val" ]]; then
          SELECTED_LANGS=()
          while IFS= read -r _item; do SELECTED_LANGS+=("$_item"); done < <(_parse_csv_or_space "$val")
        fi ;;
      copilot_extras)
        if [[ -n "$val" ]]; then
          local -a _raw_extras=()
          while IFS= read -r _item; do _raw_extras+=("$_item"); done < <(_parse_csv_or_space "$val")
          SELECTED_EXTRAS=()
          while IFS= read -r _item; do SELECTED_EXTRAS+=("$_item"); done < <(_migrate_extra_ids "${_raw_extras[@]+"${_raw_extras[@]}"}")
        fi ;;
      copilot_agent_ide)
        COPILOT_AGENT_IDE="${val:-vscode}" ;;
    esac
  done < "$CONFIG_FILE"
  return 0
}

configure() {
  echo ""
  echo "==================================================================="
  echo "  sync-ai-configs: Select what to generate"
  echo "  Config saved to .sync-ai-configs -- commit it to share with team."
  echo "  To reconfigure: delete .sync-ai-configs or pass --reconfigure"
  echo "==================================================================="
  echo ""
  echo "  Which AI tools does your team use?"
  _MENU_IDS=("${TOOL_IDS[@]}"); _MENU_LABELS=("${TOOL_LABELS[@]}")
  _select_from_menu SELECTED_TOOLS

  echo ""
  echo "  Which languages does this project use?"
  _MENU_IDS=("${LANG_IDS[@]}"); _MENU_LABELS=("${LANG_LABELS[@]}")
  _select_from_menu SELECTED_LANGS

  if has_tool "copilot" || has_tool "codex" || has_tool "cursor" || has_tool "jetbrains" || has_tool "junie"; then
    echo ""
    echo "  Extras to generate? (agents/prompts are Copilot-only; skills apply to all tools)"
    _MENU_IDS=("${EXTRA_IDS[@]}"); _MENU_LABELS=("${EXTRA_LABELS[@]}")
    _select_from_menu SELECTED_EXTRAS
  fi

  if has_tool "copilot" && has_extra "agents"; then
    echo ""
    echo "  Which IDE will your team use with GitHub Copilot agents?"
    echo "    1) VS Code"
    echo "    2) JetBrains (IntelliJ, PyCharm, Rider, WebStorm)"
    echo "    3) Visual Studio (Windows) -- requires VS 2026 17.14+ preview"
    read -rp "  > [1] " _ide_answer
    case "$_ide_answer" in
      2) COPILOT_AGENT_IDE="jetbrains" ;;
      3) COPILOT_AGENT_IDE="visualstudio" ;;
      *) COPILOT_AGENT_IDE="vscode" ;;
    esac
    echo "  Copilot agent IDE set to: $COPILOT_AGENT_IDE"
  fi

  echo ""
  read -rp "  Is this a new project (cloned from the template)? [y/N] " _new_proj_answer
  if [[ "$(_to_lower "$_new_proj_answer")" == "y" ]]; then
    NEW_PROJECT=true
  else
    NEW_PROJECT=false
  fi

  echo ""
  save_config
}

# Track generated files for summary
GENERATED_FILES=()
KEPT_FILES=()

# Set to true by --all so write_file auto-replaces without prompting
SYNC_GENERATE_ALL=false

###############################################################################
# Helpers
###############################################################################

HEADER_COMMENT='<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->
<!-- Edit the source files in docs/ai-guidelines/ instead.    -->'

ensure_dir() {
  mkdir -p "$1"
}

# Read a source file; warn and return empty string if missing.
read_source() {
  local path="$DOCS_DIR/$1"
  if [[ -f "$path" ]]; then
    cat "$path"
  else
    echo "[sync-ai-configs] WARNING: source file missing: $1" >&2
    echo ""
  fi
}

# Check whether a source file exists.
source_exists() {
  [[ -f "$DOCS_DIR/$1" ]]
}

# Interactive choice when a manually-edited file conflicts with generated content.
# Sets SYNC_CHOICE to "r" (replace) or "k" (keep).
# Defaults to "k" (keep) in non-interactive mode.
sync_interactive_choice() {
  local rel="$1"
  local tgt_file="$2"
  local new_content="$3"

  SYNC_CHOICE="k"  # safe default

  # --all: auto-replace without prompting
  if $SYNC_GENERATE_ALL; then
    SYNC_CHOICE="r"
    return
  fi

  # Non-interactive (CI / piped): keep by default
  if [ ! -t 0 ]; then
    return
  fi

  echo ""
  echo "  [conflict] $rel -- file exists and differs from generated version"
  while true; do
    local choice
    read -r -p "    (r)eplace with generated / (k)eep existing / (m)erge -- show diff? " choice || {
      SYNC_CHOICE="k"
      return
    }
    case "$choice" in
      r|R)
        SYNC_CHOICE="r"
        return
        ;;
      k|K)
        SYNC_CHOICE="k"
        return
        ;;
      m|M)
        echo ""
        local tmpfile
        tmpfile="$(mktemp)"
        printf '%s\n' "$new_content" > "$tmpfile"
        local rc=0
        diff --color -u "$tgt_file" "$tmpfile" 2>/dev/null || rc=$?
        if [ "$rc" -gt 1 ]; then
          diff -u "$tgt_file" "$tmpfile" || true
        fi
        rm -f "$tmpfile"
        echo ""
        # Loop back to prompt
        ;;
      *)
        echo "    Please enter r, k, or m."
        ;;
    esac
  done
}

write_file() {
  local relpath="$1"
  local content="$2"
  local filepath="$PROJECT_ROOT/$relpath"

  if [[ -f "$filepath" ]]; then
    local is_auto=false
    if head -5 "$filepath" | grep -q "AUTO-GENERATED"; then
      is_auto=true
    fi

    # Check if content actually differs by comparing via temp file.
    # Using cmp avoids the $() trailing-newline-stripping pitfall.
    local tmpfile
    tmpfile="$(mktemp)"
    printf '%s\n' "$content" > "$tmpfile"
    if cmp -s "$filepath" "$tmpfile"; then
      rm -f "$tmpfile"
      echo "  [unchanged] $relpath"
      return
    fi
    rm -f "$tmpfile"

    if $is_auto; then
      # Auto-generated: check if differences are whitespace-only
      local _wstmp
      _wstmp="$(mktemp)"
      printf '%s\n' "$content" > "$_wstmp"
      if diff -q <(sed 's/[[:space:]]*$//' "$filepath") <(sed 's/[[:space:]]*$//' "$_wstmp") >/dev/null 2>&1; then
        # Only whitespace/formatting differences -- replace silently
        rm -f "$_wstmp"
        ensure_dir "$(dirname "$filepath")"
        printf '%s\n' "$content" > "$filepath"
        GENERATED_FILES+=("$relpath")
        echo "  [updated] $relpath"
      else
        # Real content differences -- prompt for confirmation
        rm -f "$_wstmp"
        sync_interactive_choice "$relpath" "$filepath" "$content"
        case "$SYNC_CHOICE" in
          r)
            ensure_dir "$(dirname "$filepath")"
            printf '%s\n' "$content" > "$filepath"
            GENERATED_FILES+=("$relpath")
            echo "  [updated] $relpath"
            ;;
          k)
            KEPT_FILES+=("$relpath")
            echo "  [kept] $relpath"
            ;;
        esac
      fi
    else
      # Not auto-generated -- prompt for confirmation
      sync_interactive_choice "$relpath" "$filepath" "$content"
      case "$SYNC_CHOICE" in
        r)
          ensure_dir "$(dirname "$filepath")"
          printf '%s\n' "$content" > "$filepath"
          GENERATED_FILES+=("$relpath")
          echo "  [replaced] $relpath"
          ;;
        k)
          KEPT_FILES+=("$relpath")
          echo "  [kept] $relpath (not auto-generated -- delete file to regenerate)"
          ;;
      esac
    fi
    return
  fi

  # New file -- create it
  ensure_dir "$(dirname "$filepath")"
  printf '%s\n' "$content" > "$filepath"
  GENERATED_FILES+=("$relpath")
  echo "  [ok] $relpath"
}

# Parse language entry fields.
lang_slug()   { echo "${1%%|*}"; }
lang_name()   { local tmp="${1#*|}"; echo "${tmp%%|*}"; }
lang_globs()  { echo "${1##*|}"; }

# Convert comma-separated globs to YAML list: ["g1", "g2"]
globs_to_yaml_list() {
  local -a parts
  IFS=',' read -ra parts <<< "$1"
  local out='['
  local first=true
  for g in "${parts[@]}"; do
    if $first; then first=false; else out+=', '; fi
    out+="\"$g\""
  done
  out+=']'
  echo "$out"
}

# Convert comma-separated globs to a plain comma-separated string for
# GitHub instructions frontmatter applyTo field.
# Input:  **/*.js,**/*.jsx   Output: **/*.js,**/*.jsx
globs_to_csv() {
  echo "$1"
}

# Extract gitignore code fence from ignore-patterns.md
extract_ignore_patterns() {
  local file="$DOCS_DIR/ignore-patterns.md"
  if [[ ! -f "$file" ]]; then
    echo "[sync-ai-configs] WARNING: ignore-patterns.md not found" >&2
    echo ""
    return
  fi
  # Extract content between the FIRST ```gitignore and the next ```
  sed -n '/^```gitignore/,/^```/{/^```/d;p;}' "$file"
}

###############################################################################
# Concatenated core content (index + general-rules + security + testing)
# Note: CLAUDE.md and Junie additionally append pilot-metrics + language files.
###############################################################################

core_content() {
  local policy_index general security testing
  policy_index="$(read_source index.md)"
  general="$(read_source general-rules.md)"
  security="$(read_source security-and-compliance.md)"
  testing="$(read_source testing.md)"

  local result=""
  for part in "$policy_index" "$general" "$security" "$testing"; do
    if [[ -n "$part" ]]; then
      [[ -n "$result" ]] && result+=$'\n\n'
      result+="$part"
    fi
  done
  echo "$result"
}

###############################################################################
# Language examples from docs/wiki/examples/
###############################################################################

WIKI_EXAMPLES_DIR="$PROJECT_ROOT/docs/wiki/Examples"

# Map language slug to wiki example filename (only non-trivial mappings)
example_filename_for_slug() {
  case "$1" in
    javascript-typescript) echo "TypeScript.md" ;;
    *)                     echo "$1.md" ;;
  esac
}

# Read language guidelines + optional wiki examples
read_lang_content() {
  local slug="$1"
  local content=""
  content="$(read_source "${slug}.md")"

  local example_file
  example_file="$WIKI_EXAMPLES_DIR/$(example_filename_for_slug "$slug")"
  if [[ -f "$example_file" ]]; then
    local examples
    examples="$(cat "$example_file")"
    if [[ -n "$examples" ]]; then
      content+=$'\n\n'"$examples"
    fi
  fi
  echo "$content"
}

###############################################################################
# Skills summary (shared across generators)
###############################################################################

build_skills_summary() {
  local skills_lines=""
  # ema-standards skill (generated from core content)
  if has_extra "skill"; then
    skills_lines+=$'\n'"- **ema-standards** -- Apply EMA coding standards and security guidelines to code review and generation"
  fi
  # Scan docs/ai-guidelines/skills/*/SKILL.md for additional skills
  local skill_src_dir
  for skill_src_dir in "$DOCS_DIR/skills"/*/; do
    [[ ! -d "$skill_src_dir" ]] && continue
    local skill_md="$skill_src_dir/SKILL.md"
    [[ ! -f "$skill_md" ]] && continue
    local sname sdesc
    sname="$(sed -n 's/^name: *//p' "$skill_md" | head -1)"
    sdesc="$(sed -n 's/^description: *//p' "$skill_md" | head -1 | sed 's/^"//;s/"$//')"
    # Skip ema-standards (handled above) and unselected extras
    [[ "$sname" == "ema-standards" ]] && continue
    local extra_id
    case "$sname" in
      dataverse-metadata-export) extra_id="dataverse-skill" ;;
      *)                         extra_id="$sname" ;;
    esac
    if ! has_extra "$extra_id"; then continue; fi
    if [[ -n "$sname" ]]; then
      skills_lines+=$'\n'"- **${sname}** -- ${sdesc}"
    fi
  done
  if [[ -n "$skills_lines" ]]; then
    printf '%s' "# Available Skills

The following skills are available for your AI tools. Each tool receives a self-contained copy with scripts and references. Read the skill's \`SKILL.md\` for full usage instructions.
${skills_lines}"
  fi
}

###############################################################################
# Generators
###############################################################################

generate_ai_sync_md() {
  local fence='```'
  local content
  content="${HEADER_COMMENT}

# AI Config Sync

This project uses the **EMA AI Scaffolding** to generate AI tool configurations (Copilot agents, prompt files, coding standards, etc.) from a single source of truth.

## How to Re-Sync

Run this command from the **project root** whenever you want to regenerate all AI configs:

**Windows (PowerShell):**
${fence}powershell
pwsh scripts/sync-ai-configs.ps1
${fence}

**macOS / Linux (bash):**
${fence}bash
bash scripts/sync-ai-configs.sh
${fence}

The script reads your saved config (\`.sync-ai-configs\`) and regenerates all files automatically.

## Common Options

| Flag | What it does |
|---|---|
| *(no flags)* | Re-generate using saved config -- the default |
| \`--reconfigure\` | Change which tools, languages, or extras are enabled |
| \`--ide=IDE\` | Switch agent IDE (vscode, jetbrains, visualstudio) and re-save config |
| \`--all\` | Generate for all tools and languages (useful for CI) |
| \`--wiki-only\` | Regenerate only the \`docs/wiki/Reference/\` pages |
| \`--clean\` | Remove all generated files (dry run for a fresh setup) |

## What Gets Generated

All generated files have this header:

${fence}
<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->
${fence}

**Do not edit generated files directly** -- your changes will be overwritten on the next sync. Edit the source files in \`docs/ai-guidelines/\` instead, then re-run the sync.

## Updating the Scaffolding

To pull in the latest EMA scaffolding improvements:

${fence}bash
# SSH
git clone --depth=1 git@ssh.dev.azure.com:v3/euemadev/IRISplatform/EMA.AI.Scaffolding .ema-scaffold
# HTTPS
git clone --depth=1 https://euemadev@dev.azure.com/euemadev/IRISplatform/_git/EMA.AI.Scaffolding .ema-scaffold

bash .ema-scaffold/scripts/setup-existing-project.sh
rm -rf .ema-scaffold
${fence}"
  write_file "AI-SYNC.md" "$content"
}

generate_claude_md() {
  local content="$cached_core_content"

  # Append selected language convention files ONLY (no worked examples).
  # Claude Code can read docs/wiki/examples/ on demand -- inlining them
  # bloats CLAUDE.md past the performance threshold.
  local lang_slugs=()
  for entry in "${LANGUAGES[@]}"; do
    lang_slugs+=("$(lang_slug "$entry")")
  done
  if [[ ${#lang_slugs[@]} -gt 0 ]]; then
    local -a sorted
    sorted=()
    while IFS= read -r _item; do sorted+=("$_item"); done < <(sort <<<"${lang_slugs[*]}")
    for slug in "${sorted[@]}"; do
      if source_exists "${slug}.md"; then
        local lc
        lc="$(read_source "${slug}.md")"
        if [[ -n "$lc" ]]; then
          content+=$'\n\n'"$lc"
        fi
      fi
    done
  fi

  # Add a reference note so Claude Code knows where to find examples
  content+=$'\n\n'"# Worked Examples

For language-specific worked examples (prompts, expected output, review checklists), see the files in \`docs/wiki/Examples/\`. Read them on demand when generating, reviewing, or refactoring code in a specific language."

  # Append skills summary
  if [[ -n "$cached_skills_summary" ]]; then
    content+=$'\n\n'"$cached_skills_summary"
  fi

  local output="${HEADER_COMMENT}

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

${content}"
  write_file "CLAUDE.md" "$output"
}

generate_agents_md() {
  local content="$cached_core_content"
  if [[ -n "$cached_skills_summary" ]]; then
    content+=$'\n\n'"$cached_skills_summary"
  fi
  local output="${HEADER_COMMENT}

${content}"
  write_file "AGENTS.md" "$output"
}

generate_copilot_instructions() {
  local content="$cached_core_content"
  if [[ -n "$cached_skills_summary" ]]; then
    content+=$'\n\n'"$cached_skills_summary"
  fi
  local output="${HEADER_COMMENT}

${content}"
  write_file ".github/copilot-instructions.md" "$output"
}

generate_copilot_language_instructions() {
  for entry in "${LANGUAGES[@]}"; do
    local slug name globs lang_content csv
    slug="$(lang_slug "$entry")"
    name="$(lang_name "$entry")"
    globs="$(lang_globs "$entry")"

    if ! source_exists "${slug}.md"; then
      echo "[sync-ai-configs] WARNING: ${slug}.md not found, skipping copilot language instruction" >&2
      continue
    fi

    lang_content="$(read_lang_content "$slug")"
    csv="$(globs_to_csv "$globs")"

    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
applyTo: \"${csv}\"
---
${HEADER_COMMENT}

${lang_content}"
    write_file ".github/instructions/${slug}.instructions.md" "$output"
  done
}

generate_cursor_general() {
  local content="$cached_core_content"
  if [[ -n "$cached_skills_summary" ]]; then
    content+=$'\n\n'"$cached_skills_summary"
  fi
  local output='---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
description: "General AI coding standards, security, and testing guidelines"
alwaysApply: true
---
'"${content}"
  write_file ".cursor/rules/general.mdc" "$output"
}

generate_cursor_language_rules() {
  for entry in "${LANGUAGES[@]}"; do
    local slug name globs lang_content yaml_globs
    slug="$(lang_slug "$entry")"
    name="$(lang_name "$entry")"
    globs="$(lang_globs "$entry")"

    if ! source_exists "${slug}.md"; then
      echo "[sync-ai-configs] WARNING: ${slug}.md not found, skipping cursor rule" >&2
      continue
    fi

    lang_content="$(read_lang_content "$slug")"
    yaml_globs="$(globs_to_yaml_list "$globs")"

    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
description: \"${name} coding conventions\"
globs: ${yaml_globs}
alwaysApply: false
---
${lang_content}"
    write_file ".cursor/rules/${slug}.mdc" "$output"
  done
}

generate_aiassistant_general() {
  local content="$cached_core_content"
  if [[ -n "$cached_skills_summary" ]]; then
    content+=$'\n\n'"$cached_skills_summary"
  fi
  local output="${HEADER_COMMENT}

${content}"
  write_file ".aiassistant/rules/general-standards.md" "$output"
}

generate_aiassistant_language_rules() {
  for entry in "${LANGUAGES[@]}"; do
    local slug lang_content
    slug="$(lang_slug "$entry")"

    if ! source_exists "${slug}.md"; then
      echo "[sync-ai-configs] WARNING: ${slug}.md not found, skipping aiassistant rule" >&2
      continue
    fi

    lang_content="$(read_lang_content "$slug")"

    local output="${HEADER_COMMENT}

${lang_content}"
    write_file ".aiassistant/rules/${slug}.md" "$output"
  done
}

generate_junie_guidelines() {
  local content="$cached_core_content"

  # Collect all language files alphabetically
  local lang_slugs=()
  for entry in "${LANGUAGES[@]+"${LANGUAGES[@]}"}"; do
    lang_slugs+=("$(lang_slug "$entry")")
  done

  local all_lang_content=""
  if [[ ${#lang_slugs[@]} -gt 0 ]]; then
    # Sort alphabetically
    local -a sorted=()
    while IFS= read -r _item; do sorted+=("$_item"); done < <(sort <<<"${lang_slugs[*]}")

    for slug in "${sorted[@]}"; do
    if source_exists "${slug}.md"; then
      local lc
      lc="$(read_lang_content "$slug")"
      if [[ -n "$lc" ]]; then
        all_lang_content+=$'\n\n'"$lc"
      fi
    fi
  done
  fi

  if [[ -n "$cached_skills_summary" ]]; then
    all_lang_content+=$'\n\n'"$cached_skills_summary"
  fi

  local output="${HEADER_COMMENT}

${content}${all_lang_content}"
  write_file ".junie/guidelines.md" "$output"
}

generate_custom_agents() {
  local agents_src_dir="$DOCS_DIR/agents"
  if [[ ! -d "$agents_src_dir" ]]; then
    echo "[sync-ai-configs] WARNING: docs/ai-guidelines/agents/ not found, skipping custom agents" >&2
    return
  fi

  local content="$cached_core_content"
  if [[ -n "$cached_skills_summary" ]]; then
    content+=$'\n\n'"$cached_skills_summary"
  fi
  local policy_index security_content security_scope
  policy_index="$(read_source index.md)"
  security_content="$(read_source security-and-compliance.md)"
  # "security" scope = policy index + security-and-compliance (no general-rules or testing)
  security_scope=""
  if [[ -n "$policy_index" ]]; then security_scope="$policy_index"; fi
  if [[ -n "$security_content" ]]; then
    [[ -n "$security_scope" ]] && security_scope+=$'\n\n'
    security_scope+="$security_content"
  fi
  if [[ -n "$cached_skills_summary" ]]; then
    security_scope+=$'\n\n'"$cached_skills_summary"
  fi

  # Read pipeline overview (agents/README.md) -- shared across non-brainstormer agents
  local pipeline_overview=""
  if [[ -f "$agents_src_dir/README.md" ]]; then
    pipeline_overview="$(cat "$agents_src_dir/README.md")"
  fi

  # Tool lists and model format vary by IDE -- set variables based on COPILOT_AGENT_IDE
  local tools_none tools_brainstormer tools_read tools_write tools_tester tools_reviewer tools_debugger tools_consolidator
  local tools_security model_security tools_backlog_manager model_backlog_manager
  local model_dispatcher model_brainstormer model_architect model_planner model_planner_lite
  local model_impl model_impl_lite model_tester model_reviewer model_debugger model_consolidator
  tools_none="[]"
  if [[ "$COPILOT_AGENT_IDE" == "jetbrains" ]]; then
    # All JetBrains agents get the full built-in tool set
    local _jb_all="['insert_edit_into_file', 'replace_string_in_file', 'create_file', 'apply_patch', 'get_terminal_output', 'show_content', 'open_file', 'run_in_terminal', 'get_errors', 'list_dir', 'read_file', 'file_search', 'grep_search', 'validate_cves', 'run_subagent']"
    tools_brainstormer="$_jb_all"
    tools_read="$_jb_all"
    tools_write="$_jb_all"
    tools_tester="$_jb_all"
    tools_reviewer="$_jb_all"
    tools_debugger="$_jb_all"
    tools_security="$_jb_all"
    tools_consolidator="$_jb_all"
    tools_backlog_manager="$_jb_all"
    model_dispatcher="model: 'GPT-5 mini'"
    model_brainstormer="model: 'GPT-5 mini'"
    model_architect="model: 'Claude Opus 4.6'"
    model_planner="model: 'GPT-5.4'"
    model_planner_lite="model: 'Gemini 3 Flash'"
    model_impl="model: 'GPT-5.4'"
    model_impl_lite="model: 'Gemini 3 Flash'"
    model_tester="model: 'GPT-5.4'"
    model_reviewer="model: 'Claude Sonnet 4.6'"
    model_debugger="model: 'GPT-5.4'"
    model_security="model: 'GPT-5.4'"
    model_consolidator="model: 'Gemini 3 Flash'"
    model_backlog_manager="model: 'GPT-5.4'"
  elif [[ "$COPILOT_AGENT_IDE" == "visualstudio" ]]; then
    # All Visual Studio agents get the full tool set (canonical + VS-specific)
    local _vs_all="['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'code_search', 'readfile', 'editfiles', 'find_references', 'runcommandinterminal', 'getwebpages', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
    tools_brainstormer="$_vs_all"
    tools_read="$_vs_all"
    tools_write="$_vs_all"
    tools_tester="$_vs_all"
    tools_reviewer="$_vs_all"
    tools_debugger="$_vs_all"
    tools_security="$_vs_all"
    tools_consolidator="$_vs_all"
    tools_backlog_manager="$_vs_all"
    model_dispatcher="model: 'GPT-5 mini'"
    model_brainstormer="model: 'GPT-5 mini'"
    model_architect="model: 'Claude Opus 4.6'"
    model_planner="model: 'GPT-5.4'"
    model_planner_lite="model: 'Gemini 3 Flash'"
    model_impl="model: 'GPT-5.4'"
    model_impl_lite="model: 'Gemini 3 Flash'"
    model_tester="model: 'GPT-5.4'"
    model_reviewer="model: 'Claude Sonnet 4.6'"
    model_debugger="model: 'GPT-5.4'"
    model_security="model: 'GPT-5.4'"
    model_consolidator="model: 'Gemini 3 Flash'"
    model_backlog_manager="model: 'GPT-5.4'"
  else
    # All VS Code agents get the full tool set (canonical + VS Code-specific)
    local _vsc_all="['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo', 'codebase', 'githubRepo', 'runTests', 'problems', 'changes', 'usages', 'fileSearch', 'textSearch', 'terminalLastCommand', 'azure-devops/*']"
    tools_brainstormer="$_vsc_all"
    tools_read="$_vsc_all"
    tools_write="$_vsc_all"
    tools_tester="$_vsc_all"
    tools_reviewer="$_vsc_all"
    tools_debugger="$_vsc_all"
    tools_security="$_vsc_all"
    tools_consolidator="$_vsc_all"
    tools_backlog_manager="$_vsc_all"
    model_dispatcher="model: 'GPT-5 mini'"
    model_brainstormer="model: 'GPT-5 mini'"
    model_architect="model: 'Claude Opus 4.6'"
    model_planner="model: 'GPT-5.4'"
    model_planner_lite="model: 'Gemini 3 Flash'"
    model_impl="model: 'GPT-5.4'"
    model_impl_lite="model: 'Gemini 3 Flash'"
    model_tester="model: 'GPT-5.4'"
    model_reviewer="model: 'Claude Sonnet 4.6'"
    model_debugger="model: 'GPT-5.4'"
    model_security="model: 'GPT-5.4'"
    model_consolidator="model: 'Gemini 3 Flash'"
    model_backlog_manager="model: 'GPT-5.4'"
  fi

  # --- ema (dispatcher) ---
  if [[ -f "$agents_src_dir/ema-starter.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-starter.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-starter\"
description: \"Smart dispatcher -- classifies your request and routes to the right agent pipeline\"
argument-hint: \"Describe your request (a vague idea, a feature to build, a bug to fix, or code to review)\"
${model_dispatcher}
tools: ${tools_none}
agents: ['ema-backlog-manager', 'ema-brainstormer', 'ema-architect', 'ema-planner-lite', 'ema-debugger', 'ema-reviewer', 'ema-security', 'ema-metrics-consolidator']
handoffs:
  - label: \"Backlog\"
    agent: ema-backlog-manager
    prompt: \"Here is the idea. Search the project wiki for relevant context, decompose it into a SAFe hierarchy (Epics, Features, User Stories/Enablers, Tasks), save the backlog to backlog/<YYYY-MM-DD>-<slug>.json, print a summary table, and ask whether to refine further or push to ADO.\"
  - label: \"Brainstorm\"
    agent: ema-brainstormer
    prompt: \"Here is my idea. Explore the codebase to understand existing patterns and constraints, then work through requirements with me via conversation -- propose approaches, challenge assumptions, and flag risks. Confirm the summary with me before producing the final requirements document saved to artifacts/<YYYY-MM-DD>-<topic>-requirements.md with a Handoff section for the next agent.\"
  - label: \"Architect\"
    agent: ema-architect
    prompt: \"Here is the request. Explore the codebase, evaluate 2-3 design approaches, produce an architecture design document saved to artifacts/<YYYY-MM-DD>-<topic>-architecture.md, and include a Handoff section for @ema-planner.\"
  - label: \"Quick plan\"
    agent: ema-planner-lite
    prompt: \"Here is the request. Read the affected files, produce a concise implementation plan saved to artifacts/<YYYY-MM-DD>-<topic>-plan.md, and include a Handoff section for @ema-implementer-lite.\"
  - label: \"Debug\"
    agent: ema-debugger
    prompt: \"Here is the bug report. Run the full reproduce → isolate → root-cause → fix → verify cycle, save the debug report to artifacts/<YYYY-MM-DD>-<topic>-debug-report.md, and include a Handoff section for @ema-tester.\"
  - label: \"Review\"
    agent: ema-reviewer
    prompt: \"Review the changed code against EMA guidelines. Read the plan and implementation artifacts from artifacts/ if they exist. Save the review report to artifacts/<YYYY-MM-DD>-<topic>-review-report.md and include a Pipeline Recap section.\"
  - label: \"Security Audit\"
    agent: ema-security
    prompt: \"Run a comprehensive security audit. Complete all four phases (reconnaissance, dependency CVE scan, code pattern analysis, infrastructure review). Save the security report to artifacts/<YYYY-MM-DD>-<topic>-security-report.md.\"
  - label: \"Consolidate Metrics\"
    agent: ema-metrics-consolidator
    prompt: \"Consolidate the .metrics/ usage log. Read all rows, group related entries by category and task similarity, and produce fewer, richer rows.\"
---
${HEADER_COMMENT}

${agent_instructions}

${pipeline_overview}"
    write_file ".github/agents/ema-starter.agent.md" "$output"
  fi

  # --- ema-backlog-manager ---
  if [[ -f "$agents_src_dir/ema-backlog-manager.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-backlog-manager.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-backlog-manager\"
description: \"SAFe backlog expert -- generate, refine, and publish structured Azure DevOps backlogs from natural language ideas\"
argument-hint: \"Describe your idea, provide a backlog/*.json file to refine, or provide an ADO work item ID/URL to review\"
${model_backlog_manager}
tools: ${tools_backlog_manager}
agents: []
handoffs: []
---
${HEADER_COMMENT}

${agent_instructions}"
    write_file ".github/agents/ema-backlog-manager.agent.md" "$output"
  fi

  # --- ema-brainstormer ---
  if [[ -f "$agents_src_dir/ema-brainstormer.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-brainstormer.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-brainstormer\"
description: \"Explore codebase, brainstorm with the user, then produce structured requirements\"
argument-hint: \"Describe your idea or the problem you want to solve\"
${model_brainstormer}
tools: ${tools_brainstormer}
agents: ['ema-architect', 'ema-planner-lite']
handoffs:
  - label: \"Architect\"
    agent: ema-architect
    prompt: \"Read the Handoff section above for the requirements artifact path and context. Explore the codebase using the requirements as your guide, evaluate 2-3 design approaches, produce an architecture design document saved to artifacts/<YYYY-MM-DD>-<topic>-architecture.md, and include a Handoff section for @ema-planner.\"
  - label: \"Plan (quick)\"
    agent: ema-planner-lite
    prompt: \"Read the Handoff section above for the requirements artifact path and context. Read the affected files, produce a concise implementation plan saved to artifacts/<YYYY-MM-DD>-<topic>-plan.md, and include a Handoff section for @ema-implementer-lite.\"
---
${HEADER_COMMENT}

${agent_instructions}

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

${security_scope}"
    write_file ".github/agents/ema-brainstormer.agent.md" "$output"
  fi

  # --- ema-architect ---
  if [[ -f "$agents_src_dir/ema-architect.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-architect.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-architect\"
description: \"Explore the codebase, evaluate design options, and produce an architecture design document\"
argument-hint: \"Describe the feature to design, or provide the requirements path (e.g. artifacts/YYYY-MM-DD-topic-requirements.md)\"
${model_architect}
tools: ${tools_read}
agents: ['ema-planner']
handoffs:
  - label: \"Plan\"
    agent: ema-planner
    prompt: \"Read the Handoff section above for the architecture artifact path, upstream artifact paths, and key context (chosen approach, files to create/modify, integration points). Verify those files exist in the codebase, then produce a detailed step-by-step plan saved to artifacts/<YYYY-MM-DD>-<topic>-plan.md, and include a Handoff section for @ema-implementer.\"
---
${HEADER_COMMENT}

${agent_instructions}

${pipeline_overview}

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

${content}"
    write_file ".github/agents/ema-architect.agent.md" "$output"
  fi

  # --- ema-planner ---
  if [[ -f "$agents_src_dir/ema-planner.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-planner.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-planner\"
description: \"Produce a detailed step-by-step implementation plan from an architecture design\"
argument-hint: \"Provide the architecture document path (e.g. artifacts/YYYY-MM-DD-topic-architecture.md)\"
${model_planner}
tools: ${tools_read}
agents: ['ema-implementer']
handoffs:
  - label: \"Implement\"
    agent: ema-implementer
    prompt: \"Read the Handoff section above for the plan artifact path, all upstream artifacts (architecture, requirements), step count, files to create/modify, test command, and any watch-for notes. Execute all plan steps (test after each, stage changes but do NOT commit -- leave committing to the user), save the implementation summary to artifacts/<YYYY-MM-DD>-<topic>-implementation.md, and include a Handoff section for @ema-tester.\"
---
${HEADER_COMMENT}

${agent_instructions}

${pipeline_overview}

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

${content}"
    write_file ".github/agents/ema-planner.agent.md" "$output"
  fi

  # --- ema-planner-lite ---
  if [[ -f "$agents_src_dir/ema-planner-lite.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-planner-lite.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-planner-lite\"
description: \"Quick planning for simple changes -- bug fixes, small features, config changes\"
argument-hint: \"Describe the change to plan (bug fix, small feature, config change) or provide the requirements path\"
${model_planner_lite}
tools: ${tools_read}
agents: ['ema-implementer-lite']
handoffs:
  - label: \"Implement\"
    agent: ema-implementer-lite
    prompt: \"Read the Handoff section above for the plan artifact path, files affected, test command, and watch-for notes. Execute all steps (test after each, stage changes but do NOT commit -- leave committing to the user), save the implementation summary to artifacts/<YYYY-MM-DD>-<topic>-implementation.md, and include a Handoff section for @ema-tester.\"
---
${HEADER_COMMENT}

${agent_instructions}

${pipeline_overview}

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

${content}"
    write_file ".github/agents/ema-planner-lite.agent.md" "$output"
  fi

  # --- ema-implementer-lite ---
  if [[ -f "$agents_src_dir/ema-implementer-lite.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-implementer-lite.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-implementer-lite\"
description: \"Lightweight implementation for simple changes -- executes short plans from planner-lite\"
argument-hint: \"Provide the plan document path (e.g. artifacts/YYYY-MM-DD-topic-plan.md)\"
${model_impl_lite}
tools: ${tools_write}
agents: ['ema-tester']
handoffs:
  - label: \"Test\"
    agent: ema-tester
    prompt: \"Read the Handoff section above for the implementation artifact path, all upstream artifacts (plan, requirements), files changed, current test results, and areas needing extra coverage. Test from the SPEC (requirements), not from the code. Write additional tests, run the full suite, save the test report to artifacts/<YYYY-MM-DD>-<topic>-test-report.md, and include a Handoff section for @ema-reviewer.\"
---
${HEADER_COMMENT}

${agent_instructions}

${pipeline_overview}

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

${content}"
    write_file ".github/agents/ema-implementer-lite.agent.md" "$output"
  fi

  # --- ema-implementer ---
  if [[ -f "$agents_src_dir/ema-implementer.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-implementer.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-implementer\"
description: \"Execute an implementation plan step-by-step -- writing code, running tests, staging changes\"
argument-hint: \"Provide the plan document path (e.g. artifacts/YYYY-MM-DD-topic-plan.md)\"
${model_impl}
tools: ${tools_write}
agents: ['ema-tester']
handoffs:
  - label: \"Test\"
    agent: ema-tester
    prompt: \"Read the Handoff section above for the implementation artifact path, all upstream artifacts (plan, architecture, requirements), files changed, current test results, and areas needing extra coverage. Test from the SPEC (requirements), not from the code. Write additional tests, run the full suite, save the test report to artifacts/<YYYY-MM-DD>-<topic>-test-report.md, and include a Handoff section for @ema-reviewer.\"
---
${HEADER_COMMENT}

${agent_instructions}

${pipeline_overview}

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

${content}"
    write_file ".github/agents/ema-implementer.agent.md" "$output"
  fi

  # --- ema-tester ---
  if [[ -f "$agents_src_dir/ema-tester.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-tester.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-tester\"
description: \"Write tests from the spec, run the full test suite, verify coverage and quality\"
argument-hint: \"Provide the implementation summary path (e.g. artifacts/YYYY-MM-DD-topic-implementation.md), or describe what was implemented\"
${model_tester}
tools: ${tools_tester}
agents: ['ema-reviewer']
handoffs:
  - label: \"Review\"
    agent: ema-reviewer
    prompt: \"Read the Handoff section above for the test report artifact path, all upstream artifacts (implementation, plan, architecture, requirements), suite results, bugs found, and coverage gaps. Read the plan and architecture (if exists) to understand what was supposed to be built and why. Review ALL changed files against EMA guidelines. Save the review report to artifacts/<YYYY-MM-DD>-<topic>-review-report.md and include a Pipeline Recap section.\"
---
${HEADER_COMMENT}

${agent_instructions}

${pipeline_overview}

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

${content}"
    write_file ".github/agents/ema-tester.agent.md" "$output"
  fi

  # --- ema-reviewer ---
  if [[ -f "$agents_src_dir/ema-reviewer.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-reviewer.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-reviewer\"
description: \"Review code against EMA guidelines, check security, quality, testing, and plan adherence\"
argument-hint: \"Provide a PR number, specific file paths, or the plan document path (e.g. artifacts/YYYY-MM-DD-topic-plan.md)\"
${model_reviewer}
tools: ${tools_reviewer}
agents: ['ema-security', 'ema-metrics-consolidator']
handoffs:
  - label: \"Security Audit\"
    agent: ema-security
    prompt: \"Run a comprehensive security audit on the files reviewed above. Complete all four phases (reconnaissance, dependency CVE scan, code pattern analysis, infrastructure review). Save the security report to artifacts/<YYYY-MM-DD>-<topic>-security-report.md.\"
  - label: \"Consolidate Metrics\"
    agent: ema-metrics-consolidator
    prompt: \"Consolidate the .metrics/ usage log. Read all rows, group related entries by category and task similarity, and produce fewer, richer rows. Write the consolidated result back to both .metrics/ai-usage-log.csv and .metrics/ai-usage-log.md.\"
---
${HEADER_COMMENT}

${agent_instructions}

${pipeline_overview}

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

${content}"
    write_file ".github/agents/ema-reviewer.agent.md" "$output"
  fi

  # --- ema-debugger ---
  if [[ -f "$agents_src_dir/ema-debugger.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-debugger.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-debugger\"
description: \"Systematically debug issues -- reproduce, isolate, root-cause, fix, and verify\"
argument-hint: \"Describe the bug, paste the error message or stack trace, or describe the unexpected behavior\"
${model_debugger}
tools: ${tools_debugger}
agents: ['ema-tester', 'ema-reviewer']
handoffs:
  - label: \"Test\"
    agent: ema-tester
    prompt: \"Read the Handoff section above for the debug report artifact path, bug description, root cause, files changed, and areas to test for regressions. Confirm the reproduction test passes, write edge case and regression tests, run the full suite, save the test report to artifacts/<YYYY-MM-DD>-<topic>-test-report.md, and include a Handoff section for @ema-reviewer.\"
  - label: \"Review\"
    agent: ema-reviewer
    prompt: \"Read the Handoff section above for the debug report artifact path, bug description, root cause, and files changed. Read the debug report artifact for full context. Review the fix against EMA guidelines (security, code quality, test coverage). Save the review report to artifacts/<YYYY-MM-DD>-<topic>-review-report.md and include a Pipeline Recap section.\"
---
${HEADER_COMMENT}

${agent_instructions}

${pipeline_overview}

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

${content}"
    write_file ".github/agents/ema-debugger.agent.md" "$output"
  fi

  # --- ema-security ---
  if [[ -f "$agents_src_dir/ema-security.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-security.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-security\"
description: \"In-depth security vulnerability analysis -- dependencies, code patterns, infrastructure\"
argument-hint: \"Describe what to audit, or provide file paths / a PR number\"
${model_security}
tools: ${tools_security}
agents: []
handoffs: []
---
${HEADER_COMMENT}

${agent_instructions}

${pipeline_overview}

# EMA Coding Standards

The following EMA guidelines apply to all work performed by this agent.

${content}"
    write_file ".github/agents/ema-security.agent.md" "$output"
  fi

  # --- ema-metrics-consolidator ---
  if [[ -f "$agents_src_dir/ema-metrics-consolidator.md" ]]; then
    local agent_instructions
    agent_instructions="$(cat "$agents_src_dir/ema-metrics-consolidator.md")"
    local output="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: \"ema-metrics-consolidator\"
description: \"Consolidate .metrics/ usage log -- group related entries into fewer, richer rows\"
argument-hint: \"Consolidate the .metrics/ usage log -- group related entries by category and task similarity\"
${model_consolidator}
tools: ${tools_consolidator}
agents: []
handoffs: []
---
${HEADER_COMMENT}

${agent_instructions}"
    write_file ".github/agents/ema-metrics-consolidator.agent.md" "$output"
  fi
}

generate_copilot_setup_steps() {
  local output='# AUTO-GENERATED by sync-ai-configs.
# Customize this workflow for your project'\''s environment setup.
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
      # exported env vars) do NOT persist.'
  write_file ".github/workflows/copilot-setup-steps.yml" "$output"
}

generate_review_prompt() {
  local output='---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
description: "Review code against EMA AI development guidelines"
agent: "ask"
---
'"${HEADER_COMMENT}"'

Review the following code against the EMA coding standards. Check for:

1. **Security**: No hardcoded credentials, parameterized queries, input validation
2. **Code quality**: Readability, single responsibility, meaningful names, no deep nesting
3. **Testing**: Behavior-focused tests, descriptive names, Arrange/Act/Assert pattern
4. **Git practices**: Atomic changes, meaningful commit messages
5. **Documentation**: Comments explain WHY not WHAT, docs updated if behavior changed

Highlight any violations and suggest specific fixes.

\${selection}'
  write_file ".github/prompts/review-guidelines.prompt.md" "$output"
}

generate_tests_prompt() {
  local output='---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
description: "Generate tests following EMA testing guidelines"
agent: "agent"
---
'"${HEADER_COMMENT}"'

Generate tests for the selected code following EMA testing guidelines:

- Test behavior, not implementation
- Use descriptive names (Given/When/Then or Should format)
- One assertion concept per test
- Arrange/Act/Assert pattern
- Test edge cases: nulls, empty collections, boundary values
- Don'\''t mock what you don'\''t own -- wrap external dependencies
- Use meaningful test data variable names

\${file}'
  write_file ".github/prompts/generate-tests.prompt.md" "$output"
}

generate_backlog_prompts() {
  # 14a. generate-backlog.prompt.md
  local output='---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
agent: agent
description: "Generate a SAFe-structured backlog from a high-level idea, or refine an existing backlog JSON file."
tools: ['edit/editFiles', 'azure-devops/*']
---
'"${HEADER_COMMENT}"'

# Generate or Refine a SAFe Backlog

You are a SAFe product management expert. You operate in two modes:

- **Generate** -- decompose a new idea into a SAFe backlog hierarchy and save it as a JSON file.
- **Refine** -- load an existing backlog JSON file and improve, extend, or restructure it based on the user'\''s feedback.

## Step 0 -- Determine Mode

1. If the message references an existing file (e.g. a path starting with `backlog/`, or phrases like "refine", "update", "improve", "expand", "rework"), set mode to **Refine**.
2. Otherwise set mode to **Generate**.

## Generate mode

1. Search the project wiki (2-3 keyword queries) for relevant architecture decisions and team standards.
2. Identify initiative type: business, technical, or mixed.
3. Decompose into 1-3 Epics with Features, Stories/Enablers, and Tasks. Apply Fibonacci sizing for stories (1, 2, 3, 5, 8, 13).
4. Save to `backlog/YYYY-MM-DD-{slug}.json`.
5. Print a summary table (counts by SAFe level) and ask: *"Would you like to refine this further, or shall I push it to ADO?"*

## Refine mode

1. Read the file and show current structure (counts by type).
2. Confirm what the user wants to change unless already stated.
3. Apply changes and overwrite the same file.
4. End with: *"Anything else to refine, or are you ready to push to ADO?"*

## SAFe rules (always apply)

- Title formats: Epic `[Domain] -- [Strategic Goal]`, Feature `[Action verb] [capability]`, User Story `As a [persona], I want [goal], so that [outcome]`
- Acceptance criteria: Given/When/Then notation on all items except Tasks
- Valid status values: `not-started`, `in-progress`, `ready`, `review`, `done`, `blocked`
- Schema: `templates/safe-backlog-schema.json`'
  write_file ".github/prompts/generate-backlog.prompt.md" "$output"

  # 14b. push-to-ado.prompt.md
  output='---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
agent: agent
description: "Push a staged backlog JSON file to Azure DevOps. Creates all SAFe work items with correct hierarchy and parent-child links."
tools: ['azure-devops/*']
---
'"${HEADER_COMMENT}"'

# Push Backlog to Azure DevOps

Parse the backlog JSON file the user specified. If no file is given, list `backlog/` and ask which file to push.

## Step 1 -- Resolve Area Path and Iteration Path

Resolve in this precedence order (highest first):
1. `backlog.config.json` (workspace root, gitignored) -- read `areaPath` and `iterationPath`.
2. Root fields in the backlog JSON file.
3. Individual item field overrides.
4. Ask the user if still unresolved.

Direct the user to copy `backlog.config.example.json` to `backlog.config.json` and fill in their values.

## Step 2 -- Pre-flight summary

Print a summary table showing counts by work item type and the resolved Area Path and Iteration Path.
Ask: *"I will create N work items. Shall I proceed? (yes/no)"* -- wait for explicit confirmation.

## Step 3 -- Create work items top-down

Process items in order: Epics first, then Features, then Stories/Enablers, then Tasks.
Capture the returned ADO ID for every created item -- you need IDs to link parent-child relationships.
Establish parent-child links after all items at each level are created.

## Step 4 -- Results table

Print a results table with ADO ID, type, title, and direct URL for every created item.'
  write_file ".github/prompts/push-to-ado.prompt.md" "$output"

  # 14c. review-work-item.prompt.md
  output='---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
agent: agent
description: "Review an existing Azure DevOps work item -- fetches the item, its children, and siblings, then proposes SAFe-aligned improvements."
tools: ['azure-devops/*']
---
'"${HEADER_COMMENT}"'

# Review Existing Work Item

The user provides a work item ID or URL. If none given, ask for one.

## Step 1 -- Fetch the work item

Fetch the item, its parent, its children, and its siblings using the ADO MCP tools.
Record: type, title, description, acceptanceCriteria, storyPoints / estimatedHours, state, areaPath, iterationPath, parent ID.

## Step 2 -- Search the project wiki

Search the project wiki (2-3 keyword queries from the title/description) for architecture decisions, standards, and related components.

## Step 3 -- Structural summary

Print a context card before analysis:
```
Work Item: #<ID> -- <Title>
Type: <type>  |  State: <state>  |  Parent: #<parentId> -- <parentTitle>
Children: <N>  |  Siblings: <N>
```

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
Ask: *"Apply all, apply #N, or skip?"*'
  write_file ".github/prompts/review-work-item.prompt.md" "$output"
}

###############################################################################
# Skill generation helpers
###############################################################################

copy_source_skill() {
  local src_dir="$1" dest_dir="$2"
  if [[ -f "$src_dir/SKILL.md" ]]; then
    # Rewrite absolute paths so SKILL.md references scripts/references relative
    # to its own location, not the canonical authoring source.
    local content; content="$(cat "$src_dir/SKILL.md")"
    local skill_name; skill_name="$(basename "$src_dir")"
    content="${content//docs\/ai-guidelines\/skills\/$skill_name\//${dest_dir#./}/}"
    # Inject AUTO-GENERATED marker into YAML frontmatter so --clean can detect it.
    if [[ "$content" == ---* ]]; then
      content="${content/---/$'---\n# AUTO-GENERATED by sync-ai-configs. Do not edit directly.'}"
    else
      content="<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->
${content}"
    fi
    write_file "$dest_dir/SKILL.md" "$content"
  fi
  local f
  if [[ -d "$src_dir/scripts" ]]; then
    for f in "$src_dir/scripts/"*; do
      [[ -f "$f" ]] || continue
      local marker="# AUTO-GENERATED by sync-ai-configs. Do not edit directly."
      [[ "$f" == *.md ]] && marker="<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->"
      write_file "$dest_dir/scripts/$(basename "$f")" "${marker}
$(cat "$f")"
    done
  fi
  if [[ -d "$src_dir/references" ]]; then
    for f in "$src_dir/references/"*; do
      [[ -f "$f" ]] || continue
      local marker="<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->"
      [[ "$f" == *.py || "$f" == *.sh || "$f" == *.ps1 ]] && marker="# AUTO-GENERATED by sync-ai-configs. Do not edit directly."
      write_file "$dest_dir/references/$(basename "$f")" "${marker}
$(cat "$f")"
    done
  fi
}

skill_body() {
  # Strip YAML frontmatter (--- ... ---). If no frontmatter found, return all content.
  local first_line; first_line="$(head -1 "$1" | tr -d '\r')"
  if [[ "$first_line" == "---" ]]; then
    sed $'1{/^---\r\\{0,1\\}$/d};1,/^---\r\\{0,1\\}$/d' "$1"
  else
    cat "$1"
  fi
}

write_skill_as_cursor_rule() {
  local skill_md="$1" rule_name="$2" src_dir="$3"
  local sdesc; sdesc="$(sed -n 's/^description: *//p' "$skill_md" | head -1 | sed 's/^"//;s/"$//')"
  local body;  body="$(skill_body "$skill_md")"
  local dest_dir=".cursor/skills/${rule_name}"
  body="${body//docs\/ai-guidelines\/skills\/$rule_name\//$dest_dir/}"
  write_file ".cursor/rules/skill-${rule_name}.mdc" "---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
description: \"${sdesc}\"
alwaysApply: true
---
${body}"
  # Copy scripts and references so the skill is self-contained
  local f
  if [[ -d "$src_dir/scripts" ]]; then
    for f in "$src_dir/scripts/"*; do
      [[ -f "$f" ]] || continue
      local marker="# AUTO-GENERATED by sync-ai-configs. Do not edit directly."
      [[ "$f" == *.md ]] && marker="<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->"
      write_file "$dest_dir/scripts/$(basename "$f")" "${marker}
$(cat "$f")"
    done
  fi
  if [[ -d "$src_dir/references" ]]; then
    for f in "$src_dir/references/"*; do
      [[ -f "$f" ]] || continue
      local marker="<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->"
      [[ "$f" == *.py || "$f" == *.sh || "$f" == *.ps1 ]] && marker="# AUTO-GENERATED by sync-ai-configs. Do not edit directly."
      write_file "$dest_dir/references/$(basename "$f")" "${marker}
$(cat "$f")"
    done
  fi
}

write_skill_as_aiassistant_rule() {
  local skill_md="$1" rule_name="$2" src_dir="$3"
  local body; body="$(skill_body "$skill_md")"
  local dest_dir=".aiassistant/skills/${rule_name}"
  body="${body//docs\/ai-guidelines\/skills\/$rule_name\//$dest_dir/}"
  write_file ".aiassistant/rules/skill-${rule_name}.md" "${HEADER_COMMENT}

${body}"
  # Copy scripts and references so the skill is self-contained
  local f
  if [[ -d "$src_dir/scripts" ]]; then
    for f in "$src_dir/scripts/"*; do
      [[ -f "$f" ]] || continue
      local marker="# AUTO-GENERATED by sync-ai-configs. Do not edit directly."
      [[ "$f" == *.md ]] && marker="<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->"
      write_file "$dest_dir/scripts/$(basename "$f")" "${marker}
$(cat "$f")"
    done
  fi
  if [[ -d "$src_dir/references" ]]; then
    for f in "$src_dir/references/"*; do
      [[ -f "$f" ]] || continue
      local marker="<!-- AUTO-GENERATED by sync-ai-configs. Do not edit directly. -->"
      [[ "$f" == *.py || "$f" == *.sh || "$f" == *.ps1 ]] && marker="# AUTO-GENERATED by sync-ai-configs. Do not edit directly."
      write_file "$dest_dir/references/$(basename "$f")" "${marker}
$(cat "$f")"
    done
  fi
}

generate_all_skills() {
  local ema_desc="Apply EMA coding standards and security guidelines to code review and generation. Use this skill when reviewing code, generating new code, or refactoring existing code to ensure compliance with EMA development guidelines."

  # ema-standards: only for tools where core content is NOT already in general config
  if has_extra "skill"; then
    local ema_skill="---
# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
name: ema-standards
description: \"${ema_desc}\"
---
${HEADER_COMMENT}

${cached_core_content}"
    if has_tool "copilot"; then write_file ".github/skills/ema-standards/SKILL.md" "$ema_skill"; fi
    if has_tool "codex";   then write_file ".agents/skills/ema-standards/SKILL.md" "$ema_skill"; fi
  fi

  # Source-based skills (from docs/ai-guidelines/skills/)
  local skill_src_dir
  for skill_src_dir in "$DOCS_DIR/skills"/*/; do
    [[ -d "$skill_src_dir" ]] || continue
    local skill_name; skill_name="$(basename "$skill_src_dir")"
    [[ -f "$skill_src_dir/SKILL.md" ]] || continue
    local extra_id
    case "$skill_name" in
      dataverse-metadata-export) extra_id="dataverse-skill" ;;
      *)                         extra_id="${skill_name}" ;;
    esac
    if ! has_extra "$extra_id"; then continue; fi

    if has_tool "copilot";   then copy_source_skill "$skill_src_dir" ".github/skills/$skill_name"; fi
    if has_tool "codex";     then copy_source_skill "$skill_src_dir" ".agents/skills/$skill_name"; fi
    if has_tool "junie";     then copy_source_skill "$skill_src_dir" ".junie/skills/$skill_name"; fi
    if has_tool "cursor";    then write_skill_as_cursor_rule "$skill_src_dir/SKILL.md" "$skill_name" "$skill_src_dir"; fi
    if has_tool "jetbrains"; then write_skill_as_aiassistant_rule "$skill_src_dir/SKILL.md" "$skill_name" "$skill_src_dir"; fi
  done
}

generate_ignore_files() {
  local patterns
  patterns="$(extract_ignore_patterns)"

  if [[ -z "$patterns" ]]; then
    echo "[sync-ai-configs] WARNING: no ignore patterns extracted, skipping ignore files" >&2
    return
  fi

  local ignore_content="# AUTO-GENERATED by sync-ai-configs. Do not edit directly.
# Edit the source file in docs/ai-guidelines/ignore-patterns.md instead.

${patterns}"

  if has_tool "claude";    then write_file ".claudeignore" "$ignore_content"; fi
  if has_tool "cursor";    then write_file ".cursorignore" "$ignore_content"; fi
  if has_tool "jetbrains"; then write_file ".aiignore"     "$ignore_content"; fi
}

###############################################################################
# Wiki reference pages (auto-generated from canonical sources)
###############################################################################

# Mapping: source filename -> wiki reference filename -> title
# Format: "source_file|wiki_file"
WIKI_CORE_MAPPINGS=(
  "index.md|AI-Usage-Policy.md"
  "general-rules.md|Coding-Standards.md"
  "security-and-compliance.md|Security-and-Compliance.md"
  "testing.md|Testing-Guidelines.md"
  "copilot-features.md|Copilot-Configuration.md"
  "ignore-patterns.md|Ignore-Patterns.md"
  "pilot-metrics.md|Pilot-Metrics.md"
)

# Map language slug to Title-Case for wiki filenames
wiki_lang_title_slug() {
  case "$1" in
    csharp)                  echo "CSharp" ;;
    java)                    echo "Java" ;;
    python)                  echo "Python" ;;
    powershell)              echo "PowerShell" ;;
    javascript-typescript)   echo "JavaScript-TypeScript" ;;
    bash)                    echo "Bash" ;;
    *)                       echo "$1" ;;
  esac
}

generate_wiki_pages() {
  local wiki_ref_dir="$PROJECT_ROOT/docs/wiki/Reference"
  mkdir -p "$wiki_ref_dir"

  local wiki_header="<!-- AUTO-GENERATED from docs/ai-guidelines/ by sync-ai-configs. -->
<!-- Edit the source file in docs/ai-guidelines/, then re-run the sync script. -->
"

  # Core guideline pages
  local entry source_file wiki_file content output
  for entry in "${WIKI_CORE_MAPPINGS[@]}"; do
    source_file="${entry%%|*}"
    wiki_file="${entry##*|}"
    if [[ -f "$DOCS_DIR/$source_file" ]]; then
      content="$(cat "$DOCS_DIR/$source_file")"
      output="${wiki_header}
${content}"
      write_file "docs/wiki/Reference/${wiki_file}" "$output"
    fi
  done

  # Language-specific pages (guideline + wiki example)
  local slug title_slug
  for lang_entry in "${LANGUAGES[@]}"; do
    slug="$(lang_slug "$lang_entry")"
    if [[ -f "$DOCS_DIR/${slug}.md" ]]; then
      content="$(read_lang_content "$slug")"
      title_slug="$(wiki_lang_title_slug "$slug")"
      output="${wiki_header}
${content}"
      write_file "docs/wiki/Reference/Lang-${title_slug}.md" "$output"
    fi
  done
}

###############################################################################
# --clean: delete all known auto-generated outputs with confirmation
###############################################################################
run_clean() {
  local yes="${1:-false}"

  local -a known_files=(
    "CLAUDE.md"
    ".claudeignore"
    "AGENTS.md"
    ".cursorignore"
    ".aiignore"
    ".github/copilot-instructions.md"
    ".github/workflows/copilot-setup-steps.yml"
  )

  # docs/wiki/Reference is intentionally excluded: wiki files are committed source
  # and should only be regenerated by sync, never deleted by --clean.
  local -a known_dirs=(
    ".github/instructions"
    ".github/agents"
    ".github/prompts"
    ".github/skills"
    ".agents"
    ".cursor/rules"
    ".cursor/skills"
    ".aiassistant"
    ".junie"
  )

  local -a to_delete=()
  local -a to_skip=()

  _is_auto_generated() {
    head -5 "$1" 2>/dev/null | grep -q "AUTO-GENERATED"
  }

  # Check individual files
  for rel in "${known_files[@]}"; do
    local full="$PROJECT_ROOT/$rel"
    [[ -f "$full" ]] || continue
    if _is_auto_generated "$full"; then
      to_delete+=("$rel")
    else
      to_skip+=("$rel")
    fi
  done

  # Check directory contents recursively
  for rel_dir in "${known_dirs[@]}"; do
    local full_dir="$PROJECT_ROOT/$rel_dir"
    [[ -d "$full_dir" ]] || continue
    while IFS= read -r -d '' file; do
      local rel="${file#"$PROJECT_ROOT/"}"
      if _is_auto_generated "$file"; then
        to_delete+=("$rel")
      else
        to_skip+=("$rel")
      fi
    done < <(find "$full_dir" -type f -print0)
  done

  # Nothing to do
  if [[ ${#to_delete[@]} -eq 0 ]]; then
    echo ""
    echo "[sync-ai-configs --clean] Nothing to delete (no auto-generated files found)."
    if [[ ${#to_skip[@]} -gt 0 ]]; then
      echo ""
      echo "  Skipped (manually edited):"
      for f in "${to_skip[@]}"; do echo "    $f"; done
    fi
    echo ""
    return 0
  fi

  # Print summary
  echo ""
  echo "[sync-ai-configs --clean] Will delete ${#to_delete[@]} auto-generated file(s):"
  for f in "${to_delete[@]}"; do echo "    $f"; done
  if [[ ${#to_skip[@]} -gt 0 ]]; then
    echo ""
    echo "  Will skip ${#to_skip[@]} file(s) (manually edited -- AUTO-GENERATED marker removed):"
    for f in "${to_skip[@]}"; do echo "    $f"; done
  fi
  echo ""

  # Confirm unless --yes / -y
  if ! $yes; then
    if [ -t 0 ]; then
      read -rp "Delete ${#to_delete[@]} file(s)? (y/N) " _answer
      case "$_answer" in
        y|Y) ;;
        *)
          echo "Aborted."
          return 0
          ;;
      esac
    else
      echo "[sync-ai-configs --clean] Non-interactive: pass --yes to confirm deletion."
      return 0
    fi
  fi

  # Delete files
  local deleted=0
  for rel in "${to_delete[@]}"; do
    local full="$PROJECT_ROOT/$rel"
    if [[ -f "$full" ]]; then
      rm -f "$full"
      echo "  x deleted $rel"
      (( deleted++ )) || true
    fi
  done

  # Remove empty directories (deepest first), then check parent dirs
  for rel_dir in "${known_dirs[@]}"; do
    local full_dir="$PROJECT_ROOT/$rel_dir"
    [[ -d "$full_dir" ]] || continue
    find "$full_dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    if [[ -d "$full_dir" ]] && [[ -z "$(ls -A "$full_dir" 2>/dev/null)" ]]; then
      rmdir "$full_dir" 2>/dev/null || true
    fi
  done
  # Also remove parent directories that became empty (e.g. .cursor after both
  # .cursor/rules and .cursor/skills are deleted but .cursor itself is not in known_dirs)
  local -a seen_parents=()
  for rel_dir in "${known_dirs[@]}"; do
    local parent="${rel_dir%/*}"
    [[ "$parent" == "$rel_dir" ]] && continue  # no parent component
    local already=false
    for k in "${known_dirs[@]}"; do [[ "$k" == "$parent" ]] && already=true && break; done
    for s in "${seen_parents[@]+"${seen_parents[@]}"}"; do [[ "$s" == "$parent" ]] && already=true && break; done
    $already && continue
    seen_parents+=("$parent")
    local full_parent="$PROJECT_ROOT/$parent"
    if [[ -d "$full_parent" ]] && [[ -z "$(ls -A "$full_parent" 2>/dev/null)" ]]; then
      rmdir "$full_parent" 2>/dev/null || true
    fi
  done

  echo ""
  echo "[sync-ai-configs --clean] Done. $deleted file(s) deleted."
  echo ""
}

###############################################################################
# Main
###############################################################################

main() {
  # --- Argument parsing ---
  local generate_all=false reconfigure=false wiki_only=false clean=false clean_yes=false
  local ide_override=""
  for arg in "$@"; do
    case "$arg" in
      --all)         generate_all=true; SYNC_GENERATE_ALL=true ;;
      --reconfigure) reconfigure=true ;;
      --ide=*)       ide_override="${arg#--ide=}" ;;
      --new-project) NEW_PROJECT=true ;;
      --wiki-only)   wiki_only=true ;;
      --clean)       clean=true ;;
      --yes|-y)      clean_yes=true ;;
    esac
  done

  # --clean: delete generated outputs and exit (works without docs/ai-guidelines/)
  if $clean; then run_clean "$clean_yes"; return 0; fi

  echo "[sync-ai-configs] Source directory: $DOCS_DIR"

  if [[ ! -d "$DOCS_DIR" ]]; then
    echo "[sync-ai-configs] ERROR: docs/ai-guidelines/ directory not found!" >&2
    exit 1
  fi

  # --- Wiki-only mode: skip tool config entirely ---
  if $wiki_only; then
    if [[ -d "$PROJECT_ROOT/docs/wiki" ]]; then
      echo ""
      echo "[sync-ai-configs] Wiki-only mode -- generating docs/wiki/Reference/ pages."
      generate_wiki_pages
      echo ""
      echo "Done. Wiki reference pages generated."
    else
      echo "[sync-ai-configs] ERROR: docs/wiki/ directory not found!" >&2
      exit 1
    fi
    return 0
  fi

  # --- Configuration ---
  if $generate_all; then
    load_config || true   # preserve COPILOT_AGENT_IDE from saved config if present
    SELECTED_TOOLS=("${TOOL_IDS[@]}")
    SELECTED_LANGS=("${LANG_IDS[@]}")
    SELECTED_EXTRAS=("${EXTRA_IDS[@]}")
  elif $reconfigure; then
    configure
  elif load_config; then
    if [ -t 0 ]; then
      echo ""
      echo "Current config ($(basename "$CONFIG_FILE")):"
      echo "  Tools    : ${SELECTED_TOOLS[*]:-none}"
      echo "  Languages: ${SELECTED_LANGS[*]:-none}"
      echo "  Extras   : ${SELECTED_EXTRAS[*]:-none}"
      if has_tool "copilot"; then
        case "$COPILOT_AGENT_IDE" in
          jetbrains)    _ide_label="JetBrains" ;;
          visualstudio) _ide_label="Visual Studio (Windows)" ;;
          *)            _ide_label="VS Code" ;;
        esac
        echo "  Agent IDE: $_ide_label"
      fi
      read -rp "Use this config? [Y/n/ide] " answer
      case "$(_to_lower "$answer")" in
        n)
          configure ;;
        ide)
          echo ""
          echo "  Select agent IDE:"
          echo "    1) VS Code (default)"
          echo "    2) JetBrains"
          echo "    3) Visual Studio (Windows)"
          read -rp "  Choice [1-3]: " _ide_choice
          case "$_ide_choice" in
            2) COPILOT_AGENT_IDE="jetbrains" ;;
            3) COPILOT_AGENT_IDE="visualstudio" ;;
            *) COPILOT_AGENT_IDE="vscode" ;;
          esac
          echo "  Agent IDE set to: $COPILOT_AGENT_IDE"
          save_config ;;
      esac
    fi
  elif [ -t 0 ]; then
    configure
  else
    echo "[sync-ai-configs] Non-interactive: generating all configs." >&2
    load_config || true   # preserve COPILOT_AGENT_IDE from saved config if present
    SELECTED_TOOLS=("${TOOL_IDS[@]}")
    SELECTED_LANGS=("${LANG_IDS[@]}")
    SELECTED_EXTRAS=("${EXTRA_IDS[@]}")
  fi

  # --- Apply --ide override if provided ---
  if [[ -n "$ide_override" ]]; then
    case "$ide_override" in
      vscode|jetbrains|visualstudio)
        if [[ "$COPILOT_AGENT_IDE" != "$ide_override" ]]; then
          COPILOT_AGENT_IDE="$ide_override"
          echo "[sync-ai-configs] Agent IDE switched to: $ide_override"
          save_config
        fi
        ;;
      *)
        echo "[sync-ai-configs] WARNING: Unknown IDE '$ide_override'. Valid values: vscode, jetbrains, visualstudio" >&2
        echo "[sync-ai-configs] Continuing with current IDE: $COPILOT_AGENT_IDE" >&2
        ;;
    esac
  fi

  # --- Filter language list to selected languages only ---
  local _filtered=()
  for entry in "${LANGUAGES[@]}"; do
    local slug
    slug="$(lang_slug "$entry")"
    if has_lang "$slug"; then _filtered+=("$entry"); fi
  done
  # Safe empty-array assignment: "${_filtered[@]}" crashes under set -u when _filtered is empty.
  if [[ ${#_filtered[@]} -gt 0 ]]; then
    LANGUAGES=("${_filtered[@]}")
  else
    LANGUAGES=()
  fi

  # --- Clean up stale outputs from deselected tools ---
  # Only remove files that still contain the AUTO-GENERATED marker.
  # Manually edited files (marker removed) are left untouched.
  local cleaned=0 skipped=0

  # Remove a single file only if it contains the AUTO-GENERATED marker.
  remove_generated_file() {
    local target="$PROJECT_ROOT/$1"
    [[ -f "$target" ]] || return 0
    if head -5 "$target" | grep -q "AUTO-GENERATED"; then
      rm -f "$target"
      printf "  [x] removed %s\n" "$1" >&2
      (( cleaned++ )) || true
    else
      printf "  (x) kept %s (manually edited)\n" "$1" >&2
      (( skipped++ )) || true
    fi
  }

  # Remove a directory, but only delete files that have the marker.
  # If any file was kept, the directory survives.
  remove_generated_dir() {
    local target="$PROJECT_ROOT/$1"
    [[ -d "$target" ]] || return 0
    local kept=0
    while IFS= read -r -d '' f; do
      if head -5 "$f" | grep -q "AUTO-GENERATED"; then
        rm -f "$f"
        local rel="${f#"$PROJECT_ROOT"/}"
        printf "  [x] removed %s\n" "$rel" >&2
        (( cleaned++ )) || true
      else
        (( kept++ )) || true
        local rel="${f#"$PROJECT_ROOT"/}"
        printf "  (x) kept %s (manually edited)\n" "$rel" >&2
        (( skipped++ )) || true
      fi
    done < <(find "$target" -type f -print0 2>/dev/null)
    # Remove empty directories left behind
    if (( kept == 0 )); then
      rm -rf "$target"
    else
      find "$target" -type d -empty -delete 2>/dev/null || true
    fi
  }

  if ! has_tool "claude"; then
    remove_generated_file "CLAUDE.md"
    remove_generated_file ".claudeignore"
  fi
  if ! has_tool "copilot"; then
    remove_generated_file ".github/copilot-instructions.md"
    remove_generated_dir  ".github/instructions"
    remove_generated_file ".github/workflows/copilot-setup-steps.yml"
    remove_generated_dir  ".github/skills"
    if ! has_extra "agents";  then remove_generated_dir ".github/agents"; fi
    if ! has_extra "prompts"; then remove_generated_dir ".github/prompts"; fi
  fi
  if ! has_tool "copilot" && ! has_tool "codex"; then
    remove_generated_file "AGENTS.md"
  fi
  if ! has_tool "codex"; then
    remove_generated_dir ".agents"
  fi
  if ! has_tool "cursor"; then
    remove_generated_dir  ".cursor/rules"
    remove_generated_dir  ".cursor/skills"
    remove_generated_file ".cursorignore"
  fi
  if ! has_tool "jetbrains"; then
    remove_generated_dir  ".aiassistant"
    remove_generated_file ".aiignore"
  fi
  if ! has_tool "junie"; then
    remove_generated_dir ".junie"
  fi
  if ! has_extra "agents"; then
    remove_generated_dir ".github/agents"
  fi
  if ! has_extra "prompts"; then
    remove_generated_dir ".github/prompts"
  fi

  if (( cleaned > 0 )) || (( skipped > 0 )); then
    printf "[sync-ai-configs] Cleanup: %d removed, %d kept (manually edited).\n" "$cleaned" "$skipped" >&2
  fi

  # --- Generate ---
  echo ""
  echo "[sync-ai-configs] Generating..."

  local cached_core_content
  cached_core_content="$(core_content)"

  local cached_skills_summary
  cached_skills_summary="$(build_skills_summary)"

  generate_ai_sync_md

  if has_tool "claude"; then generate_claude_md; fi

  if has_tool "copilot" || has_tool "codex"; then
    generate_agents_md
  fi

  if has_tool "copilot"; then
    generate_copilot_instructions
    generate_copilot_language_instructions
    generate_copilot_setup_steps
    if has_extra "agents";  then generate_custom_agents; fi
    if has_extra "prompts"; then
      generate_review_prompt
      generate_tests_prompt
      if has_extra "agents"; then generate_backlog_prompts; fi
    fi
  fi

  if has_tool "cursor"; then
    generate_cursor_general
    generate_cursor_language_rules
  fi

  if has_tool "jetbrains"; then
    generate_aiassistant_general
    generate_aiassistant_language_rules
  fi

  if has_tool "junie"; then generate_junie_guidelines; fi

  # Skills -- unified generation for all tools that support them
  generate_all_skills

  generate_ignore_files

  # Wiki reference pages (always generated when docs/wiki/ exists)
  if [[ -d "$PROJECT_ROOT/docs/wiki" ]]; then
    generate_wiki_pages
  fi

  # --- New-project setup (detach from template origin) ---
  if $NEW_PROJECT; then
    if git -C "$PROJECT_ROOT" remote get-url origin &>/dev/null; then
      local current_origin
      current_origin="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null)"
      if [[ "$current_origin" == *"EMA"*"Scaffolding"* ]] || [[ "$current_origin" == *"scaffolding"* ]]; then
        git -C "$PROJECT_ROOT" remote remove origin
        echo "[sync-ai-configs] Removed template origin."
        echo "  Set your project's remote with:  git remote add origin <your-repo-url>"
      else
        echo "[sync-ai-configs] Origin does not point to the template repo -- keeping it."
      fi
    fi
  elif ! $generate_all && [ -t 0 ]; then
    if git -C "$PROJECT_ROOT" remote get-url origin &>/dev/null; then
      local current_origin
      current_origin="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null)"
      if [[ "$current_origin" == *"EMA"*"Scaffolding"* ]] || [[ "$current_origin" == *"scaffolding"* ]]; then
        echo ""
        read -rp "Origin points to the template repo. Remove it? [y/N] " remove_origin
        if [[ "$(_to_lower "$remove_origin")" == "y" ]]; then
          git -C "$PROJECT_ROOT" remote remove origin
          echo "[sync-ai-configs] Removed template origin."
          echo "  Set your project's remote with:  git remote add origin <your-repo-url>"
        fi
      fi
    fi
  fi

  # --- Ensure artifacts/ directory exists (agents save work here) ---
  local artifacts_dir="$PROJECT_ROOT/artifacts"
  if [[ ! -d "$artifacts_dir" ]]; then
    mkdir -p "$artifacts_dir"
    touch "$artifacts_dir/.gitkeep"
  fi

  # --- Ensure backlog support files exist (ema-backlog-manager) ---
  if has_extra "agents"; then
    # templates/safe-backlog-schema.json -- JSON schema for backlog files
    local templates_dir="$PROJECT_ROOT/templates"
    local schema_source="$SCRIPT_DIR/../templates/safe-backlog-schema.json"
    local schema_dest="$templates_dir/safe-backlog-schema.json"
    if [[ -f "$schema_source" && ! -f "$schema_dest" ]]; then
      mkdir -p "$templates_dir"
      cp "$schema_source" "$schema_dest"
      echo "  + created templates/safe-backlog-schema.json"
    fi

    # .vscode/mcp.json -- Azure DevOps MCP server config (needed for azure-devops/* tools in ema-backlog-manager)
    local vscode_dir="$PROJECT_ROOT/.vscode"
    local mcp_json="$vscode_dir/mcp.json"
    if [[ ! -f "$mcp_json" ]]; then
      mkdir -p "$vscode_dir"
      cat > "$mcp_json" <<'MCPEOF'
{
  "servers": {
    "azure-devops": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp", "euemadev", "--domains", "work-items,core"]
    }
  }
}
MCPEOF
      echo "  + created .vscode/mcp.json (Azure DevOps MCP server for ema-backlog-manager)"
      echo "    Requires Node.js / npx. First use will prompt for OAuth in VS Code."
    fi

    # Remind about .gitignore entries
    local gitignore="$PROJECT_ROOT/.gitignore"
    if [[ -f "$gitignore" ]] && ! grep -q 'backlog/\*\.json' "$gitignore"; then
      echo ""
      echo "  [backlog-manager] Add these entries to .gitignore to avoid committing local backlog files:"
      echo "    backlog/*.json"
      echo "    backlog.config.json"
      echo ""
    fi
  fi

  # --- Summary ---
  echo ""
  if [[ ${#KEPT_FILES[@]} -gt 0 ]]; then
    echo "Done. ${#GENERATED_FILES[@]} files generated, ${#KEPT_FILES[@]} kept (manually edited)."
  else
    echo "Done. ${#GENERATED_FILES[@]} files generated."
  fi
}

main "$@"
