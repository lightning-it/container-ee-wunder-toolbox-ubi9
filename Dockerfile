FROM quay.io/l-it/ee-wunder-ansible-ubi9:v1.7.0

LABEL maintainer="Lightning IT"
LABEL org.opencontainers.image.title="ee-wunder-toolbox-ubi9"
LABEL org.opencontainers.image.description="Wunder operations toolbox based on ee-wunder-ansible-ubi9 for offline and restricted environments."
LABEL org.opencontainers.image.source="https://github.com/lightning-it/container-ee-wunder-toolbox-ubi9"

USER 0

COPY rpm-packages.txt /tmp/rpm-packages.txt
COPY requirements.txt /tmp/requirements.txt

RUN xargs -r dnf -y install --allowerasing < /tmp/rpm-packages.txt && \
    python3 -m pip install --no-cache-dir -r /tmp/requirements.txt && \
    ansible-navigator --version && \
    dnf clean all && \
    rm -rf /var/cache/dnf /var/cache/yum && \
    rm -f /tmp/rpm-packages.txt /tmp/requirements.txt

USER runner
WORKDIR /runner

ENTRYPOINT ["/usr/local/bin/ee-entrypoint"]
CMD ["/bin/bash"]
