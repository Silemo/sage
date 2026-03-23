## Executive Summary
The targeted security audit of the SAGE static schedule viewer found no critical or high-severity issues in the reviewed application code. The client-side runtime is small, uses safe DOM APIs such as `textContent` and `createElement`, has no authentication surface, no dynamic code execution, no embedded secrets, and no evidence of injection-prone patterns in the changed files. The main risk area is deployment configuration: the GitHub Pages workflow publishes the entire repository artifact, which can expose internal documentation and review artifacts publicly, and both workflows rely on mutable major-tag GitHub Actions rather than immutable SHAs.

## Scan Environment
- Project type(s): Static HTML/CSS/JavaScript site; GitHub Actions workflows
- CLI tools available: `npm` installed, but no `package.json` or lockfile was present so no Node dependency audit was applicable
- CLI tools unavailable: `pip-audit` not installed; `trivy` not installed; `grype` not installed
- Files analyzed: 11
- Scan date: 2026-03-23

## Findings

### Critical
- None.

### High
- None.

### Medium
- **[VULN-001] Data Exposure [.github/workflows/static.yml:40]**: The GitHub Pages deployment uploads the entire repository as the publish artifact via `path: '.'`.
  - **Risk**: When Pages is enabled publicly, non-site content such as `artifacts/`, `docs/`, `test-data/`, review reports, and future internal files committed to the repository can become directly downloadable from the public site. This expands the public attack surface and can disclose internal process documentation or audit artifacts that were never intended to be web content.
  - **Evidence**: `.github/workflows/static.yml:40` contains `path: '.'`
  - **Remediation**: Publish from a dedicated deployment directory that contains only the site assets. For this repo, restrict the artifact to a curated output such as `index.html`, `styles.css`, `app.js`, `js/`, `config/`, and `data/`, or generate a dedicated `site/` folder before `actions/upload-pages-artifact` runs.
  - **Reference**: CWE-200, OWASP A01:2021 Broken Access Control / exposure through overly broad publishing scope

### Low
- **[VULN-002] CI/CD Hardening [.github/workflows/copilot-setup-steps.yml]**: The Copilot setup workflow has no explicit `permissions:` block.
  - **Risk**: The workflow currently only checks out the repository, but future edits to this job will inherit whatever default `GITHUB_TOKEN` permissions are configured at the repository or organization level. That weakens least-privilege guarantees and increases the blast radius of later changes.
  - **Evidence**: `.github/workflows/copilot-setup-steps.yml` contains a job definition and `actions/checkout@v4` at line 27, but no top-level `permissions:` block.
  - **Remediation**: Add an explicit minimal permission set, for example:
    - `permissions:`
    - `  contents: read`
  - **Reference**: CWE-250, GitHub Actions hardening guidance

- **[VULN-003] Supply Chain / CI Pinning [.github/workflows/static.yml:33,35,37,43; .github/workflows/copilot-setup-steps.yml:27]**: GitHub Actions are pinned only to mutable major tags (`@v4`, `@v5`, `@v3`) rather than immutable commit SHAs.
  - **Risk**: If an upstream action tag is compromised or unexpectedly retargeted, the workflow can execute unreviewed code in CI. The practical risk is lower than using `@main`, but immutable SHAs provide stronger supply-chain integrity.
  - **Evidence**:
    - `.github/workflows/static.yml:33` `uses: actions/checkout@v4`
    - `.github/workflows/static.yml:35` `uses: actions/configure-pages@v5`
    - `.github/workflows/static.yml:37` `uses: actions/upload-pages-artifact@v3`
    - `.github/workflows/static.yml:43` `uses: actions/deploy-pages@v4`
    - `.github/workflows/copilot-setup-steps.yml:27` `uses: actions/checkout@v4`
  - **Remediation**: Pin each action to an immutable full-length commit SHA, optionally with a trailing comment indicating the human-readable release tag.
  - **Reference**: CWE-829, GitHub Actions hardening guidance

## Dependency Summary
| Package | Current | Vulnerable | Fixed In | CVE(s) | Severity |
|---------|---------|-----------|----------|--------|----------|
| No dependency manifests detected (`package.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `*.csproj`, etc.) | N/A | N/A | N/A | N/A | N/A |

## Infrastructure Summary
- `.github/workflows/static.yml:40` — uploads the entire repository to Pages via `path: '.'` (Medium — VULN-001)
- `.github/workflows/copilot-setup-steps.yml` — no explicit `permissions:` block (Low — VULN-002)
- `.github/workflows/static.yml:33,35,37,43` and `.github/workflows/copilot-setup-steps.yml:27` — actions pinned only to major version tags instead of SHAs (Low — VULN-003)

## Coverage Gaps
- No package manager manifests were present, so ecosystem-specific CVE scans (`npm audit`, `pip-audit`, `cargo audit`, etc.) were not applicable
- `trivy` and `grype` were not installed, so no filesystem/container vulnerability scan could be performed
- No Docker, Terraform, Bicep, ARM, Kubernetes, or application server config files were detected
- Code-pattern analysis was targeted to the reviewed runtime/config files and workflows rather than every generated documentation file in the repository

## Recommendations
1. Restrict GitHub Pages publishing scope in `.github/workflows/static.yml` so only site assets are deployed; this is the only medium-severity issue and the most direct public exposure risk.
2. Add `permissions: contents: read` to `.github/workflows/copilot-setup-steps.yml` to enforce least privilege before the workflow gains more steps.
3. Pin all GitHub Actions to immutable commit SHAs in both workflows to reduce CI supply-chain risk.
4. Keep the current client-side rendering approach (`createElement`, `textContent`) and local-only fetch pattern; no code-level security regressions were found in `app.js`, `js/loader.js`, `js/renderer.js`, `js/url-state.js`, `index.html`, `config/sources.json`, or `tests/sage-spec-requirements.mjs`.
5. If this repository later gains a package manifest or build pipeline, add automated dependency scanning (`npm audit`, Dependabot, or equivalent) as part of CI.
