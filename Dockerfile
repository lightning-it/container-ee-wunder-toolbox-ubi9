FROM registry.access.redhat.com/ubi9/python-311:9.8-1779945715@sha256:a0bdb55576fc5b8d6704279307817828ef027e1065533ceba133fe9516003a6c

LABEL maintainer="Lightning IT"
LABEL org.opencontainers.image.title="ee-wunder-toolbox-ubi9"
LABEL org.opencontainers.image.description="Wunder operations toolbox for offline and restricted environments (ansible-navigator + helper tools, EE-first workflow)."
LABEL org.opencontainers.image.source="https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9"

USER 0
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG HELM_VERSION=4.2.2
ARG KUSTOMIZE_VERSION=5.8.1
ARG VAULT_VERSION=2.0.3
ARG MODULIX_COPR_OWNER=litroc
ARG MODULIX_COPR_PROJECT=modulix
ARG MODULIX_COPR_CHROOT=auto
ARG ONIGURUMA_HEADER_SHA256=7fb0a26767a8d2c31af3739ddd452b63860d520ef4b54fffbf55affd70550d8a

COPY rpm-packages.txt /tmp/rpm-packages.txt
COPY copr-packages.txt /tmp/copr-packages.txt
COPY requirements.txt /tmp/requirements.txt
COPY requirements.lock /tmp/requirements.lock
COPY scripts/container-download-verified.sh /usr/local/lib/container-download-verified.sh
COPY scripts/ee-entrypoint.sh /usr/local/bin/ee-entrypoint

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
      x86_64) tool_arch="amd64"; copr_chroot_default="epel-9-x86_64" ;; \
      aarch64|arm64) tool_arch="arm64"; copr_chroot_default="epel-9-aarch64" ;; \
      *) echo "Unsupported arch: ${arch}" >&2; exit 1 ;; \
    esac; \
    if [ "${MODULIX_COPR_CHROOT}" = "auto" ]; then \
      modulix_copr_chroot="${copr_chroot_default}"; \
    else \
      modulix_copr_chroot="${MODULIX_COPR_CHROOT}"; \
    fi; \
    source /usr/local/lib/container-download-verified.sh; \
    download_verified \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${tool_arch}.tar.gz" \
      /tmp/helm.tar.gz \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${tool_arch}.tar.gz.sha256sum" \
      "helm-v${HELM_VERSION}-linux-${tool_arch}.tar.gz"; \
    download_verified \
      "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${tool_arch}.tar.gz" \
      /tmp/kustomize.tar.gz \
      "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v${KUSTOMIZE_VERSION}/checksums.txt" \
      "kustomize_v${KUSTOMIZE_VERSION}_linux_${tool_arch}.tar.gz"; \
    download_verified \
      "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${tool_arch}.zip" \
      /tmp/vault.zip \
      "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS" \
      "vault_${VAULT_VERSION}_linux_${tool_arch}.zip"; \
    tar -xzf /tmp/helm.tar.gz -C /tmp; \
    tar -xzf /tmp/kustomize.tar.gz -C /tmp kustomize; \
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/vault.zip').extract('vault', '/tmp')"; \
    install -m 0755 "/tmp/linux-${tool_arch}/helm" /usr/local/bin/helm; \
    install -m 0755 /tmp/kustomize /usr/local/bin/kustomize; \
    install -m 0755 /tmp/vault /usr/local/bin/vault; \
    rm -rf /tmp/helm.tar.gz /tmp/kustomize.tar.gz /tmp/vault.zip /tmp/kustomize /tmp/vault "/tmp/linux-${tool_arch}"; \
    dnf -y install --allowerasing 'dnf-command(copr)'; \
    echo "Using COPR chroot: ${modulix_copr_chroot}"; \
    dnf -y copr enable "${MODULIX_COPR_OWNER}/${MODULIX_COPR_PROJECT}" "${modulix_copr_chroot}"; \
    xargs -r dnf -y install --allowerasing < /tmp/copr-packages.txt; \
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
    rm -f /tmp/rpm-packages.txt /tmp/copr-packages.txt /tmp/requirements.txt /tmp/requirements.lock

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
