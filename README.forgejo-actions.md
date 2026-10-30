# Forgejo Actions build

Continuous integration for the container image via [`.forgejo/workflows/container-build.yml`](.forgejo/workflows/container-build.yml). Modeled on [fedora-server-bootc](https://github.com/benblasco/fedora-server-bootc) Forgejo workflow.

## Forgejo repository

| Item | Value |
|------|--------|
| **Forgejo** | [bblasco/pqc-ssh-server](http://opti.lan:3000/bblasco/pqc-ssh-server) |
| **Source (mirror)** | [https://github.com/benblasco/pqc-ssh-server](https://github.com/benblasco/pqc-ssh-server) |
| **Mirror interval** | 8h (same as [fedora-server-bootc](http://opti.lan:3000/bblasco/fedora-server-bootc)) |

This repo on Forgejo is a **read-only pull mirror** of GitHub. Commit on **GitHub `main`**, then either wait for the next mirror pull or run **Sync Mirror** in the Forgejo UI (or `POST /api/v1/repos/bblasco/pqc-ssh-server/mirror-sync`) before Forgejo Actions sees new workflow YAML.

**Actions secrets:** add `SIGNAL_WEBHOOK_URL`, `SIGNAL_NUMBER`, and `SIGNAL_GROUP_ID` under the Forgejo repo (same names and values as [fedora-server-bootc](http://opti.lan:3000/bblasco/fedora-server-bootc) — see [README.forgejo-notification.md](README.forgejo-notification.md)).

## Runner and job image

Deploy and configure Forgejo Actions runners with [podman-container-yaml](https://github.com/benblasco/podman-container-yaml) (`run-podman-quadlet-forgejo.yml`). This workflow uses:

- **`runs-on: pqc-ssh-server`**
- Job container: [`quay.io/containers/aio`](https://quay.io/repository/containers/aio) (Podman + Buildah + Skopeo), same privileged options as the `fedora-server-bootc` label

The workflow installs **`nodejs`**, **`git`**, **`jq`**, and **`curl`** once per job with `microdnf`. Node is required for JavaScript Actions (`actions/checkout`, `redhat-actions/buildah-build`). `jq`/`curl` support registry sizing and Signal notifications.

### Runner label (required one-time setup)

The workflow **`runs-on`** value must match a label registered on your Forgejo runner. Add a **second** label on the existing runner host (no separate runner pod); keep the same aio image tag and container options as bootc.

In [podman-container-yaml `run-podman-quadlet-forgejo.yml`](https://github.com/benblasco/podman-container-yaml/blob/main/run-podman-quadlet-forgejo.yml), under `hosts: forgejo_runner` → `vars.forgejo_runner_labels`:

```yaml
forgejo_runner_labels:
  - "fedora-server-bootc:docker://quay.io/containers/aio:v2026.10.05"
  - "pqc-ssh-server:docker://quay.io/containers/aio:v2026.10.05"
```

Do **not** change `forgejo_runner_container_privileged`, `forgejo_runner_container_network`, or `forgejo_runner_container_options` unless you are fixing runner-wide build issues (Buildah/fuse, SELinux, insecure registries for `micro.lan:5000` / `nuc.lan:5000` are already covered for bootc).

Apply and restart:

```bash
ansible-playbook run-podman-quadlet-forgejo.yml --ask-become-pass
systemctl --user restart forgejo-runner.service
```

Verify on a runner host:

```bash
getenforce
forgejo-runner --version
systemctl --user is-active forgejo-runner.service
```

After changing runner labels or `container:` options in Ansible, re-run the playbook and restart `forgejo-runner.service`. See [README.forgejo.md](https://github.com/benblasco/podman-container-yaml/blob/main/README.forgejo.md) in podman-container-yaml.

**Runner version:** Homelab runners use **forgejo-runner v6.x**, which supports JavaScript actions through **`node20`** only. The workflow pins **`actions/checkout@v4`** (`runs.using: node20`). To use `checkout@v5`/`@v6` (`node24`), upgrade the runner to **[>= v9.1.0](https://codeberg.org/forgejo/runner/releases/tag/v9.1.0)** in podman-container-yaml, then restart `forgejo-runner.service`.

## Repository secrets

Configure the three `SIGNAL_*` repository secrets per [README.forgejo-notification.md](README.forgejo-notification.md) (same values as Jenkins / fedora-server-bootc Forgejo).

## Triggers

- **Push:** commits to **`main`**
- **Schedule:** Wednesday ~06:15 Australia/Melbourne (cron is UTC in the workflow file; bootc runs on Saturday instead)
- **Manual:** `workflow_dispatch` in the Actions tab

Scheduled workflows run only from the **default branch**.

## Image tags and registries

Each successful run pushes:

- `micro.lan:5000/pqc-ssh-server:<branch>`
- `micro.lan:5000/pqc-ssh-server:<branch>-<YYYYMMDD>`
- Same tags mirrored to `nuc.lan:5000` via `skopeo copy`

The CI build does not pass `SSH_UID` / `SSH_GID`; the [Containerfile](Containerfile) defaults (**1000:1000**) match the README.

## Troubleshooting

### `crun: executable file 'node' not found` on a `uses:` step

The aio image is still the right choice for Buildah/Skopeo. Forgejo runs JavaScript Actions inside the job container and needs **`node`** on `PATH`. Install it in the bootstrap `microdnf` step (as in the workflow), or use a custom image that includes aio tools plus Node.js.

### `runs.using` … `got node24` at job setup

Keep **`actions/checkout@v4`** (`node20`) or upgrade forgejo-runner to **>= v9.1.0** on the host.

### Job stuck waiting for a runner

Confirm the **`pqc-ssh-server`** label appears on an online runner in Forgejo and matches `forgejo_runner_labels` after the last playbook run.

Workflow YAML must exist on the repository **default branch** for the Actions tab and `workflow_dispatch` to list it.

## Verify

On a runner host:

```bash
getenforce
podman pull quay.io/containers/aio:latest
podman run --rm quay.io/containers/aio:latest buildah version
podman run --rm quay.io/containers/aio:latest skopeo version
podman run --rm quay.io/containers/aio:latest sh -c 'microdnf install -y nodejs git && node --version && git --version'
```

After a successful run:

```bash
skopeo inspect --tls-verify=false "docker://nuc.lan:5000/pqc-ssh-server:main-$(date +%Y%m%d)" \
  | jq '[.LayersData[].Size] | add' | numfmt --to=iec-i --suffix=B
```

Confirm the Signal group message includes `size=` on success ([README.forgejo-notification.md](README.forgejo-notification.md)).
