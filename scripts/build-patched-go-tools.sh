#!/usr/bin/env bash
set -euo pipefail

readonly OUT_DIR=/out
readonly SOURCE_DIR=/src
readonly REBUILD_METADATA=lit.1

require_value() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Error: required build argument ${name} is empty" >&2
    exit 1
  fi
}

clone_exact() {
  local repository="$1"
  local commit="$2"
  local destination="$3"

  git init --quiet "$destination"
  git -C "$destination" remote add origin "$repository"
  git -C "$destination" fetch --quiet --depth=1 origin "$commit"
  git -C "$destination" -c advice.detachedHead=false checkout --quiet --detach FETCH_HEAD
  test "$(git -C "$destination" rev-parse HEAD)" = "$commit"
  test -z "$(git -C "$destination" status --porcelain=v1)"
}

verify_release_tag() {
  local destination="$1"
  local tag="$2"
  local commit="$3"

  git -C "$destination" fetch --quiet --depth=1 origin \
    "refs/tags/${tag}:refs/tags/lit-release"
  test "$(git -C "$destination" rev-list -n 1 refs/tags/lit-release)" = "$commit"
}

for name in \
  HELM_VERSION HELM_COMMIT HELM_ORAS_VERSION \
  KUSTOMIZE_VERSION KUSTOMIZE_COMMIT KUSTOMIZE_X_TEXT_VERSION \
  VAULT_VERSION VAULT_COMMIT VAULT_BUILD_DATE; do
  require_value "$name"
done

test "$(go env GOVERSION)" = "go1.26.6"
export CGO_ENABLED=0 GOTOOLCHAIN=local
install -d -m 0755 "$OUT_DIR" "$SOURCE_DIR"

clone_exact \
  https://github.com/helm/helm.git \
  "$HELM_COMMIT" \
  "$SOURCE_DIR/helm"
verify_release_tag "$SOURCE_DIR/helm" "v${HELM_VERSION}" "$HELM_COMMIT"
(
  cd "$SOURCE_DIR/helm"
  go get "oras.land/oras-go/v2@v${HELM_ORAS_VERSION}"
  test "$(go list -m -f '{{.Version}}' oras.land/oras-go/v2)" = "v${HELM_ORAS_VERSION}"
  make build \
    BINDIR="$OUT_DIR" \
    VERSION="v${HELM_VERSION}" \
    VERSION_METADATA="$REBUILD_METADATA" \
    GIT_COMMIT="$HELM_COMMIT" \
    GIT_DIRTY=clean \
    CGO_ENABLED=0
)

clone_exact \
  https://github.com/kubernetes-sigs/kustomize.git \
  "$KUSTOMIZE_COMMIT" \
  "$SOURCE_DIR/kustomize"
verify_release_tag \
  "$SOURCE_DIR/kustomize" \
  "kustomize/v${KUSTOMIZE_VERSION}" \
  "$KUSTOMIZE_COMMIT"
(
  cd "$SOURCE_DIR/kustomize/kustomize"
  go get "golang.org/x/text@v${KUSTOMIZE_X_TEXT_VERSION}"
  test "$(go list -m -f '{{.Version}}' golang.org/x/text)" = "v${KUSTOMIZE_X_TEXT_VERSION}"
  go build \
    -buildvcs=false \
    -trimpath \
    -ldflags="-s -w -X sigs.k8s.io/kustomize/api/provenance.version=kustomize/v${KUSTOMIZE_VERSION}+${REBUILD_METADATA}" \
    -o "$OUT_DIR/kustomize" \
    .
)

clone_exact \
  https://github.com/hashicorp/vault.git \
  "$VAULT_COMMIT" \
  "$SOURCE_DIR/vault"
verify_release_tag "$SOURCE_DIR/vault" "v${VAULT_VERSION}" "$VAULT_COMMIT"
(
  cd "$SOURCE_DIR/vault"
  go build \
    -buildvcs=false \
    -trimpath \
    -tags=vault \
    -ldflags="-s -w -X github.com/hashicorp/vault/version.GitCommit=${VAULT_COMMIT} -X github.com/hashicorp/vault/version.BuildDate=${VAULT_BUILD_DATE} -X github.com/hashicorp/vault/version.VersionMetadata=${REBUILD_METADATA}" \
    -o "$OUT_DIR/vault" \
    .
)

chmod 0755 "$OUT_DIR/helm" "$OUT_DIR/kustomize" "$OUT_DIR/vault"
"$OUT_DIR/helm" version --short | grep -F "v${HELM_VERSION}+${REBUILD_METADATA}"
"$OUT_DIR/kustomize" version | grep -F "v${KUSTOMIZE_VERSION}+${REBUILD_METADATA}"
"$OUT_DIR/vault" version | grep -F "Vault v${VAULT_VERSION}+${REBUILD_METADATA}"
"$OUT_DIR/vault" version | grep -F "built ${VAULT_BUILD_DATE}"
