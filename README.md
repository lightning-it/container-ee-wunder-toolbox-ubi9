# container-ee-wunder-toolbox-ubi9
UBI9-based Wunder operations toolbox for Podman-driven automation in offline and restricted environments.
Includes `ansible-navigator` in-container so automation does not depend on host Ansible tooling.

Dependency sources:
- RPM packages: `rpm-packages.txt`
- Python packages: `requirements.txt`

## Included tooling

- `ansible-navigator`
- `helm`
- `kustomize`

Helm and Kustomize are installed in the image during build from official release tarballs and
pinned with `HELM_VERSION` and `KUSTOMIZE_VERSION` in `Dockerfile`.

## Build locally

```bash
docker buildx build -t ee-wunder-toolbox-ubi9:local .
```

## Quick checks

```bash
docker run --rm ee-wunder-toolbox-ubi9:local ansible-navigator --version
docker run --rm ee-wunder-toolbox-ubi9:local helm version --short
docker run --rm ee-wunder-toolbox-ubi9:local kustomize version
```

## Helm usage

Basic Helm command:

```bash
docker run --rm ee-wunder-toolbox-ubi9:local helm version --short
```

Run against local kubeconfig:

```bash
docker run --rm \
  -v "$HOME/.kube:/runner/.kube:ro,Z" \
  -e KUBECONFIG=/runner/.kube/config \
  ee-wunder-toolbox-ubi9:local \
  helm list -A
```

## Kustomize usage

Basic Kustomize command:

```bash
docker run --rm -v "$PWD":/runner/project:ro,Z ee-wunder-toolbox-ubi9:local kustomize build /runner/project
```
