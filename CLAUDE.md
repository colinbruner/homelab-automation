# CLAUDE.md

This file provides context and guidance for Claude when working in this repository.

## Repository Purpose

This repo automates a homelab built on **Proxmox** and **Talos Linux**. The primary goal is bootstrapping a Kubernetes cluster via network (PXE) boot, along with auxiliary services.

## Directory Structure

```
homelab-automation/
├── ansible/
│   ├── ansible.cfg              # host_key_checking off, roles_path, default inventory
│   ├── requirements.yml         # ansible.posix, community.general
│   ├── inventory/
│   │   ├── hosts.yml            # groups: proxmox, dns_lb, pxe, warp
│   │   ├── group_vars/          # all.yml, proxmox.yml, dns_lb.yml, pxe.yml, warp.yml
│   │   └── host_vars/           # ns1.yml, ns2.yml, proxmox-1..3.yml
│   ├── playbooks/
│   │   ├── site.yml             # converge-everything entry point (Semaphore-scheduled)
│   │   ├── dns-lb.yml           # Technitium DNS + Caddy LB
│   │   ├── pxe.yml              # PXE server
│   │   ├── warp-connector.yml   # Cloudflare WARP connector
│   │   ├── proxmox.yml          # Proxmox ACME + OIDC
│   │   └── ops/                 # manual-only: capacity-report, provision-worker, download-talos
│   ├── roles/
│   │   ├── technitium/          # Technitium DNS server
│   │   ├── caddy_lb/            # Caddy reverse proxy / load balancer
│   │   ├── pxe/                 # PXE server (TFTP + nginx + NFS)
│   │   ├── warp_connector/      # Cloudflare WARP connector
│   │   └── proxmox/             # Proxmox ACME + OIDC configuration
│   └── scripts/
│       ├── provision-pxe-lxc.sh # LXC provisioning (pct-based, uses desktop op CLI)
│       └── create-lxc.sh        # Raw pct commands for LXC creation
└── build/
    ├── ipxe/          # Builds custom undionly.kpxe bootloader
    └── sftp/          # Alpine SFTP container for network scanner
```

## Key Technologies

- **Ansible** — primary automation tool; uses `ansible.posix` collection
- **Proxmox** — hypervisor; LXC containers managed via `pct` CLI
- **Talos Linux** — Kubernetes-optimized OS served via PXE (v1.9.4 as of last update)
- **iPXE** — custom bootloader built from source with embedded chain script
- **TFTP (tftpd-hpa) + Nginx** — serve boot files and ISO images
- **NFS** — shared storage between NAS (192.168.10.5) and PXE server
- **1Password CLI (`op`)** — credential management for provisioning scripts
- **Podman/Docker** — for building the SFTP container image

## Network Layout

| Host | IP | Role |
|------|----|------|
| Proxmox | 192.168.10.13 | Hypervisor |
| PXE Server (LXC 1001) | 192.168.10.4 | TFTP + HTTP + NFS client |
| NFS Server | 192.168.10.5 | Shared storage (`/var/nfs/shared/pxe`) |

## Common Tasks

### Provision the PXE LXC container on Proxmox
```bash
ansible/scripts/provision-pxe-lxc.sh <proxmox-host-ip>
# Uses desktop 1Password CLI to retrieve credentials
```

### Run a playbook
```bash
cd ansible
ansible-galaxy collection install -r requirements.yml   # one-time
export OP_CONNECT_HOST="https://<connect-host>"
export OP_CONNECT_TOKEN="$(op read 'op://lab/onepassword-connect/token')"
ansible-playbook playbooks/pxe.yml
ansible-playbook playbooks/dns-lb.yml
ansible-playbook playbooks/site.yml   # converge all
```

### Run an ops (manual-only) playbook
```bash
cd ansible
ansible-playbook playbooks/ops/download-talos.yml
ansible-playbook playbooks/ops/capacity-report.yml
ansible-playbook playbooks/ops/provision-worker.yml
```

### Build the custom iPXE bootloader
```bash
cd build/ipxe
./build.sh
# On macOS (Apple Silicon): run inside a Linux container
# Output: build/ipxe/bin/undionly.kpxe
# Deploy: cp bin/undionly.kpxe ../../ansible/roles/pxe/files/undionly.kpxe
```

### Build the SFTP container
```bash
cd build/sftp
podman build -t sftp .
```

## Ansible Role Task Execution Order

The `pxe` role runs tasks in this order (`roles/pxe/tasks/main.yml`):

1. **install.yml** — installs packages (xinetd, tftpd-hpa, nginx, nfs-common, ipxe, grub-efi-amd64-signed, shim-signed)
2. **mount.yml** — mounts NFS share, creates TFTP/HTTP directories
3. **configure.yml** — copies iPXE files, templates boot.ipxe and nginx config, configures tftpd-hpa
4. **extract.yml** — extracts Ubuntu ISO boot files (runs helper script idempotently)
5. **talos.yml** — downloads Talos vmlinuz + initramfs.xz for amd64 and arm64

## Important Files

| File | Purpose |
|------|---------|
| `ansible/ansible.cfg` | Project-wide Ansible configuration |
| `ansible/inventory/hosts.yml` | Host inventory (proxmox, dns_lb, pxe, warp groups) |
| `ansible/inventory/group_vars/pxe.yml` | PXE group vars including `talos_linux_version` |
| `ansible/roles/pxe/defaults/main.yml` | PXE role default variables (packages, IPs, paths) |
| `ansible/roles/pxe/templates/ipxe/boot.ipxe` | iPXE boot config (loads Talos kernel) |
| `ansible/roles/pxe/files/undionly.kpxe` | Pre-built iPXE bootloader binary |
| `ansible/scripts/create-lxc.sh` | Proxmox `pct` commands for LXC creation |
| `ansible/roles/pxe/scripts/extract-boot-disk.sh` | Mounts ISOs and extracts vmlinuz/initrd |
| `ansible/playbooks/site.yml` | Converge-everything entry point (imports all four config playbooks) |
| `ansible/scripts/provision-pxe-lxc.sh` | LXC provisioning script (pct-based) |
| `build/ipxe/chain.ipxe` | Embedded iPXE script: DHCP + chain to HTTP |

## Conventions & Patterns

- **Idempotency**: Tasks check for file existence before downloading/extracting (use `creates:` or `stat`)
- **Handlers**: `tftpd-hpa` and `nginx` are restarted via handlers on config change
- **Secrets**: Never hardcoded — resolved at runtime via 1Password Connect lookups in `group_vars`; export `OP_CONNECT_HOST` and `OP_CONNECT_TOKEN` before running playbooks that touch secrets
- **TFTP file permissions**: Boot files must be world-readable (mode `0644`)
- **NFS mount**: PXE server mounts `/var/nfs/shared/pxe` from NAS at `/srv/`

## Notes for Making Changes

- When updating Talos version: edit `ansible/inventory/group_vars/pxe.yml` (`talos_linux_version`)
- When adding new architectures: extend `talos_linux_architectures` list in `ansible/roles/pxe/defaults/main.yml`
- The `undionly.kpxe` binary must be rebuilt if `build/ipxe/chain.ipxe` changes, then copied to `ansible/roles/pxe/files/`
- The SFTP container uses RSA host keys specifically because older network scanners don't support ed25519
- `playbooks/ops/` playbooks are manual-only and intentionally excluded from `site.yml`
- Secrets (Cloudflare tokens, OIDC credentials, etc.) are resolved via `community.general.onepassword` lookups in `group_vars`; no wrapper scripts needed
