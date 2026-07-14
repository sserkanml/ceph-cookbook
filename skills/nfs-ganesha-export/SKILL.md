---
name: nfs-ganesha-export
description: This skill should be used when the user asks to export Ceph storage over NFS — e.g. "nfs export from ceph", "deploy nfs-ganesha", "nfs over cephfs", "nfs over rgw bucket". Covers deploying the ceph orch-managed nfs-ganesha cluster and creating CephFS- or RGW-backed exports.
version: 0.1.0
---

# NFS-Ganesha Export (cephadm)

## Overview

Exposing CephFS or RGW storage over NFS using the `nfs-ganesha` service managed by
`ceph orch`. Creates an NFS cluster (one or more Ganesha daemons), then adds exports backed
by either a CephFS path or an RGW bucket.

## Placeholders

| Placeholder          | Meaning                                                  | Example         |
|------------------------|---------------------------------------------------------------|---------------------|
| `<NFS_CLUSTER_ID>`    | NFS cluster id                                                 | `nfs-cluster`       |
| `<PLACEMENT>`         | cephadm placement spec for Ganesha daemons                     | `count:2`            |
| `<PSEUDO_PATH>`       | NFSv4 pseudo path clients mount                                 | `/export1`           |
| `<FS_NAME>`           | Backing CephFS filesystem name (CephFS backend)                 | `cephfs`             |
| `<FS_PATH>`           | Path inside the CephFS to export                                | `/`                  |
| `<RGW_BUCKET>`        | Backing RGW bucket name (RGW backend)                           | `nfs-bucket`         |
| `<CLIENT_CIDR>`       | Client network allowed to mount                                 | `10.0.0.0/24`        |
| `<NFS_HOST>`          | VIP or Ganesha daemon host clients mount from                   | `10.0.0.30`          |
| `<NFS_CLIENT_MOUNT>`  | Client-side mountpoint                                          | `/mnt/nfs`            |

## Prerequisites

1. A healthy cephadm-managed cluster.
2. CephFS backend: filesystem already created (see [[cephfs-deploy]]).
3. RGW backend: RGW already deployed with `<RGW_BUCKET>` existing.
4. `nfs-utils`/`nfs-common` installed on client hosts.

---

## 1. Create the NFS Cluster

```bash
ceph nfs cluster create <NFS_CLUSTER_ID> --placement="<PLACEMENT>"
ceph orch ps --daemon-type nfs
```

---

## 2. Create an Export

**CephFS-backed:**

```bash
ceph nfs export create cephfs --cluster-id <NFS_CLUSTER_ID> --pseudo-path <PSEUDO_PATH> \
  --fsname <FS_NAME> --path <FS_PATH> --client_addr <CLIENT_CIDR>
```

**RGW-backed:**

```bash
ceph nfs export create rgw --cluster-id <NFS_CLUSTER_ID> --pseudo-path <PSEUDO_PATH> \
  --bucket <RGW_BUCKET> --client_addr <CLIENT_CIDR>
```

---

## 3. Confirm the Export is Registered

```bash
ceph nfs export ls <NFS_CLUSTER_ID>
ceph nfs export info <NFS_CLUSTER_ID> <PSEUDO_PATH>
```

---

## 4. Mount from a Client

```bash
mkdir -p <NFS_CLIENT_MOUNT>
mount -t nfs -o nfsvers=4.1 <NFS_HOST>:<PSEUDO_PATH> <NFS_CLIENT_MOUNT>
```

---

## 5. Verify

```bash
df -h <NFS_CLIENT_MOUNT>
touch <NFS_CLIENT_MOUNT>/test && ls <NFS_CLIENT_MOUNT>
ceph orch ps --daemon-type nfs   # all Ganesha daemons running
```
