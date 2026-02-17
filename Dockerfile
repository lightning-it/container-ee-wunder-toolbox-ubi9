FROM quay.io/l-it/ee-wunder-ansible-ubi9:v1.7.0

LABEL maintainer="Lightning IT"
LABEL org.opencontainers.image.title="ee-wunder-toolbox-ubi9"
LABEL org.opencontainers.image.description="Wunder operations toolbox based on ee-wunder-ansible-ubi9 for offline and restricted environments."
LABEL org.opencontainers.image.source="https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9"

USER 0
ARG HELM_VERSION=3.19.0
ARG KUSTOMIZE_VERSION=5.8.0

COPY rpm-packages.txt /tmp/rpm-packages.txt
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
    tar -xzf /tmp/helm.tar.gz -C /tmp; \
    tar -xzf /tmp/kustomize.tar.gz -C /tmp kustomize; \
    install -m 0755 "/tmp/linux-${tool_arch}/helm" /usr/local/bin/helm; \
    install -m 0755 /tmp/kustomize /usr/local/bin/kustomize; \
    rm -rf /tmp/helm.tar.gz /tmp/kustomize.tar.gz /tmp/kustomize "/tmp/linux-${tool_arch}"; \
    ansible-navigator --version; \
    helm version --short; \
    kustomize version; \
    dnf clean all; \
    rm -rf /var/cache/dnf /var/cache/yum; \
    rm -f /tmp/rpm-packages.txt /tmp/requirements.txt

USER runner
WORKDIR /runner

ENTRYPOINT ["/usr/local/bin/ee-entrypoint"]
CMD ["/bin/bash"]
