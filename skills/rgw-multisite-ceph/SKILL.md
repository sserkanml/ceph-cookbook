---
name: rgw-multisite-ceph
description: This skill should be used when the user asks to set up RGW (RADOS Gateway) multisite replication between two Ceph clusters using native Ceph tooling — e.g. "set up RGW multisite with radosgw-admin", "cephadm RGW multisite", "configure realm/zonegroup/zone without Rook", "primary/secondary RGW zone on bare-metal/cephadm Ceph". No Kubernetes/Rook — plain `radosgw-admin` + `ceph orch` (cephadm).
version: 0.1.0
---

# RGW Multisite Replication with Ceph — Setup

## Overview

RGW (RADOS Gateway) multisite replication between two independent, cephadm-managed Ceph
clusters, configured directly with `radosgw-admin` and `ceph orch` — no Kubernetes, no Rook.
This is the same realm/zonegroup/zone model as the Rook version, just driven straight
against the Ceph cluster.

Replication is **active-active (bidirectional)** by default; the metadata master is the
primary zone.

## Placeholders

Define these values up front and export them as shell variables on each cluster before
running any commands.

| Placeholder             | Meaning                                                        | Example                              |
|--------------------------|-----------------------------------------------------------------|----------------------------------------|
| `<REALM>`                | Realm name                                                       | `repl-realm`                          |
| `<ZONEGROUP>`            | ZoneGroup name                                                   | `repl-zonegroup`                      |
| `<PRIMARY_ZONE>`         | Primary (master) zone name                                       | `zone-primary`                        |
| `<SECONDARY_ZONE>`       | Secondary (slave) zone name                                      | `zone-secondary`                      |
| `<RGW_SVC_ID>`           | cephadm RGW service id (same convention on both clusters)        | `multisite`                           |
| `<PLACEMENT>`            | cephadm placement spec for the RGW daemon(s)                     | `count:1` or `label:rgw`              |
| `<PRIMARY_ENDPOINT>`     | Address the secondary cluster can reach the primary RGW at       | `http://<primary-host-or-vip>:80`     |
| `<SECONDARY_ENDPOINT>`   | Address the primary cluster can reach the secondary RGW at       | `http://<secondary-host-or-vip>:80`   |
| `<SYS_ACCESS_KEY>`       | System user access key — **letters and digits only**             | `SYSKEY0PRIMARY01ABCDE`               |
| `<SYS_SECRET_KEY>`       | System user secret key — **letters and digits only**             | `SysSecret0NoSpecialChars0123456789ab`|

> ⚠️ Do **NOT** use `/` or `+` inside `<SYS_ACCESS_KEY>` / `<SYS_SECRET_KEY>` — these
> characters break SigV4 signing. Letters and digits only.

All commands below assume a `cephadm shell` (or any host with a working `ceph`/`radosgw-admin`
CLI and an admin keyring) on the respective cluster.

## Prerequisites

1. Both clusters are healthy (`ceph -s` → `HEALTH_OK`/`HEALTH_WARN` with no blocking issues)
   and cephadm-managed (`ceph orch ls` works).
2. **Bidirectional network reachability**: the secondary cluster must reach the primary RGW
   endpoint, and the primary cluster must reach the secondary RGW endpoint (multisite sync
   requires this both ways).
3. Neither cluster already has a conflicting default realm/zonegroup/zone from a prior
   single-site RGW setup — if it does, reconcile that first, since this walkthrough assumes
   a clean slate for the realm being created here.
4. Whatever DNS/address you use for `<PRIMARY_ENDPOINT>` / `<SECONDARY_ENDPOINT>` must
   resolve and be routable from the other cluster.

---

## 1. Primary (Master) Cluster

### 1.1 Realm + ZoneGroup + Zone

```bash
radosgw-admin realm create --rgw-realm=<REALM> --default

radosgw-admin zonegroup create --rgw-zonegroup=<ZONEGROUP> --rgw-realm=<REALM> \
  --endpoints=<PRIMARY_ENDPOINT> --master --default

radosgw-admin zone create --rgw-zonegroup=<ZONEGROUP> --rgw-zone=<PRIMARY_ZONE> \
  --endpoints=<PRIMARY_ENDPOINT> --master --default

radosgw-admin period update --commit
```

### 1.2 System User (URL-safe keys)

A **system user** on the realm is required for the secondary to pull the realm and for the
zones to authenticate to each other. Set the keys yourself, URL-safe (letters+digits only).

```bash
radosgw-admin user create --uid="<REALM>-system-user" --display-name="Multisite System User" \
  --access-key="<SYS_ACCESS_KEY>" --secret-key="<SYS_SECRET_KEY>" --system

# Set the zone's system_key to the same keys + commit a new period
radosgw-admin zone modify --rgw-zone=<PRIMARY_ZONE> --rgw-zonegroup=<ZONEGROUP> --rgw-realm=<REALM> \
  --access-key="<SYS_ACCESS_KEY>" --secret-key="<SYS_SECRET_KEY>"

radosgw-admin period update --commit
```

### 1.3 Deploy the RGW daemon on this zone

```bash
ceph orch apply rgw <RGW_SVC_ID> --realm=<REALM> --zone=<PRIMARY_ZONE> --placement="<PLACEMENT>"
```

```bash
ceph orch ps --daemon-type rgw                                    # wait for running
curl -s -o /dev/null -w "%{http_code}\n" <PRIMARY_ENDPOINT>       # expect 200
```

---

## 2. Secondary (Slave) Cluster

### 2.1 Pull the realm + period from the primary

```bash
radosgw-admin realm pull --url=<PRIMARY_ENDPOINT> \
  --access-key="<SYS_ACCESS_KEY>" --secret-key="<SYS_SECRET_KEY>" --default

radosgw-admin period pull --url=<PRIMARY_ENDPOINT> \
  --access-key="<SYS_ACCESS_KEY>" --secret-key="<SYS_SECRET_KEY>"
```

### 2.2 Create the secondary zone

```bash
radosgw-admin zone create --rgw-zonegroup=<ZONEGROUP> --rgw-zone=<SECONDARY_ZONE> \
  --endpoints=<SECONDARY_ENDPOINT> \
  --access-key="<SYS_ACCESS_KEY>" --secret-key="<SYS_SECRET_KEY>" --default

radosgw-admin period update --commit --rgw-zone=<SECONDARY_ZONE>
```

### 2.3 Deploy the RGW daemon on this zone

```bash
ceph orch apply rgw <RGW_SVC_ID> --realm=<REALM> --zone=<SECONDARY_ZONE> --placement="<PLACEMENT>"
```

```bash
ceph orch ps --daemon-type rgw                                    # wait for running
```

### 2.4 Start metadata sync (REQUIRED)

Metadata sync usually doesn't start automatically on the secondary; kick it off and restart
the gateway. This pulls all metadata, including the system user, from the primary and opens
the **reverse-direction** sync.

```bash
radosgw-admin metadata sync init --rgw-realm=<REALM>
ceph orch restart rgw.<RGW_SVC_ID>
# Once the RGW is back up, the system user should be replicated to the secondary:
radosgw-admin user list --rgw-realm=<REALM>                       # <REALM>-system-user
```

---

## 3. Verify

Run on both clusters:

```bash
radosgw-admin sync status --rgw-realm=<REALM>
```

Expected:
- Primary: `metadata sync: no sync (zone is master)`, `data ... caught up with source`
- Secondary: `metadata is caught up with master`, `data is caught up with source`

No `Permission denied` / `failed` should appear anywhere.
