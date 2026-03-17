# PowerShell Conventions

## Function Design

- Use approved verbs from `Get-Verb` -- `Get-`, `Set-`, `New-`, `Remove-`, `Invoke-`, etc.
- Include `[CmdletBinding()]` on all functions
- Use `[Parameter()]` attributes with validation attributes (`[ValidateNotNullOrEmpty()]`, `[ValidateSet()]`, `[ValidateRange()]`)
- Support `-WhatIf` and `-Confirm` for destructive operations via `[CmdletBinding(SupportsShouldProcess)]`

## Output and Logging

- Use `Write-Verbose` for detailed progress information
- Use `Write-Warning` for non-fatal issues
- Use `Write-Error` for errors that should be catchable
- Avoid `Write-Host` in functions intended for automation -- it bypasses the pipeline
- Return objects, not formatted strings -- let the caller decide how to display

## Help and Documentation

- Include comment-based help blocks on all public functions:

```powershell
function Get-Example {
    <#
    .SYNOPSIS
        Brief description.
    .DESCRIPTION
        Detailed description.
    .PARAMETER Name
        Description of the parameter.
    .EXAMPLE
        Get-Example -Name "test"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    # implementation
}
```

## Error Handling

- Use `try`/`catch`/`finally` for error handling
- Set `$ErrorActionPreference = 'Stop'` at script level when failures should halt execution
- Use `-ErrorAction Stop` on individual commands when needed

## Testing

- **Framework**: Pester (v5+)
- Organize tests in `Describe`/`Context`/`It` blocks
- Use `Should` assertions: `| Should -Be`, `| Should -BeExactly`, `| Should -Throw`
- Mock external dependencies with `Mock`

## Style

- Use PascalCase for function names and parameters
- Use `$camelCase` for local variables
- Prefer splatting for commands with many parameters
- Use single quotes for literal strings, double quotes only when variable expansion is needed
