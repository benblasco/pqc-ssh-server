# Forgejo Actions build

Continuous integration for the container image via
[`.forgejo/workflows/container-build.yml`](.forgejo/workflows/container-build.yml). Modeled on
[fedora-server-bootc](https://github.com/benblasco/fedora-server-bootc) Forgejo workflow.

## Forgejo repository

| Item | Value |
|------|--------|
| **Forgejo** | [bblasco/pqc-ssh-server](http://opti.lan:3000/bblasco/pqc-ssh-server) |
| **Source (mirror)** | [https://github.com/benblasco/pqc-ssh-server](https://github.com/benblasco/pqc-ssh-server) |
| **Mirror interval** | 8h (same as [fedora-server-bootc](http://opti.lan:3000/bblasco/fedora-server-bootc)) |

This repo on Forgejo is a **read-only pull mirror** of GitHub. Commit on **GitHub `main`**, then either
wait for the next mirror pull or run **Sync Mirror** in the Forgejo UI (or
`POST /api/v1/repos/bblasco/pqc-ssh-server/mirror-sync`) before Forgejo Actions sees new workflow YAML.

**Actions secrets:** add `SIGNAL_WEBHOOK_URL`, `SIGNAL_NUMBER`, and `SIGNAL_GROUP_ID` under the Forgejo repo
(same names and values as [fedora-server-bootc](http://opti.lan:3000/bblasco/fedora-server-bootc) — see
[README.forgejo-notification.md](README.forgejo-notification.md)). You do **not** need Red Hat registry
username/password secrets for the current build (see [Red Hat registry (Hardened Images)](#red-hat-registry-hardened-images)).

## Runner and job image

Deploy and configure Forgejo Actions runners with
[podman-container-yaml](https://github.com/benblasco/podman-container-yaml)
(`run-podman-quadlet-forgejo.yml`). This workflow uses:

- **`runs-on: pqc-ssh-server`**
- Job container: [`quay.io/containers/aio`](https://quay.io/repository/containers/aio) (Podman + Buildah +
  Skopeo), same privileged options as the `fedora-server-bootc` label

The workflow installs **`nodejs`**, **`git`**, **`jq`**, and **`curl`** once per job with `microdnf`. Node is
required for JavaScript Actions (`actions/checkout`, `redhat-actions/buildah-build`). `jq`/`curl` support
registry sizing and Signal notifications.

### Runner label (required one-time setup)

The workflow **`runs-on`** value must match a label registered on your Forgejo runner. Add a **second** label on
the existing runner host (no separate runner pod); keep the same aio image tag and container options as bootc.

In [podman-container-yaml `run-podman-quadlet-forgejo.yml`](https://github.com/benblasco/podman-container-yaml/blob/main/run-podman-quadlet-forgejo.yml),
under `hosts: forgejo_runner` → `vars.forgejo_runner_labels`:

```yaml
forgejo_runner_labels:
  - "fedora-server-bootc:docker://quay.io/containers/aio:v2026.10.05"
  - "pqc-ssh-server:docker://quay.io/containers/aio:v2026.10.05"
```

Do **not** change `forgejo_runner_container_privileged`, `forgejo_runner_container_network`, or
`forgejo_runner_container_options` unless you are fixing runner-wide build issues (Buildah/fuse, SELinux,
insecure registries for `micro.lan:5000` / `nuc.lan:5000` are already covered for bootc).

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

After changing runner labels or `container:` options in Ansible, re-run the playbook and restart
`forgejo-runner.service`. See
[README.forgejo.md](https://github.com/benblasco/podman-container-yaml/blob/main/README.forgejo.md) in
podman-container-yaml.

**Runner version:** Homelab runners use **forgejo-runner v6.x**, which supports JavaScript actions through
**`node20`** only. The workflow pins **`actions/checkout@v4`** (`runs.using: node20`). To use
`checkout@v5`/`@v6` (`node24`), upgrade the runner to
**[>= v9.1.0](https://codeberg.org/forgejo/runner/releases/tag/v9.1.0)** in podman-container-yaml, then restart
`forgejo-runner.service`.

## Repository secrets

Configure the three `SIGNAL_*` repository secrets per [README.forgejo-notification.md](README.forgejo-notification.md)
(same values as Jenkins / fedora-server-bootc Forgejo).

Homelab registry credentials for `micro.lan:5000` / `nuc.lan:5000` belong on the runner host (`registries.conf`,
Ansible `podman_registry_*`, and similar in podman-container-yaml), **not** as Forgejo secrets for this workflow.

## Red Hat registry (Hardened Images)

The [Containerfile](Containerfile) pulls `hi/core-runtime`, `hi/core-runtime-builder`, and `hi/chunkah` from
**`registry.access.redhat.com`**, not **`registry.redhat.io`**. Red Hat documents two product registries ([Container
Registry Authentication](https://access.redhat.com/articles/RegistryAuthentication)):

| Registry | Authentication |
| --- | --- |
| `registry.access.redhat.com` | Unauthenticated pulls supported (what this repo uses) |
| `registry.redhat.io` | Red Hat login or [registry service account](https://access.redhat.com/articles/3399531) token required |

**Forgejo Actions secrets:** do **not** add your Red Hat Customer Portal username and password for the current
workflow. No `RH_REGISTRY_*` (or similar) secrets are required while all `FROM` lines stay on
`registry.access.redhat.com`.

**Workflow `podman login` / `buildah login` step:** **not needed** today. The **Build image with Buildah** step runs
`buildah bud` with `--pull=always`, which pulls those base images without logging in. Hardened Images also require
`-v "${GITHUB_WORKSPACE}:/run/src:Z"`, `--skip-unused-stages=false`, `--security-opt label=disable`, and
`CHUNKAH_CONFIG_STR` (see [Troubleshooting](#open-indexjson--from-ociout) and the [Containerfile](Containerfile)
header). The earlier **Workaround empty docker config** step writes a minimal `~/.docker/config.json` for the
JavaScript **checkout** action; that does not block unauthenticated pulls from `registry.access.redhat.com`.

Verify on a runner host (or inside the aio image) before relying on CI:

```bash
buildah pull registry.access.redhat.com/hi/core-runtime:latest
buildah pull registry.access.redhat.com/hi/chunkah:latest
getenforce
```

If both pulls succeed, CI needs no Red Hat login step.

**If you change the Containerfile to `registry.redhat.io`:** add Forgejo repository secrets (prefer a **registry
service account** token as the password—not your personal portal password), and insert a login step **before**
`Build image with Buildah`, for example:

```yaml
      - name: Log in to registry.redhat.io
        env:
          RH_REGISTRY_USERNAME: ${{ secrets.RH_REGISTRY_USERNAME }}
          RH_REGISTRY_PASSWORD: ${{ secrets.RH_REGISTRY_PASSWORD }}
        run: buildah login -u "$RH_REGISTRY_USERNAME" -p "$RH_REGISTRY_PASSWORD" registry.redhat.io
```

That is only required for `registry.redhat.io` (or other authenticated registries), not for the current
`registry.access.redhat.com` Hardened Images paths.

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

The CI build does not pass `SSH_UID` / `SSH_GID`; the [Containerfile](Containerfile) defaults (**1000:1000**)
match the README.

## Troubleshooting

### `crun: executable file 'node' not found` on a `uses:` step

The aio image is still the right choice for Buildah/Skopeo. Forgejo runs JavaScript Actions inside the job
container and needs **`node`** on `PATH`. Install it in the bootstrap `microdnf` step (as in the workflow), or
use a custom image that includes aio tools plus Node.js.

### `runs.using` … `got node24` at job setup

Keep **`actions/checkout@v4`** (`node20`) or upgrade forgejo-runner to **>= v9.1.0** on the host.

### Job stuck waiting for a runner

Confirm the **`pqc-ssh-server`** label appears on an online runner in Forgejo and matches
`forgejo_runner_labels` after the last playbook run.

### Build fails pulling `registry.access.redhat.com/hi/...`

Confirm unauthenticated pull works on the runner (`buildah pull` commands in [Red Hat registry
(Hardened Images)](#red-hat-registry-hardened-images)). HTTP **401** / **403** on **`registry.redhat.io`** means the
Containerfile or tooling is hitting the authenticated registry—either switch `FROM` URLs back to
`registry.access.redhat.com` or add registry service account secrets and a `buildah login` step as documented there.
Do not store a personal Customer Portal password in Forgejo if a registry token is available.

### `open index.json` / `FROM oci:out`

Symptom in the build log:

```text
[4/4] STEP 1/6: FROM oci:out
Error: creating build container: open index.json: no such file or directory
```

The [Containerfile](Containerfile) ends with `FROM oci:out`. That stage reads an OCI image layout in **`out/`** at
the repository root—the output of the **chunked** (chunkah) stage. Chunkah only writes that tree into the checkout when
the build context is bind-mounted at `/run/src` during `buildah bud` (same path as in the Containerfile
`oci:/run/src/out` output).

A plain `buildah bud` or `redhat-actions/buildah-build` with only `--pull=always` is **not** enough. CI must pass at
least:

- `-v "${GITHUB_WORKSPACE}:/run/src:Z"`
- `--skip-unused-stages=false` (so the chunkah stage runs)
- `--security-opt label=disable` on SELinux-enforcing runners
- `--build-arg CHUNKAH_CONFIG_STR=$(buildah inspect … hi/core-runtime:latest)` (metadata for chunkah)

The workflow [`.forgejo/workflows/container-build.yml`](.forgejo/workflows/container-build.yml) implements this
explicitly. Locally, use the command block at the top of the [Containerfile](Containerfile) or see [README.md](README.md)
(Red Hat Hardened Images / `FROM oci:out`).

Workflow YAML must exist on the repository **default branch** for the Actions tab and `workflow_dispatch` to
list it.

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

Confirm the Signal group message includes `size=` on success
([README.forgejo-notification.md](README.forgejo-notification.md)).
