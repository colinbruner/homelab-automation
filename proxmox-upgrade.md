# Proxmox VE Cluster Upgrade: 8.3.0 → 9.1

This document details the full procedure for upgrading the homelab Proxmox cluster from version 8.3.0 to 9.1. It covers prerequisites, the automated Ansible approach, the equivalent manual steps for each phase, known breaking changes, and post-upgrade verification.

---

## Cluster Overview

| Node | IP | Role |
|------|----|------|
| proxmox-1 | 192.168.10.11 | Cluster node |
| proxmox-2 | 192.168.10.12 | Cluster node |
| proxmox-3 | 192.168.10.13 | Cluster node |

All nodes form a 3-node Proxmox VE cluster. The cluster runs Talos Linux worker VMs and LXC containers (PXE server, WARP Connector).

---

## Version and OS Baseline

| | Proxmox VE 8.x | Proxmox VE 9.x |
|--|--|--|
| **Debian base** | Debian 12 (Bookworm) | Debian 13 (Trixie) |
| **Kernel** | Linux 6.8 | Linux 6.14+ |
| **APT suite** | `bookworm` | `trixie` |
| **Repo format** | Legacy `.list` | deb822 `.sources` |

---

## Upgrade Path

Because this is a major version upgrade that also crosses a Debian base OS boundary, the upgrade **must be done in two stages**:

```
PVE 8.3.0 (Bookworm) → PVE 8.4.x (Bookworm) → PVE 9.x (Trixie)
```

Proxmox requires nodes to be on the latest PVE 8.4 release before the `pve8to9` upgrade tool will pass cleanly. Skipping directly from 8.3 to 9 is not supported.

Nodes are upgraded **one at a time** to maintain cluster quorum. In a 3-node cluster, at least 2 nodes must remain online and healthy throughout the process.

---

## Prerequisites

Before starting the upgrade, verify the following on every node:

### 1. Console / IPMI Access
SSH sessions may be interrupted during reboots. Ensure you have out-of-band console access (IPMI, iDRAC, iLO, or Proxmox web console) to each node before starting.

### 2. Backups
Back up all VMs and LXC containers using Proxmox Backup Server or `vzdump` before upgrading any node. Verify that backups are restorable.

```bash
# Example: back up all VMs on a node
vzdump --all --compress zstd --storage <backup-storage>
```

### 3. Disk Space
Each node needs at least **5 GB free** on `/`. The upgrade downloads several hundred megabytes of packages and a new kernel.

```bash
df -h /
```

### 4. Cluster Health
All nodes must be online, healthy, and at quorum before starting.

```bash
pvecm status
# Expected: Quorate: Yes, Nodes: 3
```

### 5. VM Migration
Before upgrading a node, migrate or shut down running VMs and containers on that node. This avoids any disruption if the upgrade or reboot takes longer than expected.

```bash
# List running VMs on a node
qm list
pct list

# Migrate a VM to another node
qm migrate <vmid> <target-node>
```

### 6. No Subscription License
These nodes use the no-subscription (community) repository. The enterprise repository will be disabled as part of the upgrade process.

---

## Automated Upgrade (Ansible)

The upgrade is automated via `ansible/proxmox/upgrade-8to9.yml`. It runs all three phases sequentially with `serial: 1` to upgrade one node at a time.

### Running the Full Upgrade

```bash
cd ansible/proxmox
./upgrade.sh
```

### Running Individual Phases via Tags

```bash
# Phase 1: Pre-flight checks only (no changes made)
./upgrade.sh --tags preflight

# Phase 2: Upgrade to PVE 8.4 only
./upgrade.sh --tags pve84

# Phase 3: Upgrade to PVE 9 only (run after pve84 completes)
./upgrade.sh --tags pve9
```

### Targeting a Single Node

```bash
# Run the full upgrade against only proxmox-1
./upgrade.sh --limit proxmox-1
```

### Dry Run (Check Mode)

```bash
# Check what would change without making any changes
# NOTE: reboot and shell tasks are skipped in check mode
./upgrade.sh --check
```

---

## Manual Upgrade Procedure

The following documents what the Ansible playbook automates. Use this as a reference for manual intervention or recovery.

### Phase 1: Pre-flight Checks (all nodes)

Run on each node before touching anything:

```bash
# Check current version
pveversion -v

# Check available disk space
df -h /

# Check cluster quorum
pvecm status

# Install and run the official upgrade checker
apt-get install -y pve-manager
pve8to9
```

Review the output of `pve8to9` carefully. It will flag any issues that need to be resolved before upgrading. Common warnings include:
- Containers using cgroup v1 (unsupported in PVE 9)
- Custom kernel parameters that may conflict
- Deprecated configuration options

### Phase 2: Upgrade to PVE 8.4 (one node at a time)

Perform these steps on **one node at a time**. Complete the full sequence (including reboot) before moving to the next node.

```bash
# 1. Disable enterprise repositories
mv /etc/apt/sources.list.d/pve-enterprise.list \
   /etc/apt/sources.list.d/pve-enterprise.list.disabled

mv /etc/apt/sources.list.d/ceph.list \
   /etc/apt/sources.list.d/ceph.list.disabled 2>/dev/null || true

# 2. Add no-subscription repository (Bookworm / PVE 8)
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list

# 3. Update and upgrade
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  -y

# 4. Reboot
reboot

# 5. After reboot: verify version
pveversion
# Expected output contains: pve-manager/8.4.x
```

After rebooting, verify the node rejoins the cluster before proceeding to the next node:

```bash
pvecm status
# All 3 nodes should appear as online
```

### Phase 3: Upgrade to PVE 9 / Debian Trixie (one node at a time)

Perform these steps on **one node at a time**, only after all nodes are running PVE 8.4.

```bash
# 1. Run the full pre-upgrade checker — must pass cleanly
pve8to9 --full

# 2. Update base OS sources from Bookworm to Trixie
sed -i 's/bookworm/trixie/g' /etc/apt/sources.list

# 3. Remove legacy PVE 8 no-subscription list
rm /etc/apt/sources.list.d/pve-no-subscription.list

# 4. Add PVE 9 repository in modern deb822 format
cat > /etc/apt/sources.list.d/proxmox.sources << 'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# 5. Update package lists
apt-get update

# 6. Full distribution upgrade (Bookworm → Trixie)
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  -y

# 7. Reboot into new kernel
reboot

# 8. After reboot: verify version
pveversion -v
# Expected output contains: pve-manager/9.x
```

**During the dist-upgrade**, dpkg may prompt about config file changes. The flags `--force-confdef` and `--force-confold` suppress interactive prompts and keep existing config files where possible. Review any changed config files post-upgrade.

After rebooting, verify the node rejoins the cluster and check quorum before proceeding to the next node:

```bash
pvecm status
```

---

## Configuration File Prompts

During the Trixie dist-upgrade, dpkg may ask about the following config files. The recommended action for each:

| File | Recommendation |
|------|---------------|
| `/etc/issue` | Keep current (cosmetic only) |
| `/etc/lvm/lvm.conf` | Accept maintainer version (unless you have custom LVM config) |
| `/etc/ssh/sshd_config` | Accept maintainer version (unless you have custom SSH config) |
| `/etc/default/grub` | **Review carefully** — keep any custom kernel parameters you've added |
| `/etc/chrony/chrony.conf` | Accept maintainer version unless you have custom NTP config |

The `--force-confdef,force-confold` dpkg flags will handle these automatically in the non-interactive Ansible run, keeping existing files. Review `/etc/apt/listchanges.log` and `dpkg.log` post-upgrade.

---

## Known Breaking Changes: PVE 8 → PVE 9

### `/tmp` is now tmpfs
Debian Trixie mounts `/tmp` as a tmpfs (up to 50% of RAM). Files written to `/tmp` are lost on reboot, and the mount is size-limited. If any scripts or VMs depend on persistent `/tmp` storage, move them to `/var/tmp` or another persistent path.

### cgroup v1 Removed
PVE 9 drops support for cgroup v1. LXC containers running very old systemd versions (< 230, released 2016) will no longer start. Check container OS versions before upgrading:

```bash
# On each node, list containers and their OS
pct list
# For any running containers, check systemd version inside
pct exec <ctid> -- systemd --version
```

### HA Groups Deprecated
High Availability Groups are deprecated in PVE 9 and replaced by HA Rules. Existing HA Groups are automatically migrated to HA Rules once **all** cluster nodes have been upgraded to PVE 9. Do not expect full HA functionality during the rolling upgrade window.

### Network Interface Names
In rare cases, network interface names may change after the kernel upgrade. Having console/IPMI access ensures you can recover if networking fails to come up after reboot.

### UEFI + LVM Boot
On nodes using UEFI boot with an LVM root filesystem, reinstall GRUB after the upgrade if the node fails to boot:

```bash
apt install grub-efi-amd64
```

### VM Memory Display
PVE 9 reports higher memory usage per VM due to improved overhead accounting. This is cosmetic — actual guest memory usage has not changed.

---

## Post-Upgrade Verification

After all three nodes are upgraded, verify the following:

### 1. Cluster Health

```bash
# On any node
pvecm status
# Expected: Quorate: Yes, all 3 nodes online

pvecm nodes
# All nodes should show as online
```

### 2. Node Versions

```bash
# On each node
pveversion -v
# Expected: pve-manager/9.x.x
```

### 3. Web UI

Open the Proxmox web UI at `https://192.168.10.11:8006`. Force-refresh the browser cache (`Ctrl+Shift+R` / `Cmd+Shift+R`) to clear any cached PVE 8 assets.

### 4. VM and Container Operations

```bash
# Verify VMs start correctly
qm start <vmid>
qm status <vmid>

# Verify LXC containers start correctly
pct start <ctid>
pct status <ctid>
```

### 5. Re-run pve8to9

The `pve8to9` tool can still be run post-upgrade to confirm no known issues remain:

```bash
pve8to9
```

### 6. Modernize Repository Format (Optional)

PVE 9 supports a convenience command to migrate any remaining legacy `.list` files to deb822 `.sources` format:

```bash
apt modernize-sources
```

---

## Rollback Notes

There is no automated rollback for a major OS version upgrade. The recommended recovery paths are:

1. **VM / container data**: Restore from backups taken before the upgrade
2. **Node failure to boot**: Access via console/IPMI; boot from live media; restore from backup
3. **Partial upgrade stuck**: Boot the node, resolve dpkg issues manually with `dpkg --configure -a` then `apt-get -f install`
4. **Network interface lost**: Connect via console; check `ip link` and update `/etc/network/interfaces` if interface names changed

The safest rollback is a full node reinstall from Proxmox VE 9 ISO followed by restoring VMs from backup — which is why pre-upgrade backups are mandatory.

---

## Ansible Files Reference

| File | Purpose |
|------|---------|
| `ansible/proxmox/upgrade-8to9.yml` | Main upgrade playbook |
| `ansible/proxmox/upgrade.sh` | Runner script |
| `ansible/proxmox/inventory/hosts.yml` | Cluster node inventory |
