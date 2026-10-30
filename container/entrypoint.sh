#!/bin/sh
set -eu

# Host keys live here so a volume mount does not hide /etc/ssh/sshd_config.d.
KEY_DIR=/var/lib/sshd
KEY="${KEY_DIR}/ssh_host_ed25519_key"

mkdir -p "${KEY_DIR}"
# Only try to chmod if it's not already 700 and the user has permission to do so.
if chmod 700 "${KEY_DIR}" 2>/dev/null; then
  :
fi

if [ ! -f "${KEY}" ]; then
	ssh-keygen -t ed25519 -f "${KEY}" -N ""
fi

exec /usr/sbin/sshd -D "$@"
