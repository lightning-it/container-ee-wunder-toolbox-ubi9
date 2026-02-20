# container-ee-wunder-toolbox-ubi9
UBI9-based Wunder operations toolbox for Podman-driven automation in offline and restricted environments.
Includes `ansible-navigator` in-container so automation does not depend on host Ansible tooling.

Dependency sources:
- RPM packages: `rpm-packages.txt`
- COPR RPM pins: `copr-packages.txt`
- Python packages: `requirements.txt`

## Included tooling

- `ansible-navigator`
- `helm`
- `kustomize`
- `vault`
- `modulix-scripts` (installed from Fedora COPR)

Helm and Kustomize are installed in the image during build from official release tarballs and
pinned with `HELM_VERSION` and `KUSTOMIZE_VERSION` in `Dockerfile`.

`modulix-scripts` is installed from COPR via `dnf copr enable` and the pinned
package list in `copr-packages.txt`.
Default COPR settings are configurable with build args:

- `MODULIX_COPR_OWNER` (default: `litroc`)
- `MODULIX_COPR_PROJECT` (default: `modulix`)
- `MODULIX_COPR_CHROOT` (default: `epel-9-x86_64`)

The package installs script payload under `/opt/modulix` and exposes
command wrappers in `/usr/bin` (for example `ansible-nav` and `test-ansible.sh`).

## Build locally

```bash
podman build --format docker -t ee-wunder-toolbox-ubi9:local .
```

Use a different COPR project:

```bash
podman build --format docker \
  --build-arg MODULIX_COPR_OWNER=litroc \
  --build-arg MODULIX_COPR_PROJECT=modulix \
  --build-arg MODULIX_COPR_CHROOT=epel-9-x86_64 \
  -t ee-wunder-toolbox-ubi9:local .
```

## Quick checks

```bash
podman run --rm ee-wunder-toolbox-ubi9:local ansible-navigator --version
podman run --rm ee-wunder-toolbox-ubi9:local helm version --short
podman run --rm ee-wunder-toolbox-ubi9:local kustomize version
podman run --rm ee-wunder-toolbox-ubi9:local vault --version
podman run --rm ee-wunder-toolbox-ubi9:local sh -lc 'command -v ansible-nav && command -v test-ansible.sh'
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
