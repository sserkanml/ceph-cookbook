---
name: rgw-multisite-rook
description: This skill should be used when the user asks to set up RGW (RADOS Gateway) multisite replication between two Rook-managed Ceph clusters — e.g. "set up Rook RGW multisite", "CephObjectRealm/CephObjectZone multisite setup", "configure multisite replication with Rook CRDs", "primary/secondary RGW zone with Rook". Platform-agnostic (works on any Kubernetes distribution running Rook, not tied to OpenShift/ODF).
version: 0.1.0
---

# RGW Multisite Replication with Rook — Setup

## Overview

RGW (RADOS Gateway) multisite replication between two Kubernetes clusters, each running a
Rook-managed Ceph cluster. Setup is done entirely through Rook CRDs (`CephObjectRealm`,
`CephObjectZoneGroup`, `CephObjectZone`, `CephObjectStore`) — no OpenShift/ODF dependency,
just Rook + `kubectl`.

Replication is **active-active (bidirectional)** by default; the metadata master is the
primary zone.

## Placeholders

Define these values up front and export them as shell variables on each cluster before
running any commands.

| Placeholder             | Meaning                                                        | Example                            |
|--------------------------|-----------------------------------------------------------------|-------------------------------------|
| `<NAMESPACE>`            | Namespace where Rook Ceph is deployed (same convention on both) | `rook-ceph`                         |
| `<REALM>`                | Realm name                                                       | `repl-realm`                        |
| `<ZONEGROUP>`            | ZoneGroup name                                                   | `repl-zonegroup`                    |
| `<PRIMARY_ZONE>`         | Primary (master) zone name                                       | `zone-primary`                      |
| `<SECONDARY_ZONE>`       | Secondary (slave) zone name                                      | `zone-secondary`                    |
| `<STORE>`                | Object store name (same on both clusters)                        | `multisite-store`                   |
| `<PRIMARY_ENDPOINT>`     | Address the secondary cluster can reach the primary RGW at       | `http://<primary-lb-or-ingress>`    |
| `<SECONDARY_ENDPOINT>`   | Address the primary cluster can reach the secondary RGW at       | `http://<secondary-lb-or-ingress>`  |
| `<SYS_ACCESS_KEY>`       | System user access key — **letters and digits only**             | `SYSKEY0PRIMARY01ABCDE`             |
| `<SYS_SECRET_KEY>`       | System user secret key — **letters and digits only**             | `SysSecret0NoSpecialChars0123456789ab` |

> ⚠️ Do **NOT** use `/` or `+` inside `<SYS_ACCESS_KEY>` / `<SYS_SECRET_KEY>` — these
> characters break SigV4 signing. Letters and digits only.

`<PRIMARY_ENDPOINT>` / `<SECONDARY_ENDPOINT>` just need to be whatever externally-reachable
address you expose the `rook-ceph-rgw-<STORE>` Service on — a `LoadBalancer` Service, an
Ingress, a NodePort, or any VPN/interconnect-reachable address. This runbook is agnostic to
which mechanism you use.

Toolbox pod reference used throughout:

```bash
NS=<NAMESPACE>
T=$(kubectl get pod -n $NS -l app=rook-ceph-tools -o name | head -1)
```

## Prerequisites

1. Rook Ceph deployed and healthy (`CephCluster` `Ready`) on both clusters.
2. **Bidirectional network reachability**: the secondary cluster must reach the primary RGW
   endpoint, and the primary cluster must reach the secondary RGW endpoint (multisite sync
   requires this both ways).
3. Whatever DNS/address you use for `<PRIMARY_ENDPOINT>` / `<SECONDARY_ENDPOINT>` must
   resolve and be routable from the other cluster.

---

## 1. Primary (Master) Cluster

Define variables:

```bash
NS=<NAMESPACE>
REALM=<REALM>; ZONEGROUP=<ZONEGROUP>; PRIMARY_ZONE=<PRIMARY_ZONE>; STORE=<STORE>
T=$(kubectl get pod -n $NS -l app=rook-ceph-tools -o name | head -1)
```

### 1.1 Realm + ZoneGroup + Zone

```yaml
# primary-multisite.yaml
---
apiVersion: ceph.rook.io/v1
kind: CephObjectRealm
metadata:
  name: <REALM>
  namespace: <NAMESPACE>
---
apiVersion: ceph.rook.io/v1
kind: CephObjectZoneGroup
metadata:
  name: <ZONEGROUP>
  namespace: <NAMESPACE>
spec:
  realm: <REALM>
---
apiVersion: ceph.rook.io/v1
kind: CephObjectZone
metadata:
  name: <PRIMARY_ZONE>
  namespace: <NAMESPACE>
spec:
  zoneGroup: <ZONEGROUP>
  metadataPool:
    failureDomain: host
    replicated: { size: 3 }
  dataPool:
    failureDomain: host
    replicated: { size: 3 }
  customEndpoints:
    - "<PRIMARY_ENDPOINT>"
  preservePoolsOnDelete: true
```

> `deviceClass` on the pools is optional — add it only if your CRUSH map uses device
> classes and you want to pin these pools to a specific one.

```bash
kubectl apply -f primary-multisite.yaml
kubectl get cephobjectzone <PRIMARY_ZONE> -n $NS -w   # wait for Ready
```

### 1.2 Object Store + expose endpoint

```yaml
# primary-store.yaml
---
apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: <STORE>
  namespace: <NAMESPACE>
spec:
  gateway:
    port: 80
    instances: 1
    resources:
      limits: { cpu: "1", memory: 1Gi }
      requests: { cpu: "500m", memory: 512Mi }
  zone:
    name: <PRIMARY_ZONE>
  preservePoolsOnDelete: true
```

> Add `gateway.placement` (nodeAffinity/tolerations) only if your cluster dedicates specific
> nodes to storage workloads — it's not required for multisite itself.

Rook creates a `rook-ceph-rgw-<STORE>` ClusterIP Service automatically. Expose it however
your platform supports cross-cluster reachability — e.g. a `LoadBalancer` Service:

```yaml
# primary-lb.yaml
apiVersion: v1
kind: Service
metadata:
  name: <STORE>-multisite-lb
  namespace: <NAMESPACE>
spec:
  type: LoadBalancer
  selector:
    app: rook-ceph-rgw
    rook_object_store: <STORE>
  ports:
    - name: http
      port: 80
      targetPort: 80
```

```bash
kubectl apply -f primary-store.yaml
kubectl apply -f primary-lb.yaml
kubectl get pod -n $NS -l rgw=<STORE> -w                 # wait for 2/2 Running
kubectl get cephobjectstore <STORE> -n $NS                # Ready
curl -s -o /dev/null -w "%{http_code}\n" <PRIMARY_ENDPOINT>   # expect 200
```

### 1.3 System User (URL-safe keys)

A **system user** on the realm is required for the secondary to pull the realm and for the
zones to authenticate to each other. Set the keys yourself, URL-safe (letters+digits only) —
do not use Rook's randomly generated key, which can contain `/` and break SigV4.

```bash
kubectl exec -n $NS $T -- radosgw-admin user create \
  --uid=<REALM>-system-user --display-name="Multisite System User" --system \
  --access-key="<SYS_ACCESS_KEY>" --secret-key="<SYS_SECRET_KEY>" \
  --rgw-realm=<REALM> --rgw-zonegroup=<ZONEGROUP> --rgw-zone=<PRIMARY_ZONE>

# Set the zone's system_key to the same keys + commit a new period
kubectl exec -n $NS $T -- radosgw-admin zone modify \
  --rgw-zone=<PRIMARY_ZONE> --rgw-zonegroup=<ZONEGROUP> --rgw-realm=<REALM> \
  --access-key="<SYS_ACCESS_KEY>" --secret-key="<SYS_SECRET_KEY>"
kubectl exec -n $NS $T -- radosgw-admin period update --commit \
  --rgw-realm=<REALM> --rgw-zonegroup=<ZONEGROUP> --rgw-zone=<PRIMARY_ZONE>

# Update the keys Secret Rook created for this realm to the same keys, so it stays
# consistent with the zone's system_key:
kubectl patch secret <REALM>-keys -n $NS --type=merge -p "{\"data\":{\
\"access-key\":\"$(printf %s '<SYS_ACCESS_KEY>' | base64 -w0)\",\
\"secret-key\":\"$(printf %s '<SYS_SECRET_KEY>' | base64 -w0)\"}}"

# Restart the gateway so it picks up the new system user + zone system_key
kubectl rollout restart deployment -n $NS -l rgw=<STORE>
```

---

## 2. Secondary (Slave) Cluster

Define variables (same REALM/ZONEGROUP/STORE, different zone):

```bash
NS=<NAMESPACE>
REALM=<REALM>; ZONEGROUP=<ZONEGROUP>; SECONDARY_ZONE=<SECONDARY_ZONE>; STORE=<STORE>
T=$(kubectl get pod -n $NS -l app=rook-ceph-tools -o name | head -1)
```

### 2.1 Keys Secret + Realm pull + ZoneGroup

Create a Secret containing the **same** system keys as the primary:

```bash
kubectl create secret generic <REALM>-keys -n $NS \
  --from-literal=access-key='<SYS_ACCESS_KEY>' \
  --from-literal=secret-key='<SYS_SECRET_KEY>'
```

```yaml
# secondary-realm.yaml
---
apiVersion: ceph.rook.io/v1
kind: CephObjectRealm
metadata:
  name: <REALM>
  namespace: <NAMESPACE>
spec:
  pull:
    endpoint: <PRIMARY_ENDPOINT>
---
apiVersion: ceph.rook.io/v1
kind: CephObjectZoneGroup
metadata:
  name: <ZONEGROUP>
  namespace: <NAMESPACE>
spec:
  realm: <REALM>
```

```bash
kubectl apply -f secondary-realm.yaml
# Wait for the realm to be pulled:
kubectl exec -n $NS $T -- radosgw-admin realm list                 # <REALM> should appear
kubectl get cephobjectzonegroup <ZONEGROUP> -n $NS                 # Ready
```

### 2.2 Secondary Zone + Object Store + expose endpoint

```yaml
# secondary-zone-store.yaml
---
apiVersion: ceph.rook.io/v1
kind: CephObjectZone
metadata:
  name: <SECONDARY_ZONE>
  namespace: <NAMESPACE>
spec:
  zoneGroup: <ZONEGROUP>
  metadataPool:
    failureDomain: host
    replicated: { size: 3 }
  dataPool:
    failureDomain: host
    replicated: { size: 3 }
  customEndpoints:
    - "<SECONDARY_ENDPOINT>"
  preservePoolsOnDelete: true
---
apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: <STORE>
  namespace: <NAMESPACE>
spec:
  gateway:
    port: 80
    instances: 1
    resources:
      limits: { cpu: "1", memory: 1Gi }
      requests: { cpu: "500m", memory: 512Mi }
  zone:
    name: <SECONDARY_ZONE>
  preservePoolsOnDelete: true
```

```yaml
# secondary-lb.yaml
apiVersion: v1
kind: Service
metadata:
  name: <STORE>-multisite-lb
  namespace: <NAMESPACE>
spec:
  type: LoadBalancer
  selector:
    app: rook-ceph-rgw
    rook_object_store: <STORE>
  ports:
    - name: http
      port: 80
      targetPort: 80
```

```bash
kubectl apply -f secondary-zone-store.yaml
kubectl apply -f secondary-lb.yaml
kubectl get cephobjectzone <SECONDARY_ZONE> -n $NS                 # Ready
kubectl get pod -n $NS -l rgw=<STORE> -w                            # wait for 2/2 Running
```

### 2.3 Start metadata sync (REQUIRED)

Metadata sync usually doesn't start automatically on the secondary; kick it off and restart
the gateway. This pulls all metadata, including the system user, from the primary and opens
the **reverse-direction** sync.

```bash
kubectl exec -n $NS $T -- radosgw-admin metadata sync init --rgw-realm=<REALM>
kubectl rollout restart deployment -n $NS -l rgw=<STORE>
# Once the RGW is 2/2, the system user should be replicated to the secondary:
kubectl exec -n $NS $T -- radosgw-admin user list --rgw-realm=<REALM>   # <REALM>-system-user
```

---

## 3. Verify

Run on both clusters:

```bash
kubectl exec -n $NS $T -- radosgw-admin sync status --rgw-realm=<REALM>
```

Expected:
- Primary: `metadata sync: no sync (zone is master)`, `data ... caught up with source`
- Secondary: `metadata is caught up with master`, `data is caught up with source`

No `Permission denied` / `failed` should appear anywhere.
