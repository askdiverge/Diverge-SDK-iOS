# Operator runbook: sandbox backend requirements

**Status:** SDK-only placeholder hosts exist (`sandbox.api.askdiverge.ai` / `api.askdiverge.ai`). Real keys, stats isolation, and webhooks are **backend/ops** work — not implemented in this SDK repo.

## Requirements for the handover checklist

| Item | Requirement | Owner |
|------|-------------|-------|
| Sandbox API keys | Issue keys that authenticate only against sandbox; never accept prod secrets in sample apps | Backend / platform |
| Sandbox endpoints | Traffic to sandbox hosts must **not** write production analytics/stats | Backend |
| Dashboard stats reset | Ability to wipe or reset sandbox/dashboard stats independently of prod | Backend / dashboard |
| Webhooks | Separate prod vs dev (or sandbox) webhook endpoints and signing secrets | Backend |

## SDK contract today

- `DivergeEnvironment.sandbox` → `https://sandbox.api.askdiverge.ai`
- `DivergeEnvironment.production` → `https://api.askdiverge.ai`
- `configure` does **not** perform network I/O in v0.1.0

When HTTP lands, clients must keep using environment-selected base URLs and never mix sandbox keys with production hosts.

## Related

- iOS sample default key: `sk_sandbox_demo` (placeholder only)
- Android sample: same placeholder string
