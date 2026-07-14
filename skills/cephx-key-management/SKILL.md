---
name: cephx-key-management
description: This skill should be used when the user asks to create, scope, audit, or rotate Ceph client credentials — e.g. "create a ceph client key", "cephx capabilities", "rotate ceph credentials", "least privilege ceph auth", "audit ceph keyrings". Covers scoped RBD/CephFS client keys, capability auditing, rotation, and revocation.
version: 0.1.0
---

# cephx Key Management

## Overview

Managing cephx authentication identities: creating least-privilege client keys for RBD/
CephFS/RGW consumers, auditing existing keys for over-broad capabilities, and rotating or
revoking them safely.

## Placeholders

| Placeholder        | Meaning                                                | Example         |
|------------------------|----------------------------------------------------------|---------------------|
| `<CLIENT_ID>`         | Client identity name (without the `client.` prefix)         | `app01`             |
| `<POOL_NAME>`         | Pool the client should be scoped to                          | `rbd-pool`           |
| `<FS_NAME>`           | CephFS filesystem name (CephFS clients)                      | `cephfs`             |
| `<FS_PATH>`           | Path restriction inside CephFS                                | `/app01`             |
| `<CAPS_MON>`          | Custom mon capability string                                  | `profile rbd`        |
| `<CAPS_OSD>`          | Custom osd capability string                                  | `profile rbd pool=rbd-pool` |
| `<CAPS_MDS>`          | Custom mds capability string                                  | `allow rw path=/app01` |

## Prerequisites

1. Admin keyring access to the cluster.
2. Know exactly which pool(s)/path(s) the new client needs — resist granting cluster-wide
   `allow *`.
3. Review the existing keyring inventory (`ceph auth ls`) before adding overlapping or
   duplicate identities.

---

## A. Least-Privilege RBD Client

```bash
ceph auth get-or-create client.<CLIENT_ID> \
  mon 'profile rbd' \
  osd 'profile rbd pool=<POOL_NAME>' \
  -o /etc/ceph/ceph.client.<CLIENT_ID>.keyring
```

---

## B. Path-Restricted CephFS Client

```bash
ceph fs authorize <FS_NAME> client.<CLIENT_ID> <FS_PATH> rw \
  -o /etc/ceph/ceph.client.<CLIENT_ID>.keyring
```

---

## C. Fully Custom Capabilities

```bash
ceph auth get-or-create client.<CLIENT_ID> \
  mon "<CAPS_MON>" \
  osd "<CAPS_OSD>" \
  mds "<CAPS_MDS>" \
  -o /etc/ceph/ceph.client.<CLIENT_ID>.keyring
```

---

## D. Audit Existing Keys

```bash
ceph auth ls
ceph auth get client.<CLIENT_ID>
```

Flag any identity carrying `mon 'allow *'` or `osd 'allow *'` that isn't meant to be
admin-equivalent.

---

## E. Rotate a Key

`ceph auth get-or-create-key` does **not** rotate an existing key — delete and recreate the
identity to actually change its secret:

```bash
ceph auth rm client.<CLIENT_ID>
ceph auth get-or-create client.<CLIENT_ID> \
  mon 'profile rbd' osd 'profile rbd pool=<POOL_NAME>' \
  -o /etc/ceph/ceph.client.<CLIENT_ID>.keyring.new
```

> Distribute the `.new` keyring to consumers and confirm they've picked it up **before**
> this step — `ceph auth rm` invalidates the previous key cluster-wide immediately.

---

## F. Revoke

```bash
ceph auth rm client.<CLIENT_ID>
```

---

## Verify

```bash
ceph auth get client.<CLIENT_ID>
rados -p <POOL_NAME> --id <CLIENT_ID> ls          # scoped access works
rados -p <SOME_OTHER_POOL> --id <CLIENT_ID> ls    # expect permission denied
```
