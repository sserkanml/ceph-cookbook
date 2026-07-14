---
name: ceph-deploy-cephadm
description: This skill should be used when the user asks to deploy or install a Ceph cluster on bare-metal/VMs using cephadm — e.g. "deploy Ceph with cephadm", "cephadm bootstrap", "install Ceph without Kubernetes", "set up a Ceph cluster on bare-metal". No Kubernetes/Rook — plain `cephadm` + `ceph orch`, container-orchestrated Ceph daemons directly on hosts.
version: 0.1.0
---

# Ceph Cluster Deployment with cephadm — Setup

## Overview

Deploying a Ceph cluster directly on bare-metal/VM hosts using `cephadm`: bootstrap the
first monitor/manager on one host, add the remaining hosts over SSH, then let the
orchestrator (`ceph orch`) place mons, mgrs, and OSDs across the cluster. Same end result as
the Rook skill (mons, mgrs, OSDs, HEALTH_OK) but driven straight against hosts and podman/
docker containers — no Kubernetes involved.

## Placeholders

| Placeholder          | Meaning                                                        | Example                       |
|------------------------|-------------------------------------------------------------------|----------------------------------|
| `<BOOTSTRAP_IP>`      | IP address of the first host, used for the initial mon            | `10.0.0.11`                    |
| `<CEPH_IMAGE>`        | Ceph container image/version cephadm should deploy                 | `quay.io/ceph/ceph:v18.2.4`    |
| `<CLUSTER_NAME>`      | Cluster name (usually `ceph`, only change for multi-cluster hosts) | `ceph`                          |
| `<ADMIN_USER>`        | Dashboard/admin initial username                                   | `admin`                        |
| `<ADMIN_PASSWORD>`    | Dashboard/admin initial password                                   | `StrongPass123!`               |
| `<HOST_N>` / `<HOST_N_IP>` | Additional host name / IP to add to the cluster                | `node02` / `10.0.0.12`         |
| `<MON_COUNT>`         | Number of mon daemons (odd number, quorum)                         | `3`                              |
| `<MGR_COUNT>`         | Number of mgr daemons                                              | `2`                              |
| `<DEVICE_FILTER>`     | Device name filter/regex for OSD candidate disks                   | `^sd[b-d]$`                     |

## Prerequisites

1. All hosts run a supported OS (RHEL/CentOS/Ubuntu) with `podman` or `docker`, `python3`,
   and `chrony`/`ntp` for time sync — cephadm refuses to proceed with clock drift or a
   missing container runtime.
2. Root (or passwordless-sudo) SSH access from the bootstrap host to every other host —
   cephadm generates its own SSH keypair and distributes the public key itself, but the
   target hosts must already accept a root login for that first copy.
3. At least 3 hosts total (for mon quorum + OSD spread across failure domains) with raw,
   unformatted block devices available for OSDs — cephadm/ceph-volume will not consume a
   device that already has a filesystem or partition table on it.
4. Outbound access from every host to pull `<CEPH_IMAGE>`, or a mirrored registry reachable
   from the cluster.
5. Network connectivity between all hosts on the public network (and cluster network, if
   separated).

---

## 1. Bootstrap the First Host

Install `cephadm` on the bootstrap host, then bootstrap the cluster:

```bash
curl --silent --remote-name --location https://raw.githubusercontent.com/ceph/ceph/reef/src/cephadm/cephadm
chmod +x cephadm
./cephadm add-repo --release reef
./cephadm install
```

```bash
cephadm bootstrap \
  --mon-ip <BOOTSTRAP_IP> \
  --image <CEPH_IMAGE> \
  --initial-dashboard-user <ADMIN_USER> \
  --initial-dashboard-password <ADMIN_PASSWORD> \
  --dashboard-password-noupdate \
  --allow-fqdn-hostname
```

This installs `cephadm`, starts the first mon + mgr containers, deploys the dashboard and
`crash` daemon, and writes an admin keyring/config to `/etc/ceph/`. The `ceph` CLI is
available on this host immediately via the bootstrapped `cephadm shell`, or install
`ceph-common` for a native client.

```bash
cephadm shell -- ceph -s   # wait for the single mon to be up
```

---

## 2. Add Hosts

Copy the cluster's public SSH key to each additional host, then register it with the
orchestrator:

```bash
for H in <HOST_N_IP>; do
  ssh-copy-id -f -i /etc/ceph/ceph.pub root@$H
done
```

```bash
cephadm shell -- ceph orch host add <HOST_N> <HOST_N_IP>
# repeat for every additional host
```

```bash
cephadm shell -- ceph orch host ls   # all hosts listed, all reachable
```

---

## 3. Place Mons, Mgrs, and OSDs

Scale mons/mgrs to the target count, then let the orchestrator claim available devices:

```bash
cephadm shell -- ceph orch apply mon --placement="<MON_COUNT>"
cephadm shell -- ceph orch apply mgr --placement="<MGR_COUNT>"
```

```bash
cephadm shell -- ceph orch device ls   # inspect available_for_osd column first
```

```bash
# Claim every available raw device on every host:
cephadm shell -- ceph orch apply osd --all-available-devices
```

For fine-grained control (specific hosts/devices), apply a DriveGroup spec instead:

```yaml
# osd-spec.yaml
service_type: osd
service_id: default_drive_group
placement:
  host_pattern: "*"
data_devices:
  path_pattern: "<DEVICE_FILTER>"
```

```bash
cephadm shell -m osd-spec.yaml -- ceph orch apply -i /mnt/osd-spec.yaml
```

```bash
cephadm shell -- ceph orch ps --daemon-type osd   # wait for all OSDs running
```

---

## 4. Verify

```bash
cephadm shell -- ceph status         # expect HEALTH_OK
cephadm shell -- ceph osd status     # all OSDs up/in
cephadm shell -- ceph mon stat       # quorum size == <MON_COUNT>
cephadm shell -- ceph orch ps        # mon/mgr/osd/crash daemons all running
```
