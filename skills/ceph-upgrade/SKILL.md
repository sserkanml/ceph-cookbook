---
name: ceph-upgrade
description: This skill should be used when the user asks to upgrade a cephadm-managed Ceph cluster — e.g. "upgrade ceph", "ceph orch upgrade", "update ceph version", "roll out a new ceph release". Covers pre-flight checks, the orchestrator-driven rolling upgrade, monitoring, pause/resume, and verification.
version: 0.1.0
---

# Ceph Cluster Upgrade (cephadm)

## Overview

Rolling upgrade of a cephadm-managed cluster using the built-in orchestrator upgrade
workflow. cephadm upgrades daemons in a safe order (mgr → mon → crash → osd → mds/rgw → ...),
one failure domain at a time, and auto-pauses if cluster health degrades mid-upgrade.

## Placeholders

| Placeholder          | Meaning                                                   | Example                       |
|------------------------|----------------------------------------------------------------|----------------------------------|
| `<TARGET_VERSION>`    | Target Ceph container image/tag                                 | `quay.io/ceph/ceph:v18.2.4`     |

## Prerequisites

1. Cluster is currently `HEALTH_OK` (or only a benign, understood `HEALTH_WARN`) — never
   start an upgrade on a degraded cluster.
2. Release notes for `<TARGET_VERSION>` reviewed for breaking changes; Ceph generally only
   supports upgrading N → N+1 or N+2 major versions, not arbitrary jumps.
3. Recent backup/export of cluster config, per org policy.
4. No other maintenance (host drain, OSD replacement — see [[osd-host-lifecycle]]) is in
   progress.

---

## 1. Pre-flight Check

```bash
ceph -s                                  # must be HEALTH_OK
ceph orch upgrade check <TARGET_VERSION>
```

---

## 2. Start the Upgrade

```bash
ceph orch upgrade start --image <TARGET_VERSION>
```

---

## 3. Monitor Progress

```bash
ceph orch upgrade status
ceph -W cephadm          # tail cephadm's upgrade log
watch ceph -s
```

---

## 4. Resume After an Assessed-Safe Pause

cephadm pauses automatically on health warnings during the rollout.

```bash
ceph orch upgrade resume
```

---

## 5. Abort

```bash
ceph orch upgrade pause
ceph orch upgrade stop
```

> `ceph orch upgrade stop` does **not** roll back daemons already upgraded — cephadm has no
> supported downgrade path. Investigate and fix forward once stopped.

---

## 6. Verify Completion

```bash
ceph orch upgrade status   # "There are no upgrades in progress"
ceph versions              # every daemon reports <TARGET_VERSION>
ceph -s                    # HEALTH_OK
```
