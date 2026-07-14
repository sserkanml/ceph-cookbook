# ceph-cookbook

A Claude Code plugin for deploying, operating, and troubleshooting Ceph storage clusters —
skills, agents, hooks, and monitors covering cluster setup (Rook or cephadm), block/file/
object storage, day-2 lifecycle operations, security, and observability.

## Installation

Add this repo as a plugin marketplace, then install the plugin:

```
/plugin marketplace add sserkanml/ceph-cookbook
/plugin install ceph-cookbook
```

## Skills

### Cluster deployment
| Skill | Use for |
|---|---|
| `ceph-deploy-rook` | Bootstrap a Ceph cluster on Kubernetes via the Rook operator + `CephCluster` CRD |
| `ceph-deploy-cephadm` | Bootstrap a Ceph cluster on bare-metal/VMs via `cephadm` + `ceph orch` |

### Object storage (RGW)
| Skill | Use for |
|---|---|
| `rgw-multisite-ceph` | RGW multisite replication between two cephadm-managed clusters (`radosgw-admin` + `ceph orch`) |
| `rgw-multisite-rook` | RGW multisite replication between two Rook-managed clusters (`CephObjectRealm`/`CephObjectZone` CRDs) |
| `rgw-user-quota-mgmt` | RGW S3 user lifecycle, access key rotation, quotas, bucket policies |

### Block & file storage
| Skill | Use for |
|---|---|
| `rbd-pool-setup` | Create an RBD pool/image, scope a cephx client, map/mount |
| `rbd-mirror-dr` | RBD mirroring (journal or snapshot mode) between two clusters for block-storage DR |
| `cephfs-deploy` | Deploy MDS daemons and create a CephFS filesystem via cephadm |
| `nfs-ganesha-export` | Export CephFS or an RGW bucket over NFS via `ceph orch`-managed NFS-Ganesha |

### Cluster lifecycle & tuning
| Skill | Use for |
|---|---|
| `ceph-upgrade` | Rolling cluster upgrade via `ceph orch upgrade`, with health gating |
| `osd-host-lifecycle` | Add/drain/remove OSDs and hosts, replace a failed disk |
| `crush-pool-tuning` | Replicated vs. erasure-coded pools, CRUSH failure domains, PG autoscaling |

### Security & observability
| Skill | Use for |
|---|---|
| `cephx-key-management` | Least-privilege client keyrings, capability auditing, key rotation/revocation |
| `ceph-prometheus-grafana` | Enable the mgr `prometheus` module and wire up Prometheus/Grafana dashboards |

## Agents

| Agent | Use for |
|---|---|
| `ceph-diagnostician` | Read-only health/OSD/PG/RGW-sync diagnosis; reports issues and recommended next steps, never remediates |
| `ceph-remediator` | Executes a fix for an already-diagnosed issue, with explicit risk classification and confirmation before medium/high-risk actions |

## Hooks & Monitors

- **`guard-dangerous-commands.sh`** (`PreToolUse` hook) — blocks irreversible commands
  (pool delete, OSD purge, realm/zone delete, force-repair, `--yes-i-really-mean-it`)
  before they run, regardless of prior confirmation.
- **`health-watch.sh`** (monitor) — reports `HEALTH_OK`/`WARN`/`ERR` transitions.
- **`rgw-sync-watch.sh`** (monitor) — reports RGW multisite sync status transitions
  (caught up / behind / failed).

## Output Styles

| Style | Use for |
|---|---|
| `ceph-incident` | Fast, command-first responses during a live incident |
| `ceph-postmortem` | Root-cause analysis and prevention, after the fact |
| `ceph-runbook` | Step-by-step, verifiable procedures for planned maintenance/setup |

## License

GPL-3.0 — see [LICENSE](LICENSE).
