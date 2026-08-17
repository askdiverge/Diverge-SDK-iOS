# Operator runbook: `docs.askdiverge.ai` → GitHub Pages

**Status:** scaffold exists; DNS/HTTPS still need a human operator. This document does not change DNS.

## What is already automated

- [`.github/workflows/docc.yml`](../../.github/workflows/docc.yml) builds DocC + `Docs/site/` and deploys to GitHub Pages on `main`.
- [`scripts/build-docs-site.sh`](../../scripts/build-docs-site.sh) writes `site-dist/CNAME` containing `docs.askdiverge.ai`.

## Operator checklist (do once)

0. **Enable GitHub Pages** on the iOS repo: Settings → Pages → Source = **GitHub Actions**.
   Until this is on, the DocC workflow’s deploy step will 404 (build still validates `site-dist/`).
1. In the **Diverge-SDK-iOS** GitHub repo: confirm Pages source remains GitHub Actions (or the branch/artifact the DocC workflow publishes).
2. Confirm a successful `DocC` workflow run produced a Pages deployment (green deploy job, not only build).
3. At the DNS provider for `askdiverge.ai`, add the GitHub Pages records for the custom domain (typically a `CNAME` for `docs` → `<org>.github.io`, or the A/AAAA records GitHub documents for apex — follow current GitHub Pages custom-domain docs).
4. In repo Pages settings, set Custom domain to `docs.askdiverge.ai` and wait for DNS check to pass.
5. Enable **Enforce HTTPS** once the certificate is ready.
6. Verify:
   - `https://docs.askdiverge.ai/` loads the site
   - Certificate is valid
   - DocC paths under `/documentation/` resolve

## Out of scope here

- Changing registrar DNS from this workspace
- Moving hosting off GitHub Pages
