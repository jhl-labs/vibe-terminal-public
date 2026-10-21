# Security policy

## Supported versions

Security fixes are applied to the latest release on `main`.

## Reporting a vulnerability

Please do **not** open a public issue for a suspected vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/jhl-labs/vibe-terminal-public/security/advisories/new)
instead. Include affected versions, reproduction steps, impact, and any
suggested mitigation. We will acknowledge the report and coordinate disclosure
privately.

Do not include API keys, tokens, personal data, or exploit payloads that could
harm other users in a report.

## Automated security checks

Only GitHub features that are free for public repositories are used. Paid licenses (GHAS Code Security/Secret Protection, Code Quality) and usage-billed AI features (Copilot Autofix, AI secret detection) stay disabled.

- Repository settings: secret scanning with push protection, Dependabot alerts and security updates, private vulnerability reporting.
- Existing workflows: CodeQL (`codeql.yml`), OSV-Scanner (`osv-scanner.yml`), Semgrep (`semgrep.yml`).
- `security-checks.yml`: dependency review on pull requests and OpenSSF Scorecard on `main` and weekly. Scorecard results are uploaded to code scanning only, not published.
