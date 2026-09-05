# syntax=docker/dockerfile:1.26@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
ARG GO_VERSION=1.26.6
FROM golang:${GO_VERSION}-bookworm@sha256:116d58cbd88c1297624acc6e967a060012422bacf9930927e23fb719189c6f36 AS patched-tools

ARG GO_VERSION
ARG GO_X_CRYPTO_VERSION=0.55.0
ARG GO_GRPC_VERSION=1.83.2
ARG HELM_VERSION=4.2.4
ARG HELM_COMMIT=3900f434fd3ef2b84065dc04508df48f288dba00
ARG HELM_ORAS_VERSION=2.6.2
ARG KUSTOMIZE_VERSION=5.8.1
ARG KUSTOMIZE_COMMIT=9790a1c3efd2fd35f1b768d495112834176581c1
ARG KUSTOMIZE_X_TEXT_VERSION=0.39.0
ARG VAULT_VERSION=2.0.4
ARG VAULT_COMMIT=c9e9d1d4ddd4b55aae79a8949adffa9e96338720
ARG VAULT_THRIFT_VERSION=0.24.0

COPY scripts/build-patched-go-tools.sh /usr/local/bin/build-patched-go-tools
RUN chmod 0755 /usr/local/bin/build-patched-go-tools && \
    GO_VERSION="${GO_VERSION}" /usr/local/bin/build-patched-go-tools

FROM registry.access.redhat.com/ubi9/python-311:9.8-1779945715@sha256:a0bdb55576fc5b8d6704279307817828ef027e1065533ceba133fe9516003a6c

LABEL maintainer="Lightning IT"
LABEL org.opencontainers.image.title="ee-wunder-toolbox-ubi9"
LABEL org.opencontainers.image.description="Wunder operations toolbox for offline and restricted environments (ansible-navigator + helper tools, EE-first workflow)."
LABEL org.opencontainers.image.source="https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9"

USER 0
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG MODULIX_COPR_OWNER=litroc
ARG MODULIX_COPR_PROJECT=modulix
ARG MODULIX_COPR_CHROOT=auto
ARG ONIGURUMA_HEADER_SHA256=7fb0a26767a8d2c31af3739ddd452b63860d520ef4b54fffbf55affd70550d8a

COPY rpm-packages.txt /tmp/rpm-packages.txt
COPY rpm-security-updates.lock /tmp/rpm-security-updates.lock
COPY copr-packages.txt /tmp/copr-packages.txt
COPY requirements.txt /tmp/requirements.txt
COPY requirements.lock /tmp/requirements.lock
COPY scripts/ee-entrypoint.sh /usr/local/bin/ee-entrypoint
COPY --from=patched-tools /out/helm /usr/local/bin/helm
COPY --from=patched-tools /out/kustomize /usr/local/bin/kustomize
COPY --from=patched-tools /out/vault /usr/local/bin/vault

RUN set -euo pipefail; \
    chmod 0755 /usr/local/bin/ee-entrypoint; \
    xargs -r dnf -y install --allowerasing < /tmp/rpm-packages.txt; \
    dnf -y install --allowerasing ca-certificates curl tar unzip; \
    dnf -y install --allowerasing gcc make python3-devel; \
    curl -fsSL \
      "https://raw.githubusercontent.com/kkos/oniguruma/v6.9.6/src/oniguruma.h" \
      -o /usr/local/include/oniguruma.h; \
    printf '%s  %s\n' "${ONIGURUMA_HEADER_SHA256}" /usr/local/include/oniguruma.h | sha256sum --check --status; \
    ln -sf /usr/lib64/libonig.so.5 /usr/lib64/libonig.so; \
    PIP_NO_BINARY=onigurumacffi python3 -m pip install --no-cache-dir --require-hashes -r /tmp/requirements.lock; \
    rm -f /usr/local/include/oniguruma.h /usr/lib64/libonig.so; \
    dnf -y remove gcc make python3-devel; \
    arch="$(uname -m)"; \
    case "${arch}" in \
      x86_64) copr_chroot_default="epel-9-x86_64" ;; \
      aarch64|arm64) copr_chroot_default="epel-9-aarch64" ;; \
      *) echo "Unsupported arch: ${arch}" >&2; exit 1 ;; \
    esac; \
    if [ "${MODULIX_COPR_CHROOT}" = "auto" ]; then \
      modulix_copr_chroot="${copr_chroot_default}"; \
    else \
      modulix_copr_chroot="${MODULIX_COPR_CHROOT}"; \
    fi; \
    chmod 0755 /usr/local/bin/helm /usr/local/bin/kustomize /usr/local/bin/vault; \
    dnf -y install --allowerasing 'dnf-command(copr)'; \
    echo "Using COPR chroot: ${modulix_copr_chroot}"; \
    dnf -y copr enable "${MODULIX_COPR_OWNER}/${MODULIX_COPR_PROJECT}" "${modulix_copr_chroot}"; \
    xargs -r dnf -y install --allowerasing < /tmp/copr-packages.txt; \
    locked_security_pkgs=(); \
    lock_line=0; \
    while read -r package evr extra; do \
      lock_line=$((lock_line + 1)); \
      [[ -z "${package}" || "${package}" == \#* ]] && continue; \
      if ! [[ "${package}" =~ ^[A-Za-z0-9+._-]+$ ]]; then \
        echo "Invalid RPM package at lock line ${lock_line}: ${package}" >&2; \
        exit 1; \
      fi; \
      if ! [[ "${evr}" =~ ^[0-9]+:[A-Za-z0-9+._~^-]+-[A-Za-z0-9+._~^-]+$ ]]; then \
        echo "Invalid RPM EVR at lock line ${lock_line}: ${evr:-<missing>}" >&2; \
        exit 1; \
      fi; \
      if [[ -n "${extra:-}" ]]; then \
        echo "Unexpected field at RPM lock line ${lock_line}: ${extra}" >&2; \
        exit 1; \
      fi; \
      if rpm -q "${package}" >/dev/null; then \
        locked_security_pkgs+=("${package}-${evr}"); \
      fi; \
    done < /tmp/rpm-security-updates.lock; \
    if (( ${#locked_security_pkgs[@]} )); then \
      dnf -y install --allowerasing "${locked_security_pkgs[@]}"; \
    fi; \
    while read -r package evr extra; do \
      [[ -z "${package}" || "${package}" == \#* ]] && continue; \
      if rpm -q "${package}" >/dev/null; then \
        actual_evr="$(rpm -q --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}\n' "${package}")"; \
        if [[ "${actual_evr}" != "${evr}" ]]; then \
          echo "RPM security lock mismatch for ${package}: expected ${evr}, got ${actual_evr}" >&2; \
          exit 1; \
        fi; \
      fi; \
    done < /tmp/rpm-security-updates.lock; \
    ansible-navigator --version; \
    ansible-doc --version; \
    helm version --short; \
    kustomize version; \
    vault --version; \
    podman --version; \
    command -v ansible-nav; \
    command -v ansible-nav-local; \
    dnf clean all; \
    rm -rf /var/cache/dnf /var/cache/yum; \
    rm -f /tmp/rpm-packages.txt /tmp/rpm-security-updates.lock /tmp/copr-packages.txt /tmp/requirements.txt /tmp/requirements.lock

RUN mkdir -p /runner /runner/.config /runner/.local/share/containers /tmp/ansible /tmp/ansible/tmp && \
    chmod 0777 /runner /runner/.config /runner/.local /runner/.local/share /runner/.local/share/containers && \
    chmod 1777 /tmp/ansible /tmp/ansible/tmp

RUN id -u runner >/dev/null 2>&1 || useradd -u 1000 -m -d /runner runner && \
    chown -R runner:runner /runner /tmp/ansible

ENV HOME=/runner \
    ANSIBLE_LOCAL_TEMP=/tmp/ansible/tmp \
    ANSIBLE_REMOTE_TEMP=/tmp/ansible/tmp \
    ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections:/usr/share/automation-controller/collections:/runner/project/collections-dev:/runner/project/collections:/runner/collections

USER runner
WORKDIR /runner

ENTRYPOINT ["/usr/local/bin/ee-entrypoint"]
CMD ["/bin/bash"]
