# Operator runbook: sandbox backend requirements

**Status:** Real keys, stats isolation, and webhooks are **backend/ops** work — not implemented in this SDK repo.

## Requirements for the handover checklist

| Item | Requirement | Owner |
|------|-------------|-------|
| Sandbox API keys | Issue keys that authenticate only against sandbox; never accept prod secrets in sample apps | Backend / platform |
| Sandbox endpoints | Traffic to sandbox hosts must **not** write production analytics/stats | Backend |
| Dashboard stats reset | Ability to wipe or reset sandbox/dashboard stats independently of prod | Backend / dashboard |
| Webhooks | Separate prod vs dev (or sandbox) webhook endpoints and signing secrets | Backend |

## iOS SDK

The SDK calls `https://api.dialogintelligens.dk` and authenticates with a session token supplied by
the host through `tokenProvider`.
