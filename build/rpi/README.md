# Raspberry Pi Image

Builds a headless Raspberry Pi OS Lite image based on **Debian 13 (Trixie)** using [pi-gen](https://github.com/RPi-Distro/pi-gen), the official Raspberry Pi Foundation image builder.

Produces a `.img.xz` that can be flashed directly to a microSD card with `dd` or Raspberry Pi Imager.

## What's Included

- Debian 13 Trixie base (Lite — no desktop, arm64)
- SSH pre-enabled
- Custom `stage-custom` overlay per image (packages, services, config)
- First-boot wizard disabled (headless-safe)

## Images

Each image lives in its own directory under `images/`:

```
images/
├── warp-connector/       # Cloudflare WARP Connector node
│   ├── config
│   └── stage-custom/
│       ├── SKIP_IMAGES
│       └── 00-config/
│           ├── 00-packages              # apt packages
│           └── 01-run-chroot.sh.tpl    # static IP template
│
└── dns-lb/               # DNS + load balancer server (Technitium + Caddy)
    ├── config
    └── stage-custom/
        ├── SKIP_IMAGES
        └── 00-config/
            ├── 00-packages              # apt packages (libicu-dev, nfs-common, etc.)
            ├── 01-run-chroot.sh         # installs Docker, Caddy, Technitium
            └── 02-run-chroot.sh.tpl    # static IP template
```

The `dns-lb` image is intended to be built twice — once per server — with different `--hostname` and `--ip` values. Ansible (`ansible/dns/` and `ansible/lb/`) manages all post-boot configuration.

To add a new image, create a new directory under `images/` with at minimum a `config` file.

## Prerequisites

- [Docker Desktop](https://docs.docker.com/desktop/) installed and running
- `git`

The build runs entirely inside Docker, so no additional dependencies are needed on macOS.

## Configuration

Each image has its own `images/<name>/config`. Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `IMG_NAME` | *(image name)* | Output filename prefix |
| `RELEASE` | `trixie` | Debian release. Change to `bookworm` if trixie is unsupported |
| `TARGET_HOSTNAME` | *(image name)* | Hostname baked into the image — override with `--hostname` at build time |
| `TIMEZONE_DEFAULT` | `America/Chicago` | Timezone |
| `FIRST_USER_NAME` | `pi` | Default non-root user |

**Do not set `FIRST_USER_PASS` or `PUBKEY_SSH_FIRST_USER` in the config file.** Pass them via CLI flags to `build.sh` instead — this keeps credentials out of the repository.

## Build

```bash
cd build/rpi

# SSH key only (DHCP)
./build.sh warp-connector --ssh-key 'ssh-ed25519 AAAA...'
# Output: build/rpi/bin/warp-connector/*.img.xz

# Password only (also disables first-boot rename wizard)
./build.sh warp-connector --password 'yourpassword'

# Both (recommended for headless use)
./build.sh warp-connector --password 'yourpassword' --ssh-key 'ssh-ed25519 AAAA...'

# Static IP + credentials
./build.sh warp-connector \
  --password 'yourpassword' \
  --ssh-key 'ssh-ed25519 AAAA...' \
  --ip 192.168.10.2/24 \
  --gateway 192.168.10.1

# Static IP with custom DNS (semicolon-separated, NetworkManager format)
./build.sh warp-connector \
  --password 'yourpassword' \
  --ip 192.168.10.2/24 \
  --gateway 192.168.10.1 \
  --dns "192.168.10.1;1.1.1.1;"

# Non-default interface (default is eth0)
./build.sh warp-connector --password 'yourpassword' --ip 192.168.10.2/24 --gateway 192.168.10.1 --interface eth1

# List available images
./build.sh
```

### dns-lb (build two servers from one image definition)

```bash
cd build/rpi

# Server 1
./build.sh dns-lb \
  --hostname rpi1 \
  --ssh-key 'ssh-ed25519 AAAA...' \
  --ip 192.168.10.x/24 \
  --gateway 192.168.10.1 \
  --dns "192.168.10.1;"

# Server 2
./build.sh dns-lb \
  --hostname rpi2 \
  --ssh-key 'ssh-ed25519 AAAA...' \
  --ip 192.168.10.y/24 \
  --gateway 192.168.10.1 \
  --dns "192.168.10.1;"
```

After flashing, run Ansible to apply configuration:
```bash
cd ansible/dns && ./install.sh 192.168.10.x
cd ansible/lb  && ./install.sh 192.168.10.x
```

The build takes approximately 20–40 minutes on first run. Subsequent runs clone pi-gen fresh each time.

### Static IP Templating

If the image's `stage-custom/` directory contains any `*.sh.tpl` files, `build.sh` renders them at build time by substituting `@@VAR@@` placeholders with the values provided via CLI flags. The `.tpl` extension is stripped to produce the final chroot script (e.g. `02-run-chroot.sh.tpl` → `02-run-chroot.sh`).

| Placeholder | Flag | Default |
|-------------|------|---------|
| `@@NM_INTERFACE@@` | `--interface` | `eth0` |
| `@@NM_ADDRESS@@` | `--ip` | *(required when using static IP)* |
| `@@NM_GATEWAY@@` | `--gateway` | *(required when using `--ip`)* |
| `@@NM_DNS@@` | `--dns` | Falls back to `--gateway` value |

If `--ip` is not provided, the template is skipped entirely and the image uses DHCP.

## Flash

**With Raspberry Pi Imager (recommended):**
Open Raspberry Pi Imager, choose "Use custom image", and select the `.img.xz` file from `bin/<image-name>/`.

**With `dd`:**
```bash
xz -d bin/warp-connector/*.img.xz
sudo dd if=bin/warp-connector/*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with your microSD card device (use `diskutil list` on macOS to find it).

## Adding a New Image

1. Create `images/<name>/` directory
2. Copy an existing `config` as a starting point and adjust `IMG_NAME`, `TARGET_HOSTNAME`, etc.
3. Add `stage-custom/SKIP_IMAGES` and a `stage-custom/00-config/` subdirectory
4. Add `00-packages` for apt packages and/or numbered `NN-run-chroot.sh` scripts for arbitrary install steps
5. Optionally add a `NN-run-chroot.sh.tpl` for static IP (rendered from `--ip`/`--gateway` flags)
6. Run `./build.sh <name>`

**Chroot scripts** run inside the image during build. Services won't start (pi-gen blocks them), but packages install and systemd units are enabled for first boot:
```bash
#!/bin/bash -e
# 01-run-chroot.sh — runs inside the image chroot
curl -fsSL https://example.com/install.sh | bash
```

**Static IP template** — use a `*.sh.tpl` file with `@@VAR@@` placeholders:
```bash
#!/bin/bash -e
# 02-run-chroot.sh.tpl
INTERFACE="@@NM_INTERFACE@@"
ADDRESS="@@NM_ADDRESS@@"
# ...
```
Then pass `--ip` and `--gateway` at build time:
```bash
./build.sh <name> --ip 192.168.1.5/24 --gateway 192.168.1.1
```

**Hostname override** — use `--hostname` to produce differently-named images from the same definition:
```bash
./build.sh <name> --hostname server1 --ip 192.168.1.5/24 --gateway 192.168.1.1
./build.sh <name> --hostname server2 --ip 192.168.1.6/24 --gateway 192.168.1.1
```
