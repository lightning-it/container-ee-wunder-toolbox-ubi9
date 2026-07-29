# container-ee-wunder-toolbox-ubi9

<!-- BEGIN LIT_SHARED_RELEASE_MODEL -->

## Release and Quality Model

This repository follows the Lightning IT shared release and quality model.

See [RELEASE.md](./RELEASE.md) for:

- branch and release flow
- required quality checks
- test matrix
- release evidence
- artifact publishing
- supported repository-specific release behavior

Repository classification: **Container Image**.
Required test profiles: `pre-commit, lint, container-build, container-smoke, trivy, fuzzing, release-validation`.
Publishing targets: `github-release, quay.io`.

## Supported and Tested Platforms

| Platform / Product |                  Status | Validation           |
| ------------------ | ----------------------: | -------------------- |
| ubuntu-latest      |               Supported | Container CI / Trivy |
| ubi9               | Tested where applicable | Container CI / Trivy |
| podman             | Tested where applicable | Container CI / Trivy |
| docker-buildx      | Tested where applicable | Container CI / Trivy |

<!-- END LIT_SHARED_RELEASE_MODEL -->

<!-- BEGIN LIT_QUALITY_BADGES -->

[![CI](https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9/actions/workflows/container-ci.yml/badge.svg?branch=develop)](https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9/actions/workflows/container-ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/lightning-it/container-ee-wunder-toolbox-ubi9?sort=semver)](https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9/releases/latest)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/lightning-it/container-ee-wunder-toolbox-ubi9/badge)](https://scorecard.dev/viewer/?uri=github.com/lightning-it/container-ee-wunder-toolbox-ubi9)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/13515/badge)](https://www.bestpractices.dev/projects/13515)
[![Quay.io](https://img.shields.io/badge/Quay.io-image-blue?logo=quay&logoColor=white)](https://quay.io/repository/l-it/ee-wunder-toolbox-ubi9)
[![Trivy](https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9/actions/workflows/container-trivy.yml/badge.svg?branch=develop)](https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9/actions/workflows/container-trivy.yml)
[![Container Build](https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9/actions/workflows/container-build.yml/badge.svg?branch=develop)](https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9/actions/workflows/container-build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

<!-- END LIT_QUALITY_BADGES -->

UBI9-based Wunder operations toolbox for Podman-driven automation in offline and restricted environments.
Includes `ansible-navigator` in-container so automation does not depend on host Ansible tooling.

The toolbox intentionally stays minimal:
- it does **not** embed Lightning IT or AAP collection bundles
- it is meant to run playbooks through Execution Environment mode
- collections should come from `quay.io/l-it/ee-wunder-ansible-ubi9:*` (or certified variant)
- it includes `podman` CLI for nested EE execution via mounted host podman socket

Dependency sources:
- RPM packages: `rpm-packages.txt`
- COPR RPM pins: `copr-packages.txt`
- Python packages: `requirements.txt`

## Included tooling

- `ansible-navigator`
- `podman`
- `helm`
- `kustomize`
- `vault`
- `modulix-automation-runtime` (installed from Fedora COPR)

Helm and Kustomize are installed in the image during build from official release tarballs and
pinned with `HELM_VERSION` and `KUSTOMIZE_VERSION` in `Dockerfile`.

`modulix-automation-runtime` is installed from COPR via `dnf copr enable` and
the pinned package list in `copr-packages.txt`.
Default COPR settings are configurable with build args:

- `MODULIX_COPR_OWNER` (default: `litroc`)
- `MODULIX_COPR_PROJECT` (default: `modulix`)
- `MODULIX_COPR_CHROOT` (default: `auto`)

`MODULIX_COPR_CHROOT=auto` maps by build architecture:
- `x86_64` -> `epel-9-x86_64`
- `aarch64/arm64` -> `epel-9-aarch64`

The package installs script payload under `/opt/modulix` and exposes
command wrappers in `/usr/bin` (for example `ansible-nav` and `ansible-nav-local`).

## Build locally

```bash
podman build --format docker -t ee-wunder-toolbox-ubi9:local .
```

Use a different COPR project:

```bash
podman build --format docker \
  --build-arg MODULIX_COPR_OWNER=litroc \
  --build-arg MODULIX_COPR_PROJECT=modulix \
  --build-arg MODULIX_COPR_CHROOT=auto \
  -t ee-wunder-toolbox-ubi9:local .
```

## Quick checks

```bash
podman run --rm ee-wunder-toolbox-ubi9:local ansible-navigator --version
podman run --rm ee-wunder-toolbox-ubi9:local sh -lc 'command -v podman && podman --version'
podman run --rm ee-wunder-toolbox-ubi9:local helm version --short
podman run --rm ee-wunder-toolbox-ubi9:local kustomize version
podman run --rm ee-wunder-toolbox-ubi9:local vault --version
podman run --rm ee-wunder-toolbox-ubi9:local sh -lc 'command -v ansible-nav && command -v ansible-nav-local'
```

## Helm usage

Basic Helm command:

```bash
podman run --rm ee-wunder-toolbox-ubi9:local helm version --short
```

Run against local kubeconfig:

```bash
podman run --rm \
  -v "$HOME/.kube:/runner/.kube:ro,Z" \
  -e KUBECONFIG=/runner/.kube/config \
  ee-wunder-toolbox-ubi9:local \
  helm list -A
```

## Kustomize usage

Basic Kustomize command:

```bash
podman run --rm -v "$PWD":/runner/project:ro,Z ee-wunder-toolbox-ubi9:local kustomize build /runner/project
```

## Pre-commit usage (devtools image)

Use the devtools image for `pre-commit`:

```bash
mkdir -p "$HOME/.cache/pre-commit"
systemctl --user enable --now podman.socket
SOCK="/run/user/$(id -u)/podman/podman.sock"
REPO="$PWD"

podman run --rm \
  --userns keep-id \
  --user "$(id -u):$(id -g)" \
  --security-opt label=disable \
  -v "$REPO":"$REPO":z \
  -v "$HOME/.cache":"$HOME/.cache":z \
  -v "$SOCK":"$SOCK" \
  -w "$REPO" \
  -e XDG_CACHE_HOME="$HOME/.cache" \
  -e PRE_COMMIT_HOME="$HOME/.cache/pre-commit" \
  -e DOCKER_HOST="unix://$SOCK" \
  -e GIT_CONFIG_COUNT=1 \
  -e GIT_CONFIG_KEY_0=safe.directory \
  -e GIT_CONFIG_VALUE_0="$REPO" \
  quay.io/l-it/ee-wunder-devtools-ubi9:latest \
  pre-commit run --all-files
```

## Security

See [SECURITY.md](./SECURITY.md) for supported versions and vulnerability reporting.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for contribution and review expectations.

## License

See [LICENSE](./LICENSE).

<!-- BEGIN LIT_RELEASE_QUALITY_MODEL -->

## Release and Quality Model

This repository follows the Lightning IT shared release and quality model.
The README shows the current supported and tested matrix.
Exact per-version validation proof is stored with each GitHub Release as `release-evidence.md` and `release-evidence.json`.
Releases are created from the protected `main` branch after a reviewed `develop -> main` release promotion.
Release back-syncs preserve the `main` merge-commit ancestry on `develop`; they
must not be replaced by rebasing or recreating already released changes.
Container releases validate build, smoke behavior, Trivy scanning, and Quay.io publishing where enabled.

See:

- [RELEASE.md](./RELEASE.md)
- [TESTING.md](./TESTING.md)
- [GitHub Releases](../../releases)

Repository classification: **Container Image**.
Required test profiles: `pre-commit, lint, container-build, container-smoke, trivy, release-validation`.
Publishing targets: `github-release, quay.io`.

<!-- END LIT_RELEASE_QUALITY_MODEL -->

<!-- BEGIN LIT_COMPATIBILITY_MATRIX -->

## Compatibility Matrix

| Image Version | Base Image | Runtime | Validation |
|---|---|---|---|
| Latest release | ubi9 | Podman / GitHub Actions | See release evidence |
| Latest release | podman | Podman / GitHub Actions | See release evidence |
| Latest release | docker-buildx | Podman / GitHub Actions | See release evidence |

Validation proof for each released version is stored in the corresponding GitHub Release evidence.

<!-- END LIT_COMPATIBILITY_MATRIX -->

## Release Evidence

Every released version includes immutable release evidence attached to the corresponding GitHub Release.
The evidence records:

- tested matrix combinations
- GitHub Actions run links
- artifact references
- publish status
- security scan status

See [GitHub Releases](../../releases), [RELEASE.md](./RELEASE.md), and [TESTING.md](./TESTING.md) for the release process and validation model.
