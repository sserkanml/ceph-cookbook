---
name: rbd-mirror-dr
description: This skill should be used when the user asks to set up RBD mirroring for block-storage disaster recovery between two Ceph clusters — e.g. "set up rbd mirroring", "rbd-mirror journal mode", "rbd snapshot mirroring", "block storage DR for ceph". Covers journal-based and snapshot-based mirroring plus failover/promote.
version: 0.1.0
---

# RBD Mirroring for Disaster Recovery

## Overview

RBD mirroring replicates block images between two independent Ceph clusters for disaster
recovery, driven by the `rbd-mirror` daemon and `rbd mirror` CLI. Two modes: **journal**
mode (continuous, lower RPO, higher write overhead) or **snapshot** mode (periodic,
schedule-driven, lower overhead). This is the RBD analogue of RGW multisite
([[rgw-multisite-ceph]]) — same peer/bootstrap pattern, different data path.

## Placeholders

| Placeholder             | Meaning                                                     | Example        |
|---------------------------|------------------------------------------------------------------|-------------------|
| `<POOL_NAME>`            | Pool being mirrored (must exist identically on both clusters)     | `rbd-pool`       |
| `<MODE>`                 | Mirror mode                                                        | `pool` or `image` |
| `<PRIMARY_SITE>`         | Site name for the primary cluster                                  | `site-a`          |
| `<SECONDARY_SITE>`       | Site name for the secondary cluster                                | `site-b`          |
| `<IMAGE_NAME>`           | Image to enable mirroring on (image mode)                          | `vol01`           |
| `<SNAPSHOT_SCHEDULE>`    | Snapshot cadence (snapshot mode only)                               | `1h`              |

## Prerequisites

1. Both clusters are healthy, cephadm-managed, and `<POOL_NAME>` already exists identically
   on both (see [[rbd-pool-setup]]).
2. Network reachability between clusters — the `rbd-mirror` daemon on each side polls the
   remote cluster continuously.
3. Ceph version supports the desired mode (snapshot mode requires Octopus+); journal mode has
   a lower RPO but adds per-write overhead — pick the mode up front, switching later requires
   re-enabling mirroring per image.

---

## 1. Enable Pool Mirroring (both clusters)

```bash
# On the primary cluster:
rbd mirror pool enable <POOL_NAME> <MODE> --site-name <PRIMARY_SITE>

# On the secondary cluster:
rbd mirror pool enable <POOL_NAME> <MODE> --site-name <SECONDARY_SITE>
```

---

## 2. Exchange Bootstrap Peer Tokens

```bash
# On the primary:
rbd mirror pool peer bootstrap create <POOL_NAME> --site-name <PRIMARY_SITE> > /tmp/token

# Copy /tmp/token to the secondary cluster, then on the secondary:
rbd mirror pool peer bootstrap import <POOL_NAME> --site-name <SECONDARY_SITE> \
  --direction rx-tx /tmp/token
```

---

## 3. Deploy the rbd-mirror Daemon (both clusters, cephadm)

```bash
ceph orch apply rbd-mirror --placement="1"
ceph orch ps --daemon-type rbd-mirror
```

---

## 4. Enable Mirroring on an Image

**Journal mode:**

```bash
rbd feature enable <POOL_NAME>/<IMAGE_NAME> journaling
rbd mirror image enable <POOL_NAME>/<IMAGE_NAME> journal
```

**Snapshot mode:**

```bash
rbd mirror image enable <POOL_NAME>/<IMAGE_NAME> snapshot
rbd mirror snapshot schedule add --pool <POOL_NAME> --image <IMAGE_NAME> <SNAPSHOT_SCHEDULE>
```

> In `pool` mode, every image in `<POOL_NAME>` mirrors automatically — skip per-image enable.

---

## 5. Verify

```bash
rbd mirror pool status <POOL_NAME> --verbose
rbd mirror image status <POOL_NAME>/<IMAGE_NAME>
```

Expected: `state: up+replaying`, journal mode shows `entries behind master: 0`; snapshot
mode shows a recently synced snapshot timestamp.

---

## 6. Failover (on a DR event)

On the surviving (secondary) site, promote the image so it accepts writes:

```bash
rbd mirror image promote <POOL_NAME>/<IMAGE_NAME>            # clean failover, primary reachable
rbd mirror image promote <POOL_NAME>/<IMAGE_NAME> --force    # primary unreachable/destroyed
```

Once the original primary recovers, demote it and re-resync before resuming normal direction:

```bash
rbd mirror image demote <POOL_NAME>/<IMAGE_NAME>
rbd mirror image resync <POOL_NAME>/<IMAGE_NAME>
```
