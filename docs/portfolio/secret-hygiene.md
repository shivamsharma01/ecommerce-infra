# Secret Hygiene for MCART Local Development

**Status:** Phase 0 baseline action  
**Related:** [Modernization Assessment](modernization-assessment.md) — Part 10 (cost/dev) and security deepening

This document records secret-handling issues found during the portfolio assessment and the remediation applied. **No live credentials are stored in this file.**

---

## Issue summary (Phase 0 finding)

During repository inspection, these files contained **plaintext credentials** unsuitable for version control:

- [`ecommerce-docs/local setup ecommerce.txt`](../local%20setup%20ecommerce.txt)
- [`ecommerce-infra/manual docs /local setup.txt`](../../ecommerce-infra/manual%20docs%20/local%20setup.txt)

| Secret type | Risk | Action taken |
|-------------|------|--------------|
| SMTP app password (`SPRING_MAIL_PASSWORD`) | **High** — real mailbox credential exposed in git history | Removed from setup doc; replaced with env var instructions |
| SMTP username (personal email) | Medium — PII + account linkage | Replaced with placeholder |
| GCP service account key path | Medium — path reveals project layout | Replaced with placeholder path |
| Local Postgres/Redis passwords | Low — dev-only defaults | Kept as explicit dev defaults with note |
| Bootstrap admin password | Low — documented seed credential | Kept; matches Flyway bootstrap script |

---

## Required operator actions

### 1. Rotate exposed SMTP credential (if file was ever committed)

If `local setup ecommerce.txt` was committed to Git with a real `SPRING_MAIL_PASSWORD`:

1. **Revoke** the exposed app password in your mail provider (Google Account → Security → App passwords).
2. **Generate** a new app password.
3. Store it only in a local env file or shell profile — **never** in the repository.

**Do not paste the new password into chat, issues, or portfolio docs.**

### 2. Use environment variables for email service

Run the email service with credentials from the environment:

```bash
export SPRING_MAIL_USERNAME="${SPRING_MAIL_USERNAME:?Set SPRING_MAIL_USERNAME}"
export SPRING_MAIL_PASSWORD="${SPRING_MAIL_PASSWORD:?Set SPRING_MAIL_PASSWORD}"
./gradlew bootRun --args='--spring.profiles.active=local'
```

Optional: create a **gitignored** file at repo root (never commit):

```text
# .env.local (add to .gitignore)
SPRING_MAIL_USERNAME=your-smtp-user@example.com
SPRING_MAIL_PASSWORD=your-app-password-here
```

Load before `bootRun`:

```bash
set -a && source .env.local && set +a
```

### 3. GCP credentials

Use Application Default Credentials or a key file **outside** the repo:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:?Path to your GCP key JSON}"
gcloud config set project "${GCP_PROJECT_ID:?Your GCP project ID}"
```

Never commit JSON key files. Ensure `.gitignore` includes:

```gitignore
*.json
.env
.env.local
.env.*.local
```

(Adjust if your repo legitimately tracks non-secret JSON.)

### 4. Portfolio and case study materials

- **Never** include SMTP, OAuth client secrets, JWT private keys, or DB production passwords in case studies, screenshots, or demo videos.
- Redact `kubectl get secret` output and `application.yaml` snippets before publishing.
- Mock payment is labeled **Simulated scenario** — no real PSP keys required.

---

## Dev-only credentials (acceptable in local setup docs)

These are **intentional local defaults** for Docker Postgres/Redis on localhost. They must **not** be reused in GKE or production:

| Credential | Purpose | Scope |
|------------|---------|-------|
| `postgres` / `postgres` | Postgres superuser in Docker | localhost:5433 only |
| `auth_password`, `user_password`, etc. | Per-service Flyway local DBs | localhost only |
| `myStrongRedisPassword` | Local Redis | localhost:6379 only |
| `ChangeMeAfterFirstDeploy!` | Bootstrap admin (Flyway seed) | Local/dev; change after first deploy |

---

## Checklist before sharing repository publicly

- [ ] Confirm no SMTP app passwords in any tracked file (`git grep -i mail_password` / `app.password`)
- [ ] Confirm no GCP key JSON files tracked
- [ ] Confirm `.env.local` or similar is gitignored
- [ ] Rotate any credential that was ever committed to a public remote
- [ ] Review [`local setup ecommerce.txt`](../local%20setup%20ecommerce.txt) uses placeholders only for sensitive values
- [ ] Portfolio website and videos contain no terminal history with exports

---

## Future improvement (Phase 7+)

- Add `.env.example` with variable **names** only (no values)
- Document email setup in `ecommerce-email/README.md` referencing this guide
- Pre-commit hook or CI secret scan (e.g. gitleaks) — **Proposed modernization**

---

## Change log

| Date | Change |
|------|--------|
| 2026-09 | Phase 0: Removed plaintext SMTP password from local setup notes; created this guide |

---

*If you discover additional exposed secrets, rotate them first, then update this document with the secret **type** only — never the value.*
