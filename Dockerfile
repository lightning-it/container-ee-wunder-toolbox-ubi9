FROM registry.access.redhat.com/ubi9/python-311:9.7-1771432269

LABEL maintainer="Lightning IT"
LABEL org.opencontainers.image.title="ee-wunder-toolbox-ubi9"
LABEL org.opencontainers.image.description="Wunder operations toolbox for offline and restricted environments (ansible-navigator + helper tools, EE-first workflow)."
LABEL org.opencontainers.image.source="https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9"

USER 0
ARG HELM_VERSION=3.19.0
ARG KUSTOMIZE_VERSION=5.8.0
ARG VAULT_VERSION=1.19.0
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

RUN mkdir -p /runner /tmp/ansible /tmp/ansible/tmp && \
    chmod 0775 /runner && \
    chmod 1777 /tmp/ansible /tmp/ansible/tmp

RUN cat > /usr/local/bin/ee-entrypoint <<'EOF' && chmod 0755 /usr/local/bin/ee-entrypoint
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  set -- /bin/bash
fi

# Provide passwd/group entries when container runs with arbitrary UID.
if ! whoami >/dev/null 2>&1; then
  uid="$(id -u)"
  gid="$(id -g)"
  home="${HOME:-/tmp}"

  export NSS_WRAPPER_PASSWD="${TMPDIR:-/tmp}/passwd.nss_wrapper"
  export NSS_WRAPPER_GROUP="${TMPDIR:-/tmp}/group.nss_wrapper"

  (cat /etc/passwd 2>/dev/null || true) > "${NSS_WRAPPER_PASSWD}"
  echo "eeuser:x:${uid}:${gid}:EE User:${home}:/bin/bash" >> "${NSS_WRAPPER_PASSWD}"

  (cat /etc/group 2>/dev/null || true) > "${NSS_WRAPPER_GROUP}"
  echo "eegroup:x:${gid}:" >> "${NSS_WRAPPER_GROUP}"

  wrapper="/usr/lib64/libnss_wrapper.so"
  if [ -f "${wrapper}" ]; then
    export LD_PRELOAD="${wrapper}${LD_PRELOAD:+:${LD_PRELOAD}}"
  fi
fi

exec "$@"
EOF

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
