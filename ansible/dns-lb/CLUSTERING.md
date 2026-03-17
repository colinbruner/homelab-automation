# Technitium DNS Clustering Setup

Clustering requires **Technitium DNS Server v14+** on both nodes and is a one-time manual process performed through the web UI after Ansible provisioning is complete.

## What Ansible Handles Automatically

- Installs certbot with the Cloudflare DNS-01 plugin
- Obtains a Let's Encrypt certificate for each node's public FQDN (`ns1.colinbruner.com` / `ns2.colinbruner.com`)
- Converts the cert to PFX and configures Technitium to serve HTTPS on port `53443`
- Installs a post-renewal deploy hook — on each cert renewal, the PFX is regenerated and Technitium is restarted automatically via `certbot.timer`

## What Syncs vs. What Doesn't

| Synced across all nodes | Per-node (independent) |
|---|---|
| Allowed / Blocked / Apps | Cache |
| Users, Groups, Permissions | Logs |
| API tokens | DHCP scopes |
| DNSSEC private keys (member zones) | Sessions |
| Cluster catalog zone membership | |

## Domain Design

| Purpose | Domain |
|---|---|
| Cluster coordination zone | `bruner.home` (private) |
| Node hostnames (post-init) | `<hostname>.bruner.home` |
| TLS certificate (ns1) | `ns1.colinbruner.com` (public LE cert) |
| TLS certificate (ns2) | `ns2.colinbruner.com` (public LE cert) |

The cluster domain and the TLS cert domain are independent. After the initial join, Technitium uses DANE-EE authentication based on each node's cert fingerprint (stored as TLSA records in the cluster zone) — the cert's domain name is irrelevant from that point on.

---

## Step 1 — Verify HTTPS is Working (Ansible-provisioned)

Ansible handles this automatically. Confirm before proceeding:

```bash
curl -sk https://192.168.1.3:53443 | grep -i technitium
curl -sk https://192.168.1.4:53443 | grep -i technitium
```

Both nodes should respond. The cert will be valid for `ns1.colinbruner.com` / `ns2.colinbruner.com` but the IP will work with `-k` for this check.

---

## Step 2 — Initialize the Primary Node (192.168.1.3)

1. Log in to `http://192.168.1.3:5380` as a user in the **Administrators** group.
2. Navigate to **Administration → Cluster**.
3. Click **Initialize → New Cluster**.
4. Fill in the dialog:
   - **Cluster Domain:** `bruner.home`
   - **Primary Node IP Addresses:** `192.168.1.3` (use Quick Add or enter manually)
5. Click **Initialize**.

Technitium will:
- Create the `bruner.home` primary zone and `cluster-catalog.bruner.home` catalog zone
- Update this node's DNS Server Domain Name to `<hostname>.bruner.home`
- Record the node's cert fingerprint as a TLSA record in the cluster zone

> **Note:** The cluster domain cannot be changed after initialization without deleting the cluster and starting over.

---

## Step 3 — Note the Primary Node URL

After initialization, still in **Administration → Cluster** (primary node selected), find the **Primary Node URL** — it will look like:

```
https://ns1.bruner.home:53443
```

Keep this handy for Step 4.

---

## Step 4 — Join the Secondary Node (192.168.1.4)

1. Log in to `http://192.168.1.4:5380`.
2. Navigate to **Administration → Cluster**.
3. Click **Initialize → Join Cluster**.
4. Fill in the dialog:
   - **Secondary Node IP Addresses:** `192.168.1.4`
   - **Primary Node URL:** the URL from Step 3
   - **Primary Node IP Address:** `192.168.1.3` — required because `bruner.home` is a private domain not resolvable from this node yet
   - **Certificate Validation:** check **Ignore Certificate Validation Errors** — necessary because `bruner.home` has no public DNS/DNSSEC so DANE-EE cannot be used for the initial join
   - **Primary Node Username / Password:** admin credentials for `192.168.1.3`
5. Click **Join**.

The secondary will authenticate, perform an initial full config sync (may take a moment if apps are installed), and HTTPS will be confirmed active on `.4`.

> After joining, all future node-to-node communication uses DANE-EE based on cert fingerprints — the "Ignore Certificate Validation" setting only applies to this one-time join.

---

## Step 5 — Verify the Cluster

1. In **Administration → Cluster** on either node, both nodes should appear with a healthy status.
2. Check **Dashboard** — use the node selector dropdown (top-right); you should see **Cluster** for aggregate stats plus each individual node.
3. In **Zones**, use the node selector to confirm you can view `.3` and `.4` independently.
4. If you see TLS errors in the DNS logs shortly after joining, the cluster secondary zone on `.4` may be stale. Force a resync:
   - **Administration → Cluster → (select secondary node) → Resync**

---

## Step 6 — Tune Cluster Timers (Optional)

Select the **primary node** in **Administration → Cluster → Options**:

| Setting | Purpose |
|---|---|
| Heartbeat Refresh Interval | How often nodes check each other's health |
| Heartbeat Retry Interval | Retry delay on heartbeat failure |
| Config Refresh Interval | How often secondary polls for config updates |
| Config Retry Interval | Retry delay on sync failure |

Defaults are fine for a homelab.

---

## Step 7 — Add Zones to the Cluster Catalog (Optional)

To sync a zone (and its DNSSEC private keys) across both nodes:

1. The zone must be a DNSSEC-signed primary zone.
2. In **Zones**, add it as a member of the `cluster-catalog.bruner.home` catalog zone.
3. The cluster automatically manages NS and SOA records for member zones and syncs DNSSEC keys to all nodes.

Zones not added to the cluster catalog continue to work independently on each node.

---

## Promoting a Secondary to Primary

If the primary (`192.168.1.3`) fails and is unrecoverable:

1. Log in to `192.168.1.4`.
2. **Administration → Cluster → (select secondary node context menu) → Promote To Primary**.

This kicks `.3` out of the cluster and promotes `.4` to primary. DNSSEC-signed member zones are automatically converted from secondary to primary using the synced private keys.

---

## Cert Renewal

Handled automatically by `certbot.timer` (runs twice daily). When a cert is within 30 days of expiry:

1. certbot renews via Cloudflare DNS-01
2. The deploy hook at `/etc/letsencrypt/renewal-hooks/deploy/technitium.sh` regenerates the PFX
3. Technitium is restarted to load the new cert

No manual intervention required.
