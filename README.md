# homelab-automation

Infrastructure automation for a personal homelab built on **Proxmox** and **Talos Linux**, providing a complete path from bare-metal network boot through Kubernetes cluster deployment.

## Overview

This repo automates two primary concerns:

1. **PXE Boot Server** — Provisions and configures an LXC container on Proxmox that serves as a network boot server, allowing bare-metal machines to boot Talos Linux (or Ubuntu) over the network without USB drives or manual OS installation.

2. **Auxiliary Services** — Builds supporting artifacts like a custom iPXE bootloader and an SFTP container for integrating network devices (e.g., scanners) with the Kubernetes cluster.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Proxmox Host                      │
│                   (192.168.10.13)                    │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │          PXE Server LXC (ID: 1001)             │  │
│  │              192.168.10.4                      │  │
│  │                                                │  │
│  │   TFTP (tftpd-hpa) → serves undionly.kpxe     │  │
│  │   HTTP  (nginx)    → serves boot.ipxe + ISOs  │  │
│  │   NFS   (client)   → mounts images from NAS   │  │
│  └────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘

           NFS Share: 192.168.10.5:/var/nfs/shared/pxe
                (ISO images, Talos boot files)

Network Boot Flow:
  Client → DHCP → gets undionly.kpxe via TFTP
         → chain.ipxe: DHCP + HTTP chain
         → boot.ipxe: loads Talos vmlinuz + initramfs
         → Talos Linux boots → joins Kubernetes cluster
```

## Repository Structure

```
homelab-automation/
├── ansible/
│   ├── ansible.cfg              # host_key_checking off, roles_path, default inventory
│   ├── requirements.yml         # ansible.posix, community.general
│   ├── inventory/
│   │   ├── hosts.yml            # groups: proxmox, dns_lb, pxe, warp
│   │   ├── group_vars/
│   │   │   ├── all.yml
│   │   │   ├── proxmox.yml      # ansible_user: root; proxmox secrets lookups
│   │   │   ├── dns_lb.yml       # ansible_user: pi; technitium/caddy secrets lookups
│   │   │   ├── pxe.yml          # ansible_user: root; talos_linux_version
│   │   │   └── warp.yml         # ansible_user: pi; warp token lookup
│   │   └── host_vars/           # ns1.yml, ns2.yml, proxmox-1..3.yml
│   ├── playbooks/
│   │   ├── site.yml             # imports the four config playbooks (weekly Semaphore)
│   │   ├── dns-lb.yml
│   │   ├── pxe.yml
│   │   ├── warp-connector.yml
│   │   ├── proxmox.yml
│   │   └── ops/                 # manual-only, never scheduled
│   │       ├── provision-worker.yml
│   │       ├── capacity-report.yml
│   │       └── download-talos.yml
│   ├── roles/
│   │   ├── technitium/          # Technitium DNS server
│   │   ├── caddy_lb/            # Caddy reverse proxy / load balancer
│   │   ├── pxe/                 # PXE server (TFTP + nginx + NFS)
│   │   ├── warp_connector/      # Cloudflare WARP connector
│   │   └── proxmox/             # Proxmox ACME + OIDC configuration
│   └── scripts/
│       ├── provision-pxe-lxc.sh # LXC provisioning via pct (uses desktop op CLI)
│       ├── create-lxc.sh        # Raw pct commands for LXC creation
│       ├── run-dns-lb.sh        # Secret-fetching wrapper (until Phase 3)
│       ├── run-warp-connector.sh
│       └── run-proxmox.sh
└── build/
    ├── ipxe/                       # Custom iPXE bootloader
    │   ├── build.sh                # Build script
    │   ├── chain.ipxe              # Embedded chain-loading script
    │   ├── bin/undionly.kpxe       # Build output
    │   └── README.md
    └── sftp/                       # SFTP container for network scanner
        ├── Containerfile           # Alpine + OpenSSH
        ├── files/                  # authorized_keys, sshd_config
        └── README.md
```

## Prerequisites

- **Ansible** with the `ansible.posix` collection
- **1Password CLI** (`op`) for credential retrieval during provisioning
- **Proxmox** host accessible over SSH
- **NFS share** configured on NAS at `192.168.10.5:/var/nfs/shared/pxe`
- **Podman or Docker** (only needed to build the SFTP container or iPXE on macOS)

## Running playbooks

All commands run from `ansible/` (`cd ansible`). One-time: `ansible-galaxy collection install -r requirements.yml`.

| Old command | New command |
|---|---|
| `ansible/dns-lb/install.sh` | `./scripts/run-dns-lb.sh` (until secrets migration: direct `ansible-playbook playbooks/dns-lb.yml`) |
| `ansible/pxe/install.sh <ip>` | `ansible-playbook playbooks/pxe.yml` |
| `ansible/pxe/Makefile download-talos` | `ansible-playbook playbooks/ops/download-talos.yml` |
| `ansible/pxe/provision.sh <proxmox-ip>` | `ansible/scripts/provision-pxe-lxc.sh <proxmox-ip>` |
| `ansible/warp-connector/install.sh <ip>` | `./scripts/run-warp-connector.sh` |
| `ansible/proxmox/configure.sh` | `./scripts/run-proxmox.sh` |
| `ansible/proxmox/assess.sh` | `ansible-playbook playbooks/ops/capacity-report.yml` |
| `ansible/proxmox/provision-worker.sh` | `ansible-playbook playbooks/ops/provision-worker.yml` |
| (new) converge everything | `ansible-playbook playbooks/site.yml` |

> **Note:** `site.yml` full runs require the secrets the wrapper scripts supply. It becomes directly runnable in Phase 3 when secrets migrate to inventory lookups.

## Usage

### 1. Provision the PXE LXC Container

Creates a Debian 12 LXC container (ID 1001) on Proxmox. Credentials are pulled from 1Password.

```bash
ansible/scripts/provision-pxe-lxc.sh <proxmox-host-ip>
```

### 2. Configure the PXE Server

Installs and configures all services (TFTP, nginx, NFS mount) and downloads Talos boot files.

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook playbooks/pxe.yml
```

### 3. Build the Custom iPXE Bootloader

Only needed when `build/ipxe/chain.ipxe` changes. On Apple Silicon, run inside a Linux container.

```bash
cd build/ipxe
./build.sh
cp bin/undionly.kpxe ../../ansible/roles/pxe/files/undionly.kpxe
```

### 4. Build the SFTP Container

```bash
cd build/sftp
podman build -t sftp .
```

Deploy to Kubernetes with an NFS PersistentVolume for scanner document uploads.

## Key Configuration

| Variable | Default | Location |
|----------|---------|----------|
| `talos_linux_version` | `v1.12.4` | `ansible/inventory/group_vars/pxe.yml` |
| `talos_linux_architectures` | `[amd64, arm64]` | `ansible/roles/pxe/defaults/main.yml` |
| `pxe_server_addr` | `192.168.10.4` | `ansible/roles/pxe/defaults/main.yml` |
| `nfs_server_addr` | `192.168.10.5` | `ansible/roles/pxe/defaults/main.yml` |
| `nfs_server_share_path` | `/var/nfs/shared/pxe` | `ansible/roles/pxe/defaults/main.yml` |
| `ubuntu_versions` | `[22.04.4]` | `ansible/roles/pxe/defaults/main.yml` |

## How Network Boot Works

1. A bare-metal machine PXE boots and contacts the DHCP server
2. DHCP points the machine to the PXE server for `undionly.kpxe` via TFTP
3. The custom `undionly.kpxe` has `chain.ipxe` embedded — it performs a new DHCP and chains to `http://192.168.10.4/boot.ipxe`
4. `boot.ipxe` instructs the client to load the Talos Linux kernel (`vmlinuz`) and initramfs via TFTP
5. Talos boots and configures itself as a Kubernetes node

This chain-loading approach avoids requiring ISC DHCP Server for next-server configuration — just a standard DHCP server is needed.

## Technology Stack

| Technology | Role |
|------------|------|
| Ansible | Provisioning and configuration management |
| Proxmox | Hypervisor (LXC containers) |
| Talos Linux | Immutable Kubernetes OS (v1.9.4) |
| iPXE | Network bootloader (custom undionly.kpxe) |
| tftpd-hpa | TFTP server for initial boot files |
| nginx | HTTP server for ISOs and boot configs |
| NFS | Shared storage (ISOs, Talos images) |
| 1Password CLI | Secrets management |
| Alpine Linux | Base for SFTP container |
| Podman | Container builds |
