# Security and Compliance

## Never Send to AI Tools

The following must never be provided as input to any AI coding assistant:

- **Real credentials** -- API keys, tokens, passwords, connection strings with real credentials, private keys, PFX/PEM files
- **Personally identifiable information (PII)** -- real names, email addresses, government IDs, health data, financial records
- **Non-public business data** -- confidential customer data, commercially-sensitive business data, non-public production database contents
- **Active vulnerability details** -- unpatched security vulnerabilities with exploit information

### What IS allowed

- **Security configuration code** -- app registrations, IAM policies, RBAC definitions, Terraform/Bicep security resources, pipeline configs (use placeholder values for secrets)
- **Infrastructure-as-code** -- ARM templates, Terraform modules, Kubernetes manifests, Dockerfiles
- **Publicly accessible data** -- data from public APIs, open datasets, public documentation
- **Authentication/authorization logic** -- the code itself is fine; just don't include real tokens, keys, or credentials inline

> **Key principle**: The restriction is on **data**, not **code**. All source code (proprietary, internal, open-source) may be used with AI tools. See [index.md](index.md#code-vs-data-distinction) for the full policy.

## Data Handling

- Store credentials in environment variables or a secret manager (Azure Key Vault, AWS Secrets Manager, HashiCorp Vault)
- Use placeholder values in examples and documentation: `YOUR_API_KEY_HERE`, `connection-string-placeholder`
- Never log sensitive data -- mask or redact secrets, PII, and tokens in log output
- Use `.gitignore` and AI ignore patterns to prevent secrets from reaching AI tool context

## Compliance

- **GDPR** -- ensure compliance wherever personal data is involved; do not send personal data to AI tools
- **Software licenses** -- be aware of license terms when using AI-generated code in your projects; ensure AI output is compatible with your project's licensing
- **Audit trail** -- document AI-assisted code in PR descriptions so reviewers and auditors can identify which parts were AI-generated
- **Data retention** -- be aware of AI tool data retention policies; prefer tools that do not retain prompts or outputs

## Incident Response

If credentials or sensitive data are accidentally sent to an AI tool:

1. **Rotate immediately** -- revoke and regenerate the compromised credential
2. **Report** -- follow EMA security incident procedures
3. **Audit** -- review logs to determine if the credential was used between exposure and rotation
4. **Remediate** -- update secret storage and access controls to prevent recurrence
