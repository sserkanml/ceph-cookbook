---
name: osd-host-lifecycle
description: This skill should be used when the user asks to add, remove, replace, or drain OSDs/hosts on a cephadm-managed cluster — e.g. "remove an osd", "replace a failed disk", "drain a host", "decommission a ceph node", "add a new osd host". Covers planned removal, in-place disk replacement, and full host decommission.
version: 0.1.0
---

# OSD & Host Lifecycle (cephadm)

## Overview

Day-2 lifecycle operations for OSDs and hosts on a cephadm-managed cluster: adding a new
host and its disks, safely draining and removing an OSD (planned decommission or after a
disk failure), replacing a failed disk in place, and fully decommissioning a host.

## Placeholders

| Placeholder         | Meaning                                            | Example        |
|------------------------|---------------------------------------------------------|-------------------|
| `<NEW_HOST>`          | Hostname of a host being added                            | `node04`          |
| `<NEW_HOST_IP>`       | IP of a host being added                                   | `10.0.0.14`       |
| `<OSD_ID>`            | Numeric OSD id being drained/removed/replaced               | `12`               |
| `<HOST_TO_DRAIN>`     | Hostname being decommissioned                               | `node02`           |

## Prerequisites

1. Cluster is `HEALTH_OK` before starting a *planned* drain/removal (unplanned
   disk-failure remediation may reasonably start from `HEALTH_WARN`).
2. Enough spare capacity elsewhere to absorb data moving off the drained OSD(s)/host —
   check `ceph df` first.
3. Understand the CRUSH failure domain in play: draining an entire host briefly reduces
   redundancy for any pool whose failure domain is host-level (see [[crush-pool-tuning]]).

---

## A. Add a Host and Its OSDs

```bash
ssh-copy-id -f -i /etc/ceph/ceph.pub root@<NEW_HOST_IP>
ceph orch host add <NEW_HOST> <NEW_HOST_IP>
ceph orch device ls <NEW_HOST>
ceph orch apply osd --all-available-devices
ceph orch ps --daemon-type osd --hostname <NEW_HOST>
```

---

## B. Planned OSD Removal

```bash
ceph osd ok-to-stop osd.<OSD_ID>        # confirm safe to stop
ceph orch osd rm <OSD_ID> --replace     # --replace reserves the OSD id for reuse
ceph orch osd rm status                 # watch drain progress until empty
```

If the id does **not** need to be reused:

```bash
ceph osd purge <OSD_ID> --yes-i-really-mean-it
```

---

## C. Replace a Failed Disk (reuse the same OSD id)

```bash
ceph orch osd rm <OSD_ID> --replace --force   # --force needed if the OSD is already down
# physically swap the disk, then:
ceph orch device ls <HOST> --wide             # confirm the new device is detected
ceph orch apply osd --all-available-devices   # cephadm reuses the reserved OSD id
```

---

## D. Drain and Remove an Entire Host

```bash
ceph orch host drain <HOST_TO_DRAIN>
ceph orch osd rm status                       # watch all OSDs on the host drain out
ceph orch ps --hostname <HOST_TO_DRAIN>       # wait until empty except the cephadm agent
ceph orch host rm <HOST_TO_DRAIN>
```

---

## Verify

```bash
ceph -s              # HEALTH_OK, misplaced/degraded % back to 0
ceph osd tree         # confirms expected topology
ceph orch device ls   # no stray unclaimed devices where none expected
```
