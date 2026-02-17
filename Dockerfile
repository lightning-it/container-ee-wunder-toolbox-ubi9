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

RUN set -euo pipefail; \
    xargs -r dnf -y install --allowerasing < /tmp/rpm-packages.txt; \
    python3 -m pip install --no-cache-dir -r /tmp/requirements.txt; \
    arch="$(uname -m)"; \
    case "${arch}" in \
      x86_64) helm_arch="amd64" ;; \
      aarch64|arm64) helm_arch="arm64" ;; \
      *) echo "Unsupported arch: ${arch}" >&2; exit 1 ;; \
    esac; \
    helm_url="https://get.helm.sh/helm-v${HELM_VERSION}-linux-${helm_arch}.tar.gz"; \
    kustomize_url="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${helm_arch}.tar.gz"; \
    HELM_URL="${helm_url}" KUSTOMIZE_URL="${kustomize_url}" python3 - <<'PY' && \
    tar -xzf /tmp/helm.tar.gz -C /tmp && \
    tar -xzf /tmp/kustomize.tar.gz -C /tmp kustomize && \
    install -m 0755 "/tmp/linux-${helm_arch}/helm" /usr/local/bin/helm && \
    install -m 0755 /tmp/kustomize /usr/local/bin/kustomize && \
    rm -rf /tmp/helm.tar.gz /tmp/kustomize.tar.gz /tmp/kustomize "/tmp/linux-${helm_arch}" && \
    ansible-navigator --version && \
    helm version --short && \
    kustomize version && \
    dnf clean all && \
    rm -rf /var/cache/dnf /var/cache/yum && \
    rm -f /tmp/rpm-packages.txt /tmp/requirements.txt
import os
import urllib.request

downloads = [
    (os.environ["HELM_URL"], "/tmp/helm.tar.gz"),
    (os.environ["KUSTOMIZE_URL"], "/tmp/kustomize.tar.gz"),
]
for url, out_path in downloads:
    with urllib.request.urlopen(url) as resp, open(out_path, "wb") as handle:
        handle.write(resp.read())
PY

USER runner
WORKDIR /runner

ENTRYPOINT ["/usr/local/bin/ee-entrypoint"]
CMD ["/bin/bash"]
