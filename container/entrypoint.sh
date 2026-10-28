#!/bin/sh
set -eu

# Host keys live here so a volume mount does not hide /etc/ssh/sshd_config.d.
KEY_DIR=/var/lib/sshd
KEY="${KEY_DIR}/ssh_host_ed25519_key"

mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

if [ ! -f "${KEY}" ]; then
	ssh-keygen -t ed25519 -f "${KEY}" -N ""
fi

exec /usr/sbin/sshd -D "$@"
