#!/usr/bin/env bash
set -euo pipefail

readonly OUT_DIR=/out
readonly SOURCE_DIR=/src
readonly REBUILD_METADATA=lit.2

require_value() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Error: required build argument ${name} is empty" >&2
    exit 1
  fi
}

assert_exact_output() {
  local expected="$1"
  shift
  local actual

  actual="$("$@" 2>&1)"
  if [ "$actual" != "$expected" ]; then
    printf 'Error: expected exact output:\n%s\nactual output:\n%s\n' \
      "$expected" "$actual" >&2
    exit 1
  fi
  printf '%s\n' "$actual"
}

assert_module_version() {
  local binary="$1"
  local module="$2"
  local expected="$3"
  local actual

  actual="$(
    go version -m "$binary" \
      | awk -v module="$module" '$1 == "dep" && $2 == module { print $3 }'
  )"
  if [ "$actual" != "$expected" ]; then
    printf 'Error: expected %s in %s at %s, got %s\n' \
      "$module" "$binary" "$expected" "${actual:-<missing>}" >&2
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

verify_module_override_scope() {
  local repository="$1"
  local expected_commit="$2"
  shift 2
  local changed_path allowed_path
  local allowed

  test "$(git -C "$repository" rev-parse HEAD)" = "$expected_commit"
  git -C "$repository" diff --cached --quiet
  test -z "$(git -C "$repository" ls-files --others --exclude-standard)"
  while IFS= read -r changed_path; do
    allowed=false
    for allowed_path in "$@"; do
      if [ "$changed_path" = "$allowed_path" ]; then
        allowed=true
        break
      fi
    done
    if [ "$allowed" != true ]; then
      echo "Error: dependency override modified unexpected path ${changed_path}" >&2
      exit 1
    fi
  done < <(git -C "$repository" diff --name-only --diff-filter=ACDMRTUXB)
  git -C "$repository" diff --check
}

for name in \
  GO_VERSION GO_X_CRYPTO_VERSION GO_GRPC_VERSION \
  HELM_VERSION HELM_COMMIT HELM_ORAS_VERSION \
  KUSTOMIZE_VERSION KUSTOMIZE_COMMIT KUSTOMIZE_X_TEXT_VERSION \
  VAULT_VERSION VAULT_COMMIT; do
  require_value "$name"
done

readonly EXPECTED_GO_VERSION="go${GO_VERSION}"
actual_go_version="$(go env GOVERSION)"
if [ "$actual_go_version" != "$EXPECTED_GO_VERSION" ]; then
  echo "Error: expected Go toolchain ${EXPECTED_GO_VERSION}, got ${actual_go_version}" >&2
  exit 1
fi
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
  go get "golang.org/x/crypto@v${GO_X_CRYPTO_VERSION}"
  test "$(go list -m -f '{{.Version}}' oras.land/oras-go/v2)" = "v${HELM_ORAS_VERSION}"
  test "$(go list -m -f '{{.Version}}' golang.org/x/crypto)" = "v${GO_X_CRYPTO_VERSION}"
  verify_module_override_scope \
    "$SOURCE_DIR/helm" "$HELM_COMMIT" go.mod go.sum
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
  verify_module_override_scope \
    "$SOURCE_DIR/kustomize" "$KUSTOMIZE_COMMIT" \
    go.work go.work.sum kustomize/go.mod kustomize/go.sum
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
vault_build_date="$(git -C "$SOURCE_DIR/vault" show -s --format=%cI "$VAULT_COMMIT")"
readonly vault_build_date
test -n "$vault_build_date"
(
  cd "$SOURCE_DIR/vault"
  go get "golang.org/x/crypto@v${GO_X_CRYPTO_VERSION}"
  go get "google.golang.org/grpc@v${GO_GRPC_VERSION}"
  test "$(go list -m -f '{{.Version}}' golang.org/x/crypto)" = "v${GO_X_CRYPTO_VERSION}"
  test "$(go list -m -f '{{.Version}}' google.golang.org/grpc)" = "v${GO_GRPC_VERSION}"
  verify_module_override_scope \
    "$SOURCE_DIR/vault" "$VAULT_COMMIT" go.mod go.sum
  go build \
    -buildvcs=false \
    -trimpath \
    -tags=vault \
    -ldflags="-s -w -X github.com/hashicorp/vault/version.GitCommit=${VAULT_COMMIT} -X github.com/hashicorp/vault/version.BuildDate=${vault_build_date} -X github.com/hashicorp/vault/version.VersionMetadata=${REBUILD_METADATA}" \
    -o "$OUT_DIR/vault" \
    .
)

chmod 0755 "$OUT_DIR/helm" "$OUT_DIR/kustomize" "$OUT_DIR/vault"
assert_module_version \
  "$OUT_DIR/helm" golang.org/x/crypto "v${GO_X_CRYPTO_VERSION}"
assert_module_version \
  "$OUT_DIR/vault" golang.org/x/crypto "v${GO_X_CRYPTO_VERSION}"
assert_module_version \
  "$OUT_DIR/vault" google.golang.org/grpc "v${GO_GRPC_VERSION}"
assert_exact_output \
  "v${HELM_VERSION}+${REBUILD_METADATA}+g${HELM_COMMIT:0:7}" \
  "$OUT_DIR/helm" version --short
assert_exact_output \
  "v${KUSTOMIZE_VERSION}+${REBUILD_METADATA}" \
  "$OUT_DIR/kustomize" version
assert_exact_output \
  "Vault v${VAULT_VERSION}+${REBUILD_METADATA} (${VAULT_COMMIT}), built ${vault_build_date}" \
  "$OUT_DIR/vault" version
