# Semaphore: Scheduled Ansible Applies

Canonical runbook for deploying and configuring [Semaphore UI](https://semaphoreui.com/)
to run this repo's Ansible playbooks on a schedule. A separate session in the
`homelab-k8s` repo reads this document before writing any manifests.

## Purpose

Semaphore exists to run `ansible/playbooks/site.yml` on a weekly schedule so the
lab converges to what is in `main` without manual intervention. Configuration
drift on the Proxmox hosts, the PXE server, the DNS/LB pis, and the WARP
connector gets corrected automatically instead of accumulating until the next
hand-run.

Only the four config playbooks (via `site.yml`) are ever scheduled. The
playbooks under `ansible/playbooks/ops/` (`capacity-report.yml`,
`provision-worker.yml`, `download-talos.yml`) are **manual-only**: they get
task templates in Semaphore so they can be triggered from the UI, but they must
never be given a schedule.

## Deployment (homelab-k8s repo)

Semaphore is deployed as an ArgoCD application in the homelab Kubernetes
cluster:

- **Image**: the official `semaphoreui/semaphore` image.
- **Database**: BoltDB (Semaphore's embedded store) on a PersistentVolumeClaim.
  No external database is needed at this scale; the PVC is the only state.
- **Secrets environment**: the pod gets `OP_CONNECT_HOST` (the cluster-local
  1Password Connect service URL) and `OP_CONNECT_TOKEN` sourced from a
  Kubernetes Secret. The Connect token must be scoped **read-only to the `lab`
  vault** — Semaphore only ever reads secrets, and the blast radius of a leaked
  token should stay small. Playbook runs inherit these env vars, which is how
  the `community.general.onepassword` lookups in `group_vars/` resolve.
- **`op` CLI binary**: the `community.general.onepassword` lookup is a wrapper
  around the 1Password `op` CLI — even in Connect mode it just passes
  `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` through to the binary. Lookups run on
  the Ansible controller (the Semaphore pod), so `op` must be present **inside
  the Semaphore container**; the remote hosts never need it. The official
  image does not ship it. Rather than maintaining a custom image, use an init
  container that copies the binary from 1Password's official image into a
  shared volume, mounted with `subPath` so it lands on the PATH Semaphore
  builds for task runs:

  ```yaml
  initContainers:
    - name: install-op
      image: 1password/op:2
      command: ["cp", "/usr/local/bin/op", "/op-bin/op"]
      volumeMounts:
        - name: op-bin
          mountPath: /op-bin
  containers:
    - name: semaphore
      # ...existing config...
      volumeMounts:
        - name: op-bin
          mountPath: /usr/local/bin/op
          subPath: op
  volumes:
    - name: op-bin
      emptyDir: {}
  ```
- **Network egress**: the pod must be able to reach the lab management networks
  `192.168.1.0/24` and `192.168.10.0/24` over SSH. Verify this with a debug pod
  (e.g. `kubectl run -it --rm debug --image=busybox -- sh`, then try connecting
  to a host on each subnet) **before** installing Semaphore — if egress is
  blocked, fix routing/NetworkPolicy first.
- **Repo access**: a GitHub deploy key (read-only) on
  `colinbruner/homelab-automation` so Semaphore can clone the repo.

## In-Semaphore setup

Configure the following inside the Semaphore UI once it is running:

1. **Key Store** — add an SSH key named `semaphore`. The private key is stored
   at `op://lab/semaphore-ssh/private-key`; paste it into the Key Store. It is
   never committed to any repo. The matching public key is distributed to all
   root-login hosts by the `lab_user` role via `lab_authorized_pubkeys` in
   `ansible/inventory/group_vars/all.yml`.

2. **Repository** — `colinbruner/homelab-automation`, branch `main`, playbook
   path `ansible/` (so `ansible.cfg`, `inventory/`, and relative role paths
   resolve correctly). Authenticate with the GitHub deploy key.

3. **Environment** — an environment exposing the two 1Password Connect
   variables (`OP_CONNECT_HOST`, `OP_CONNECT_TOKEN`) to task runs, matching the
   values injected into the pod.

4. **Task templates** — one template per playbook:

   | Template | Playbook | Schedule |
   |---|---|---|
   | site | `playbooks/site.yml` | weekly (see below) |
   | dns-lb | `playbooks/dns-lb.yml` | none (manual) |
   | pxe | `playbooks/pxe.yml` | none (manual) |
   | warp-connector | `playbooks/warp-connector.yml` | none (manual) |
   | proxmox | `playbooks/proxmox.yml` | none (manual) |
   | ops: capacity-report | `playbooks/ops/capacity-report.yml` | **never** |
   | ops: provision-worker | `playbooks/ops/provision-worker.yml` | **never** |
   | ops: download-talos | `playbooks/ops/download-talos.yml` | **never** |

   The individual config playbook templates exist for targeted manual runs;
   the ops templates exist for one-off operational tasks and must not be
   scheduled under any circumstances.

## Schedules

- **Weekly apply**: `site.yml` every Sunday at 04:00 — cron `0 4 * * 0`.
- **First-month check run**: for the first month, an additional template runs
  `site.yml` with `--check --diff` every Wednesday at 04:00 — cron
  `0 4 * * 3`. This surfaces what the next Sunday apply would change without
  touching anything. Delete this template once a few weeks of clean runs have
  established confidence in the scheduled apply.

## Notifications

Configure a Semaphore alert integration (e.g. Telegram, Slack, or email) so
**failed tasks** send a notification. A silent scheduled failure is worse than
no schedule at all — drift correction that silently stops running looks
identical to a healthy lab until something breaks.

## Consequence: main is live

Once the weekly schedule is enabled, **merging to `main` means Semaphore
applies it on the next scheduled run** — within the week, with no human in the
loop. The CI lint/syntax gate is load-bearing: it is the last check before a
change reaches real hosts. Treat every merge to `main` as a deploy.
