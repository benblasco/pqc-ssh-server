# Red Hat Hardened Images: install RPMs in builder installroot, chunkah runtime has no package manager.
# Build (from repo root; chunkah writes oci:out under the mounted build context):
#   podman login registry.access.redhat.com
#   podman build --pull=always --skip-unused-stages=false --security-opt label=disable \
#     -v "$(pwd):/run/src" \
#     --build-arg "CHUNKAH_CONFIG_STR=$(podman image inspect registry.access.redhat.com/hi/core-runtime:latest)" \
#     --build-arg "SSH_UID=$(id -u)" --build-arg "SSH_GID=$(id -g)" \
#     -t pqc-ssh-server -f Containerfile .
ARG CHUNKAH_CONFIG_STR

FROM registry.access.redhat.com/hi/core-runtime:latest AS base

FROM registry.access.redhat.com/hi/core-runtime:latest-builder AS builder
USER 0
ARG SSH_UID=1000
ARG SSH_GID=1000
COPY --from=base / /target/
RUN bash -euo pipefail <<EOF
# Install RPMs into alternate runtime installroot (/target)
# ie everything else in the final container image is in /target
# That tree is later passed to chunkah and becomes the OCI image rootfs.
dnf install -y --installroot=/target --use-host-config \
    --nodocs --setopt=install_weak_deps=False \
    openssh-server crypto-policies
ln -sf /usr/share/crypto-policies/FUTURE/opensshserver.txt \
    /target/etc/crypto-policies/back-ends/opensshserver.config
# Look up sshuser user and group in the target installroot to see if it exists.
if ! chroot /target getent group sshuser >/dev/null; then
    groupadd -R /target -g ${SSH_GID} sshuser
fi
if ! chroot /target getent passwd sshuser >/dev/null; then
    useradd -R /target -l -m -u ${SSH_UID} -g ${SSH_GID} \
        -s /sbin/nologin -d /home/sshuser sshuser
fi
install -d -m 700 -o ${SSH_UID} -g ${SSH_GID} /target/home/sshuser/.ssh
rm -rf /target/usr/share/doc /target/usr/share/info
dnf clean all --installroot=/target
rm -rf /target/var/cache/dnf /target/var/cache/yum /target/var/lib/dnf /target/tmp/*
EOF

# Chunkah is a tool that converts the RPM-installed runtime installroot (/target)
# into an OCI image rootfs.
FROM registry.access.redhat.com/hi/chunkah:latest AS chunked
USER 0
ARG CHUNKAH_CONFIG_STR
RUN --mount=type=bind,target=/run/src,rw \
    --mount=type=bind,from=builder,source=/target,target=/chunkah,ro \
    ["/usr/bin/chunkah", "build", "--rootfs", "/chunkah", "--output", "oci:/run/src/out"]

FROM oci:out

EXPOSE 22

# Match the UID/GID used when chowning authorized_keys (see README / podman-container-yaml).
ARG SSH_UID=1000
ARG SSH_GID=1000

COPY etc/ssh/sshd_config.d/07-access-sshuser.conf \
     etc/ssh/sshd_config.d/08-hostkey-ed25519-only.conf \
     etc/ssh/sshd_config.d/09-ed25519-user-keys.conf \
     etc/ssh/sshd_config.d/10-pq-kex-only.conf \
     etc/ssh/sshd_config.d/99-pubkey-only.conf \
     /etc/ssh/sshd_config.d/

# Host keys: use pod init prepare-hostkeys (podman-container-yaml) or supply /var/lib/sshd before start.
CMD ["/usr/sbin/sshd", "-D"]
