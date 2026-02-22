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
│   ├── pxe/                        # PXE server automation
│   │   ├── pxe.yml                 # Main Ansible playbook
│   │   ├── install.sh              # Wrapper: install deps + run playbook
│   │   ├── provision.sh            # Creates LXC container on Proxmox
│   │   ├── requirements/
│   │   │   └── collections.yml     # Requires ansible.posix
│   │   └── roles/pxe/
│   │       ├── defaults/main.yml   # Default variables
│   │       ├── vars/main.yml       # Version overrides (Talos: v1.9.4)
│   │       ├── tasks/              # install, mount, configure, extract, talos
│   │       ├── templates/          # boot.ipxe, nginx config, pxelinux config
│   │       ├── files/              # Pre-built undionly.kpxe binary
│   │       ├── scripts/            # LXC creation, ISO extraction helpers
│   │       └── handlers/main.yml   # Restart tftpd-hpa, nginx
│   └── proxmox/
│       └── TODO.md                 # Proxmox host hardening checklist
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

## Usage

### 1. Provision the PXE LXC Container

Creates a Debian 12 LXC container (ID 1001) on Proxmox. Credentials are pulled from 1Password.

```bash
./ansible/pxe/provision.sh <proxmox-host-ip>
```

### 2. Configure the PXE Server

Installs and configures all services (TFTP, nginx, NFS mount) and downloads Talos boot files.

```bash
./ansible/pxe/install.sh <pxe-server-ip>
```

Or run the playbook directly:

```bash
cd ansible/pxe
ansible-galaxy collection install -r requirements/collections.yml
ansible-playbook -i 192.168.10.4, pxe.yml
```

### 3. Build the Custom iPXE Bootloader

Only needed when `build/ipxe/chain.ipxe` changes. On Apple Silicon, run inside a Linux container.

```bash
cd build/ipxe
./build.sh
cp bin/undionly.kpxe ../../ansible/pxe/roles/pxe/files/undionly.kpxe
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
| `talos_linux_version` | `v1.9.4` | `roles/pxe/vars/main.yml` |
| `talos_linux_architectures` | `[amd64, arm64]` | `roles/pxe/defaults/main.yml` |
| `pxe_server_addr` | `192.168.10.4` | `roles/pxe/defaults/main.yml` |
| `nfs_server_addr` | `192.168.10.5` | `roles/pxe/defaults/main.yml` |
| `nfs_server_share_path` | `/var/nfs/shared/pxe` | `roles/pxe/defaults/main.yml` |
| `ubuntu_versions` | `[22.04.4]` | `roles/pxe/defaults/main.yml` |

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
