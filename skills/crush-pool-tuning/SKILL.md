---
name: crush-pool-tuning
description: This skill should be used when the user asks to create or tune Ceph pools, CRUSH rules, or PG settings — e.g. "create an erasure coded pool", "change the crush rule", "set failure domain to rack", "enable pg autoscaler", "target ssd device class". Covers replicated pools, erasure-coded pools, custom CRUSH rules, and PG autoscaling.
version: 0.1.0
---

# CRUSH Rules & Pool Tuning

## Overview

Configuring pool redundancy strategy (replicated vs. erasure-coded), CRUSH placement rules
(failure domain, device class), and PG count — the knobs that determine durability, capacity
efficiency, and rebalancing behavior for a pool.

## Placeholders

| Placeholder            | Meaning                                            | Example            |
|---------------------------|-----------------------------------------------------------|------------------------|
| `<POOL_NAME>`            | Pool being created/tuned                                    | `data-pool`             |
| `<PG_NUM>`                | Initial PG count                                             | `128`                    |
| `<REPLICA_SIZE>`         | Replication factor (replicated pools)                        | `3`                       |
| `<FAILURE_DOMAIN>`       | CRUSH bucket type used as the failure domain                 | `host`, `rack`, `osd`     |
| `<DEVICE_CLASS>`         | OSD device class to target                                    | `hdd`, `ssd`, `nvme`      |
| `<CRUSH_RULE_NAME>`      | Name for a custom CRUSH rule                                  | `ssd-host-rule`           |
| `<EC_PROFILE_NAME>`      | Erasure-code profile name                                     | `ec-4-2`                  |
| `<EC_K>` / `<EC_M>`      | Data / coding chunk counts                                    | `4` / `2`                 |

## Prerequisites

1. Healthy cluster; know the current device-class layout (`ceph osd crush class ls`,
   `ceph osd tree`).
2. EC pools: enough independent failure domains to satisfy `k+m` without a single domain
   holding two chunks.
3. Note existing pool settings before changing `crush_rule` or `size` on a live pool —
   both trigger cluster-wide data movement.

---

## A. Replicated Pool with Explicit Failure Domain + Device Class

```bash
ceph osd crush rule create-replicated <CRUSH_RULE_NAME> default <FAILURE_DOMAIN> <DEVICE_CLASS>
ceph osd pool create <POOL_NAME> <PG_NUM> <PG_NUM> replicated <CRUSH_RULE_NAME>
ceph osd pool set <POOL_NAME> size <REPLICA_SIZE>
```

---

## B. Erasure-Coded Pool

```bash
ceph osd erasure-code-profile set <EC_PROFILE_NAME> \
  k=<EC_K> m=<EC_M> crush-failure-domain=<FAILURE_DOMAIN>

ceph osd pool create <POOL_NAME> <PG_NUM> <PG_NUM> erasure <EC_PROFILE_NAME>
ceph osd pool application enable <POOL_NAME> rbd   # or rgw / cephfs
```

> To use an EC pool as an RBD/CephFS **data** pool, enable overwrites (bluestore only):
> `ceph osd pool set <POOL_NAME> allow_ec_overwrites true`

---

## C. PG Autoscaling

```bash
ceph mgr module enable pg_autoscaler
ceph osd pool set <POOL_NAME> pg_autoscale_mode on   # on | warn | off
ceph osd pool autoscale-status
```

---

## D. Change CRUSH Rule on an Existing Pool

Triggers cluster-wide rebalance — expect misplaced-object percentage to rise then drain
back to 0.

```bash
ceph osd pool set <POOL_NAME> crush_rule <CRUSH_RULE_NAME>
ceph -s   # watch misplaced % drop back to 0
```

---

## Verify

```bash
ceph osd pool ls detail
ceph osd crush rule dump <CRUSH_RULE_NAME>
ceph osd pool autoscale-status
ceph -s                              # HEALTH_OK once any rebalance completes
```
