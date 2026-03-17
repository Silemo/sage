# EMA AI-Assisted Development Guidelines

## Purpose

These guidelines govern the use of AI coding assistants at EMA. All AI-generated code must undergo full human review before production deployment. AI tools are productivity aids, not substitutes for engineering judgment.

## Decision Tree

### Prohibited Inputs

Do **not** provide the following to AI tools:

- **Real credentials and secrets** -- API keys, passwords, tokens, certificates, private keys, connection strings containing credentials
- **Personal data (PII)** -- real names, email addresses, government IDs, health data, or any data subject to GDPR
- **Non-public business data** -- confidential customer data, non-public production database contents, commercially-sensitive business data (publicly accessible data is fine)
- **Active vulnerability reports** -- unpatched security vulnerabilities with exploit details

### Prohibited Processes

- Development of safety-critical systems without mandatory human review at every stage
- Automation of decision-making that affects individuals without human oversight
- Using AI output as-is in production without review

### Allowed Inputs

- **All source code** -- proprietary, confidential, internal, and open-source code of any license type
- **Infrastructure and security configuration code** -- Terraform, Bicep, ARM templates, app registration configs, IAM policies, pipeline definitions (strip real secrets first, use placeholders)
- **Technical documentation** -- architecture docs, API specs, runbooks
- **Configuration files** -- provided they contain no embedded real credentials (use placeholders for secrets)
- **Publicly accessible data** -- public APIs, public datasets, open data
- **Synthetic/anonymised test data** -- never real customer or production data

### Allowed Processes

- Development with mandatory human review before merge
- Prototyping and proof-of-concept work
- Refactoring existing code
- Scaffolding new projects and modules
- Building internal tools and automation
- Developer workflow assistance -- generating comments, docstrings, test stubs, and boilerplate

## Code vs. Data Distinction

> **Code is allowed. Production data is not.**
>
> AI tools may be used on any source code, regardless of whether it is proprietary, confidential, internal, or open-source. The restriction applies to **data**, not code:
>
> - **Allowed**: all source code, configuration, infrastructure-as-code, scripts, documentation
> - **Not allowed**: non-public production data, customer data, PII, credentials, secrets (publicly accessible data is fine)
> - **Required**: mandatory human review of all AI output before production deployment

## Glossary

| Term                        | Definition                                                                                                            |
|-----------------------------|-----------------------------------------------------------------------------------------------------------------------|
| Security-Sensitive Material | Credentials, API keys, encryption keys, tokens, authentication flows, vulnerability reports                           |
| Personal or Sensitive Data  | Any identifiable information including names, emails, IDs, health data, ethnicity, political or religious information |
| Non-Public Data             | Confidential business data, customer records, or non-public production data -- never send to AI tools                 |
| Allowed Internal Code       | All internal source code, modules, documentation, and scripts -- may be used with AI tools regardless of license      |
