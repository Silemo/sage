# Bash / Shell Scripting Conventions

## Script Header

Every script must start with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- `set -e` -- exit immediately on command failure
- `set -u` -- treat unset variables as errors
- `set -o pipefail` -- propagate failures through pipes

## Variables

- Quote all variable expansions: `"$var"` not `$var`
- Use `local` for function-scoped variables
- Use `readonly` for constants: `readonly CONFIG_DIR="/etc/myapp"`
- Use `${var:-default}` for default values
- Use uppercase for exported/global variables, lowercase for local variables

## Conditionals and Control Flow

- Use `[[ ]]` over `[ ]` for conditionals -- `[[ ]]` supports regex, glob matching, and is safer with unquoted variables
- Use `$(command)` for command substitution -- never backticks
- Use `(( ))` for arithmetic

## Functions

- Declare with `function_name() { ... }` syntax
- Use `local` for all internal variables
- Return status codes, not strings -- capture output with `$(function_name)`
- Include a `usage()` or `--help` function in all scripts

## Error Handling and Cleanup

- Use `trap` for cleanup on exit:

```bash
cleanup() {
    rm -f "$tmpfile"
}
trap cleanup EXIT
```

- Check command availability before use: `command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }`

## Output

- Use `printf` over `echo` for portability and format control
- Send diagnostic/progress messages to stderr: `printf "Processing...\\n" >&2`
- Send machine-readable output to stdout

## Quality

- All scripts must pass ShellCheck with no warnings
- Name scripts with `.sh` extension
- Make scripts executable: `chmod +x script.sh`
- Prefer long option flags for readability: `--recursive` over `-r` in scripts

## Testing

- Use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System) for unit tests
- Test edge cases: empty input, missing files, permission errors
