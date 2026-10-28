FROM quay.io/fedora/fedora-minimal:latest

# Map host 22222 to container 22 at run time, e.g.:
#   podman run -d -p 22222:22 --name pqc-ssh-server IMAGE
EXPOSE 22

# Match the UID/GID of the host user who owns the bind-mounted authorized_keys file.
ARG SSH_UID=1000
ARG SSH_GID=1000

RUN <<EOF
set -euo pipefail
microdnf -y install \
    openssh-server
ln -sf /usr/share/crypto-policies/FUTURE/opensshserver.txt \
    /etc/crypto-policies/back-ends/opensshserver.config
if ! getent group sshuser >/dev/null; then
    groupadd -g ${SSH_GID} sshuser
fi
if ! getent passwd sshuser >/dev/null; then
    useradd -m -u ${SSH_UID} -g ${SSH_GID} -s /bin/sh -d /home/sshuser sshuser
fi
install -d -m 700 -o ${SSH_UID} -g ${SSH_GID} /home/sshuser/.ssh
microdnf clean all
rm -rf /var/cache/yum /var/cache/dnf /var/lib/dnf /tmp/*
EOF

COPY etc/ssh/sshd_config.d/07-access-sshuser.conf \
     etc/ssh/sshd_config.d/08-hostkey-ed25519-only.conf \
     etc/ssh/sshd_config.d/09-ed25519-user-keys.conf \
     etc/ssh/sshd_config.d/10-pq-kex-only.conf \
     etc/ssh/sshd_config.d/99-pubkey-only.conf \
     /etc/ssh/sshd_config.d/

COPY --chmod=755 container/entrypoint.sh /usr/local/bin/entrypoint.sh

# Entrypoint is used to generate the host key if it does not exist.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
