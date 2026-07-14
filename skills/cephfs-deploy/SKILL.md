---
name: cephfs-deploy
description: This skill should be used when the user asks to deploy CephFS or MDS daemons on a cephadm-managed Ceph cluster — e.g. "deploy cephfs", "create a ceph filesystem", "set up MDS", "mount cephfs". Covers pool creation, MDS deployment, filesystem creation, scoped client auth, and mounting.
version: 0.1.0
---

# CephFS Deployment with cephadm

## Overview

Deploying CephFS on an existing cephadm-managed Ceph cluster: create the metadata + data
pools, deploy MDS daemons via the orchestrator, create the filesystem, grant a
least-privilege client identity, then mount it from a client host.

## Placeholders

| Placeholder      | Meaning                                                  | Example              |
|--------------------|-------------------------------------------------------------|--------------------------|
| `<FS_NAME>`       | Filesystem name                                              | `cephfs`                |
| `<META_POOL>`     | Metadata pool name                                           | `cephfs_metadata`       |
| `<DATA_POOL>`     | Data pool name                                                | `cephfs_data`           |
| `<PG_NUM>`        | PG count for both pools                                       | `64`                    |
| `<MDS_COUNT>`     | Active MDS rank count (cluster also runs standbys)             | `1`                      |
| `<PLACEMENT>`     | cephadm placement spec for MDS daemons                         | `count:2`                |
| `<CLIENT_ID>`     | cephx client id (without `client.` prefix)                     | `cephfs-client`          |
| `<MON_HOST>`      | Mon host(s)/IPs the client connects to                         | `mon1,mon2,mon3`         |
| `<MOUNT_POINT>`   | Client-side mountpoint                                         | `/mnt/cephfs`            |

## Prerequisites

1. A healthy cephadm-managed cluster with `ceph orch` working.
2. Enough OSD capacity for two new pools.
3. On the client host: `ceph-common` (kernel mount, via `mount -t ceph`) or `ceph-fuse`.

---

## 1. Create the Pools

```bash
ceph osd pool create <META_POOL> <PG_NUM>
ceph osd pool create <DATA_POOL> <PG_NUM>
```

---

## 2. Create the Filesystem

```bash
ceph fs new <FS_NAME> <META_POOL> <DATA_POOL>
ceph fs ls
```

---

## 3. Deploy MDS Daemons

```bash
ceph orch apply mds <FS_NAME> --placement="<PLACEMENT>"
ceph orch ps --daemon-type mds
ceph fs status <FS_NAME>   # wait for at least one MDS in state=active
```

---

## 4. Scale Active Ranks (optional, for large workloads)

```bash
ceph fs set <FS_NAME> max_mds <MDS_COUNT>
```

> Keep at least one daemon beyond `max_mds` as standby (covered by `<PLACEMENT>` above) —
> multi-active MDS needs a healthy standby for failover of any given rank.

---

## 5. Create a Scoped Client

```bash
ceph fs authorize <FS_NAME> client.<CLIENT_ID> / rw \
  -o /etc/ceph/ceph.client.<CLIENT_ID>.keyring
```

---

## 6. Mount (kernel client)

```bash
grep key /etc/ceph/ceph.client.<CLIENT_ID>.keyring | awk '{print $NF}' > /etc/ceph/ceph.client.<CLIENT_ID>.secret

mkdir -p <MOUNT_POINT>
mount -t ceph <MON_HOST>:/ <MOUNT_POINT> \
  -o name=<CLIENT_ID>,secretfile=/etc/ceph/ceph.client.<CLIENT_ID>.secret
```

---

## 7. Verify

```bash
ceph fs status <FS_NAME>
df -h <MOUNT_POINT>
touch <MOUNT_POINT>/test && ls <MOUNT_POINT>
```
