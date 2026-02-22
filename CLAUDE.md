# CLAUDE.md

This file provides context and guidance for Claude when working in this repository.

## Repository Purpose

This repo automates a homelab built on **Proxmox** and **Talos Linux**. The primary goal is bootstrapping a Kubernetes cluster via network (PXE) boot, along with auxiliary services.

## Directory Structure

```
homelab-automation/
├── ansible/
│   ├── pxe/           # PXE boot server automation (main focus)
│   │   ├── pxe.yml    # Main playbook
│   │   ├── install.sh # Runs playbook against PXE server
│   │   ├── provision.sh # Creates LXC container on Proxmox
│   │   └── roles/pxe/ # Ansible role with tasks, templates, scripts
│   └── proxmox/       # Proxmox host setup (TODO stage)
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
./ansible/pxe/provision.sh <proxmox-host-ip>
# Uses 1password CLI to retrieve credentials
```

### Run the PXE playbook against an existing host
```bash
./ansible/pxe/install.sh <pxe-server-ip>
# Installs Ansible collections then runs pxe.yml
```

### Run the playbook directly
```bash
cd ansible/pxe
ansible-galaxy collection install -r requirements/collections.yml
ansible-playbook -i <pxe-server-ip>, pxe.yml
```

### Build the custom iPXE bootloader
```bash
cd build/ipxe
./build.sh
# On macOS (Apple Silicon): run inside a Linux container
# Output: build/ipxe/bin/undionly.kpxe
# Deploy: cp bin/undionly.kpxe ../../ansible/pxe/roles/pxe/files/undionly.kpxe
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
| `ansible/pxe/roles/pxe/defaults/main.yml` | Default variables (packages, IPs, paths) |
| `ansible/pxe/roles/pxe/vars/main.yml` | Override vars (Talos version = v1.9.4) |
| `ansible/pxe/roles/pxe/templates/ipxe/boot.ipxe` | iPXE boot config (loads Talos kernel) |
| `ansible/pxe/roles/pxe/files/undionly.kpxe` | Pre-built iPXE bootloader binary |
| `ansible/pxe/scripts/create-lxc.sh` | Proxmox `pct` commands for LXC creation |
| `ansible/pxe/scripts/extract-boot-disk.sh` | Mounts ISOs and extracts vmlinuz/initrd |
| `build/ipxe/chain.ipxe` | Embedded iPXE script: DHCP + chain to HTTP |

## Conventions & Patterns

- **Idempotency**: Tasks check for file existence before downloading/extracting (use `creates:` or `stat`)
- **Handlers**: `tftpd-hpa` and `nginx` are restarted via handlers on config change
- **Secrets**: Never hardcoded — always retrieved via `op` CLI at runtime
- **TFTP file permissions**: Boot files must be world-readable (mode `0644`)
- **NFS mount**: PXE server mounts `/var/nfs/shared/pxe` from NAS at `/srv/`

## Notes for Making Changes

- When updating Talos version: edit `ansible/pxe/roles/pxe/vars/main.yml` (`talos_linux_version`)
- When adding new architectures: extend `talos_linux_architectures` list in defaults
- The `undionly.kpxe` binary must be rebuilt if `build/ipxe/chain.ipxe` changes, then copied to `ansible/pxe/roles/pxe/files/`
- The SFTP container uses RSA host keys specifically because older network scanners don't support ed25519
- `ansible/proxmox/` is a work-in-progress; see `TODO.md` for pending items
