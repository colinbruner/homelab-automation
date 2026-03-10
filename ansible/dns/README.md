# ansible/dns

Ansible automation for a **Technitium DNS Server** running on a Raspberry Pi. Handles installation, user setup, and nightly backups to NFS.

Intended to run on the `dns-lb` image produced by `build/rpi/`.

## Directory Structure

```
ansible/dns/
├── dns.yml                          # Main playbook
├── install.sh                       # Runner — pulls secrets from 1Password
├── ansible.cfg
└── roles/dns/
    ├── defaults/main.yml            # Default variables
    ├── handlers/main.yml
    └── tasks/
        ├── main.yml                 # Task order: user → install → backup
        ├── user.yml                 # Create pi user, sudo, SSH key
        ├── install.yml              # Install Technitium DNS
        └── backup.yml               # NFS mount, backup script, systemd timer
```

## Run

```bash
# Against a specific host
./install.sh 192.168.10.x

# Against a specific host, dry-run
./install.sh 192.168.10.x --check
```

`install.sh` connects as `root` and reads `pi_ssh_pubkey` from 1Password.

### Secrets (via 1Password)

| `op://` path | Variable | Purpose |
|---|---|---|
| `op://private/Personal Key/public key` | `pi_ssh_pubkey` | SSH public key authorized for the `pi` user |

## What Ansible Manages

### User (`user.yml`)

Creates a `pi` user with passwordless sudo and the SSH public key from 1Password. The `dns-lb` image already has the `pi` user from pi-gen (via `--ssh-key` at build time) — this task is idempotent and ensures the correct key and sudo config are in place.

### Technitium DNS (`install.yml`)

Installs or upgrades Technitium via the official install script. The `dns-lb` image pre-installs Technitium at build time; Ansible re-runs the script on each playbook run to apply upgrades.

- Install script: `https://download.technitium.com/dns/install.sh`
- Data directory: `/etc/dns`
- Install directory: `/usr/share/technitium-dns-server`
- Service: `dns` (enabled, started)

Technitium is configured through its web UI (port 5380 by default) or API. DNS zones, forwarders, and clustering are managed there, not via Ansible.

### Backup (`backup.yml`)

Mounts an NFS share and configures a nightly backup of `/etc/dns/` to the NAS.

| Variable | Default | Description |
|---|---|---|
| `nfs_server` | `192.168.10.5` | NFS server address |
| `nfs_export` | `/var/nfs/shared/homelab` | NFS export path |
| `nfs_mount_point` | `/mnt/backup/homelab` | Local mount point |
| `backup_retain_days` | `7` | Days to retain backup archives |
| `backup_schedule` | `02:00:00` | Nightly backup time (systemd OnCalendar) |

Backups are written to `<nfs_mount_point>/dns/`:
- `latest/` — rsync mirror of `/etc/dns/` (always current)
- `dns-backup-YYYYMMDD-HHMMSS.tar.gz` — dated archives, retained for 7 days

## Clustering

Two DNS servers are planned for redundancy. Technitium supports multi-primary clustering natively — configure replication through the Technitium web UI after both servers are provisioned.
