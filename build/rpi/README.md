# Raspberry Pi Image

Builds a headless Raspberry Pi OS Lite image based on **Debian 13 (Trixie)** using [pi-gen](https://github.com/RPi-Distro/pi-gen), the official Raspberry Pi Foundation image builder.

Produces a `.img.xz` that can be flashed directly to a microSD card with `dd` or Raspberry Pi Imager.

## What's Included

- Debian 13 Trixie base (Lite — no desktop, arm64)
- SSH pre-enabled
- Custom `stage-custom` overlay with homelab packages: `curl`, `git`, `vim`, `htop`, `net-tools`, `nmap`, `python3`, `jq`
- First-boot wizard disabled (headless-safe)

## Images

Each image lives in its own directory under `images/`:

```
images/
└── warp-connector/       # Cloudflare WARP Connector node
    ├── config            # pi-gen configuration
    └── stage-custom/
        ├── 00-packages              # apt packages to install
        ├── 01-run-chroot.sh.tpl     # static IP template (rendered at build time)
        └── SKIP_IMAGES
```

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
| `TARGET_HOSTNAME` | *(image name)* | Hostname baked into the image |
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

The build takes approximately 20–40 minutes on first run. Subsequent runs clone pi-gen fresh each time.

### Static IP Templating

If the image's `stage-custom/` directory contains a `01-run-chroot.sh.tpl` file, `build.sh` renders it at build time by substituting `@@VAR@@` placeholders with the values provided via CLI flags:

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
3. Optionally add `stage-custom/00-packages`, `stage-custom/01-run-chroot.sh.tpl` (or `01-run-chroot.sh`), and `stage-custom/SKIP_IMAGES`
4. Run `./build.sh <name>`

To run arbitrary commands inside the image at build time, use `stage-custom/01-run-chroot.sh`:
```bash
#!/bin/bash -e
# Runs inside the image chroot during build
systemctl enable your-service
```

To support static IP configuration baked in at build time, use `stage-custom/01-run-chroot.sh.tpl` with `@@VAR@@` placeholders instead:
```bash
#!/bin/bash -e
INTERFACE="@@NM_INTERFACE@@"
ADDRESS="@@NM_ADDRESS@@"
GATEWAY="@@NM_GATEWAY@@"
DNS="@@NM_DNS@@"
# ... write NetworkManager keyfile, etc.
```

Then pass `--ip` and `--gateway` at build time:
```bash
./build.sh <name> --ip 192.168.1.5/24 --gateway 192.168.1.1
```
