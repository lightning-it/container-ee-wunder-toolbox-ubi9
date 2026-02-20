# AGENT.md

## Dependency pinning rules

- Keep `Dockerfile` tool version args pinned:
  - `HELM_VERSION`
  - `KUSTOMIZE_VERSION`
  - `VAULT_VERSION`
- These pins are Renovate-managed through `renovate.json` custom regex managers.
- Do not remove or rename these args without updating `renovate.json` in the same change.

## When adding new pinned tool versions

- If a new `ARG *_VERSION=...` is introduced in `Dockerfile`, add a matching Renovate
  `customManagers` regex entry so updates remain automated.
- Prefer GitHub release/tag data sources with an `extractVersionTemplate` when tags include prefixes
  like `v` or `kustomize/v`.
