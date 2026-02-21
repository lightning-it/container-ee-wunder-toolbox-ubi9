FROM quay.io/l-it/ee-wunder-ansible-ubi9:v1.8.0

LABEL maintainer="Lightning IT"
LABEL org.opencontainers.image.title="ee-wunder-toolbox-ubi9"
LABEL org.opencontainers.image.description="Wunder operations toolbox based on ee-wunder-ansible-ubi9 for offline and restricted environments."
LABEL org.opencontainers.image.source="https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9"

USER 0
ARG HELM_VERSION=4.1.1
ARG KUSTOMIZE_VERSION=5.8.1
ARG VAULT_VERSION=1.21.2
ARG MODULIX_COPR_OWNER=litroc
ARG MODULIX_COPR_PROJECT=modulix
ARG MODULIX_COPR_CHROOT=epel-9-x86_64

COPY rpm-packages.txt /tmp/rpm-packages.txt
COPY copr-packages.txt /tmp/copr-packages.txt
COPY requirements.txt /tmp/requirements.txt

RUN set -eu; \
    xargs -r dnf -y install --allowerasing < /tmp/rpm-packages.txt; \
    dnf -y install --allowerasing gcc make python3-devel; \
    curl -fsSL \
      "https://raw.githubusercontent.com/kkos/oniguruma/v6.9.6/src/oniguruma.h" \
      -o /usr/local/include/oniguruma.h; \
    ln -sf /usr/lib64/libonig.so.5 /usr/lib64/libonig.so; \
    PIP_NO_BINARY=onigurumacffi python3 -m pip install --no-cache-dir -r /tmp/requirements.txt; \
    rm -f /usr/local/include/oniguruma.h /usr/lib64/libonig.so; \
    dnf -y remove gcc make python3-devel; \
    arch="$(uname -m)"; \
    case "${arch}" in \
      x86_64) tool_arch="amd64" ;; \
      aarch64|arm64) tool_arch="arm64" ;; \
      *) echo "Unsupported arch: ${arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${tool_arch}.tar.gz" \
      -o /tmp/helm.tar.gz; \
    curl -fsSL \
      "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${tool_arch}.tar.gz" \
      -o /tmp/kustomize.tar.gz; \
    curl -fsSL \
      "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${tool_arch}.zip" \
      -o /tmp/vault.zip; \
    tar -xzf /tmp/helm.tar.gz -C /tmp; \
    tar -xzf /tmp/kustomize.tar.gz -C /tmp kustomize; \
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/vault.zip').extract('vault', '/tmp')"; \
    install -m 0755 "/tmp/linux-${tool_arch}/helm" /usr/local/bin/helm; \
    install -m 0755 /tmp/kustomize /usr/local/bin/kustomize; \
    install -m 0755 /tmp/vault /usr/local/bin/vault; \
    rm -rf /tmp/helm.tar.gz /tmp/kustomize.tar.gz /tmp/vault.zip /tmp/kustomize /tmp/vault "/tmp/linux-${tool_arch}"; \
    dnf -y install --allowerasing 'dnf-command(copr)'; \
    dnf -y copr enable "${MODULIX_COPR_OWNER}/${MODULIX_COPR_PROJECT}" "${MODULIX_COPR_CHROOT}"; \
    xargs -r dnf -y install --allowerasing < /tmp/copr-packages.txt; \
    ansible-navigator --version; \
    helm version --short; \
    kustomize version; \
    vault --version; \
    command -v ansible-nav; \
    command -v test-ansible.sh; \
    dnf clean all; \
    rm -rf /var/cache/dnf /var/cache/yum; \
    rm -f /tmp/rpm-packages.txt /tmp/copr-packages.txt /tmp/requirements.txt

USER runner
WORKDIR /runner

ENTRYPOINT ["/usr/local/bin/ee-entrypoint"]
CMD ["/bin/bash"]
