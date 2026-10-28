# pqc-ssh-server
Post-quantum capable SSH server container

## Run

Build (default `sshuser` UID/GID **1000**; override if your login user is different):

```bash
podman build -t pqc-ssh-server -f Containerfile \
  --build-arg SSH_UID="$(id -u)" --build-arg SSH_GID="$(id -g)" .
```

Generate an Ed25519 key pair on the client (skip if you already have one):

```bash
ssh-keygen -t ed25519 -f "${HOME}/.ssh/id_ed25519" -C "$(whoami)@$(hostname -f)"
```

Place your **Ed25519 public** key in a host file (mode `600` or `644`, owned by your user):

```bash
install -d -m 700 "${HOME}/.config/pqc-ssh-server"
cp "${HOME}/.ssh/id_ed25519.pub" "${HOME}/.config/pqc-ssh-server/authorized_keys"
chmod 600 "${HOME}/.config/pqc-ssh-server/authorized_keys"
```

Rootless Podman (default user namespace mapping; do **not** use `--userns=keep-id` for this image):

```bash
podman volume create pqc-ssh-hostkeys
podman run -d -p 22222:22 \
  -v pqc-ssh-hostkeys:/var/lib/sshd:Z \
  -v "${HOME}/.config/pqc-ssh-server/authorized_keys:/home/sshuser/.ssh/authorized_keys:ro,Z" \
  --name pqc-ssh-server \
  pqc-ssh-server
```

Connect:

```bash
ssh -p 22222 sshuser@localhost
```

Mounting `/var/lib/sshd` persists the **server host** key. The **client public** key is bind-mounted read-only into `sshuser`’s `authorized_keys`. The numeric UID/GID of `sshuser` in the image must match the owner of that file on the host (hence `SSH_UID` / `SSH_GID` at build time).

## Intrusion blocking (fail2ban / sshguard)

This image **does not** ship **fail2ban** or **sshguard**. Public-key-only login already removes password brute force; either tool would mainly react to **failed key attempts**, invalid users, and scanner noise by **banning source IPs** (usually via nftables/iptables inside the container, often requiring **`--cap-add=NET_ADMIN`** on Podman and an auth log source such as **rsyslog** writing to `/var/log/secure`).

| Tool | Notes |
|------|--------|
| **fail2ban** | Flexible jails; common on Fedora hosts; heavier in a minimal container (Python, jail/filter setup). |
| **sshguard** | Small C daemon focused on log-driven blocks; often simpler for **SSH-only** containers. |

For many deployments here, **network controls** (do not expose SSH broadly, VPN/bastion, host or edge firewall allowlists) matter more than in-container jails. Consider adding one of these tools if the service is **internet-facing** and you want automatic throttling of repeated failures; skip them if SSH is **LAN/VPN-only** and you prefer a minimal image.

## References

- [SSH Post-Quantum Cryptography Configuration Guide](https://gist.github.com/michabbb/5eb580d60ede01dc7d1e5abc72d7eb40)
