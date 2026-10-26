# Security policy

## Reporting a vulnerability

Do not open a public issue. Use *Report a vulnerability* under the Security tab of this repository, or email the security team at the address in your internal directory. Expect an acknowledgement within two business days.

## What to report

- A way to impersonate an automation service account from outside the main branch of a listed repository
- A path that bypasses the required reviews, the `production` environment approval or the pre-commit checks
- A credential, key or token found in the repository history
- An organization policy or IAM binding that is weaker than `docs/controls.md` says

## Handling secrets

- No long-lived Google credentials exist or should be created. Service account key creation is blocked by organization policy.
- `MODULES_READ_TOKEN` is the only secret. It is read-only and scoped to one repository. Rotate it at least every 90 days.
- If a secret is committed, treat it as leaked: revoke first, then rewrite history.

## Supported versions

Only `main` is supported.
