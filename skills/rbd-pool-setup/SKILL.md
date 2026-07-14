---
name: rbd-pool-setup
description: This skill should be used when the user asks to create RBD (RADOS Block Device) storage on an existing Ceph cluster — e.g. "create an RBD pool", "set up block storage on Ceph", "rbd create image", "map an RBD device". Covers pool creation, image creation, scoped cephx client auth, and mapping/mounting.
version: 0.1.0
---

# RBD Pool & Image Setup

## Overview

Setting up RBD (RADOS Block Device) storage on an already-healthy Ceph cluster: create a
dedicated pool, initialize it for RBD use, create one or more images, grant a client
identity least-privilege access scoped to that pool, then map/mount the image.

## Placeholders

| Placeholder      | Meaning                                                  | Example                                          |
|--------------------|-------------------------------------------------------------|-----------------------------------------------------|
| `<POOL_NAME>`     | RBD pool name                                               | `rbd-pool`                                          |
| `<PG_NUM>`        | Placement group count for the pool                          | `128`                                               |
| `<IMAGE_NAME>`    | RBD image name                                               | `vol01`                                             |
| `<IMAGE_SIZE>`    | Image size                                                   | `50G`                                               |
| `<CLIENT_ID>`     | cephx client id (without the `client.` prefix)               | `rbd-client`                                        |
| `<FEATURES>`      | RBD image features to enable                                 | `layering,exclusive-lock,object-map,fast-diff`      |

## Prerequisites

1. A healthy Ceph cluster reachable via `ceph`/`rbd` CLI (native client or `cephadm shell`)
   with an admin keyring.
2. Enough free OSD capacity for the new pool at the target `<PG_NUM>`.
3. On consumer hosts: the kernel `rbd` module (for kernel-mapped block devices) or `librbd`
   (for QEMU/libvirt-attached images).

---

## 1. Create and Initialize the Pool

```bash
ceph osd pool create <POOL_NAME> <PG_NUM> <PG_NUM>
ceph osd pool application enable <POOL_NAME> rbd
rbd pool init <POOL_NAME>
```

---

## 2. Create the Image

```bash
rbd create <IMAGE_NAME> --size <IMAGE_SIZE> --pool <POOL_NAME> --image-feature <FEATURES>
rbd info <POOL_NAME>/<IMAGE_NAME>
```

---

## 3. Create a Scoped Client

Least-privilege: this client can only touch `<POOL_NAME>`, nothing else in the cluster.

```bash
ceph auth get-or-create client.<CLIENT_ID> \
  mon 'profile rbd' \
  osd 'profile rbd pool=<POOL_NAME>' \
  -o /etc/ceph/ceph.client.<CLIENT_ID>.keyring

ceph auth get client.<CLIENT_ID>
```

---

## 4. Map and Mount (kernel client)

```bash
rbd map <IMAGE_NAME> --pool <POOL_NAME> --id <CLIENT_ID>
mkfs.xfs /dev/rbd/<POOL_NAME>/<IMAGE_NAME>
mkdir -p /mnt/<IMAGE_NAME>
mount /dev/rbd/<POOL_NAME>/<IMAGE_NAME> /mnt/<IMAGE_NAME>
```

> For QEMU/libvirt consumers, skip the kernel map and attach the image directly via a
> `<disk type='network'>` libvirt XML stanza (or `-drive file=rbd:<POOL_NAME>/<IMAGE_NAME>`
> for raw QEMU) using the same `<CLIENT_ID>` keyring.

---

## 5. Verify

```bash
rbd ls -p <POOL_NAME>
rbd showmapped
ceph osd pool stats <POOL_NAME>
df -h /mnt/<IMAGE_NAME>
```
