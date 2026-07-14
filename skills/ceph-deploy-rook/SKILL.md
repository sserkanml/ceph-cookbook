---
name: ceph-deploy-rook
description: This skill should be used when the user asks to deploy or install a Ceph cluster on Kubernetes using Rook — e.g. "deploy Ceph with Rook", "install rook-ceph operator", "bootstrap a CephCluster CRD", "set up Rook on Kubernetes". Platform-agnostic (works on any Kubernetes distribution, not tied to OpenShift/ODF).
version: 0.1.0
---

# Ceph Cluster Deployment with Rook — Setup

## Overview

Deploying a Ceph cluster on Kubernetes using the Rook operator: install the Rook Ceph
operator, then create a `CephCluster` custom resource that Rook reconciles into a full Ceph
cluster (mons, mgrs, OSDs) on top of your nodes' raw block devices.

## Placeholders

| Placeholder       | Meaning                                                  | Example        |
|--------------------|-----------------------------------------------------------|-----------------|
| `<NAMESPACE>`      | Namespace for the Rook operator + Ceph cluster             | `rook-ceph`     |
| `<ROOK_VERSION>`   | Rook release/tag to install                                | `v1.14.9`       |
| `<CEPH_IMAGE>`     | Ceph container image/version Rook should deploy            | `quay.io/ceph/ceph:v18.2.4` |
| `<CLUSTER_NAME>`   | Name of the `CephCluster` CR (usually same as namespace)   | `rook-ceph`     |
| `<MON_COUNT>`      | Number of mon daemons (odd number, quorum)                 | `3`             |
| `<DEVICE_FILTER>`  | Device name filter/regex for OSD candidate disks           | `^sd[b-d]$`     |

## Prerequisites

1. A Kubernetes cluster (any distribution) with `kubectl` access and cluster-admin rights.
2. At least 3 nodes (for mon quorum + OSD spread across failure domains) with raw,
   unformatted block devices available for OSDs — Rook will not consume a device that
   already has a filesystem or partition table on it.
3. The `rbd` kernel module available on nodes if RBD block storage will be consumed later.
4. Outbound access to pull the Rook operator image and the Ceph container image
   (`<CEPH_IMAGE>`), or a mirrored registry reachable from the cluster.

---

## 1. Install the Rook Operator

Using the official manifests:

```bash
git clone --single-branch --branch <ROOK_VERSION> https://github.com/rook/rook.git
cd rook/deploy/examples

kubectl apply -f crds.yaml -f common.yaml -f operator.yaml
```

```bash
kubectl get pods -n <NAMESPACE> -w   # wait for rook-ceph-operator-... Running
```

Helm alternative:

```bash
helm repo add rook-release https://charts.rook.io/release
helm repo update
helm install rook-ceph rook-release/rook-ceph \
  --namespace <NAMESPACE> --create-namespace \
  --version <ROOK_VERSION>
```

---

## 2. Deploy the CephCluster

```yaml
# cluster.yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: <CLUSTER_NAME>
  namespace: <NAMESPACE>
spec:
  cephVersion:
    image: <CEPH_IMAGE>
  dataDirHostPath: /var/lib/rook
  mon:
    count: <MON_COUNT>
    allowMultiplePerNode: false
  mgr:
    count: 2
    allowMultiplePerNode: false
  dashboard:
    enabled: true
  storage:
    useAllNodes: true
    useAllDevices: false
    deviceFilter: "<DEVICE_FILTER>"
  disruptionManagement:
    managePodBudgets: true
```

> Set `useAllDevices: true` (and drop `deviceFilter`) if every raw block device on every
> node should become an OSD. Otherwise scope OSD candidates with `deviceFilter`, or switch
> to an explicit per-node `nodes:` list for full control.

```bash
kubectl apply -f cluster.yaml
kubectl get cephcluster <CLUSTER_NAME> -n <NAMESPACE> -w   # wait for phase Ready / HEALTH_OK
```

---

## 3. Deploy the Toolbox

Needed to run `ceph`/`radosgw-admin`/etc. commands against the cluster for verification and
day-2 admin.

```yaml
# toolbox.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rook-ceph-tools
  namespace: <NAMESPACE>
  labels:
    app: rook-ceph-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rook-ceph-tools
  template:
    metadata:
      labels:
        app: rook-ceph-tools
    spec:
      dnsPolicy: ClusterFirstWithHostNet
      containers:
        - name: rook-ceph-tools
          image: <CEPH_IMAGE>
          command: ["/bin/bash"]
          args: ["-m", "-c", "/usr/local/bin/toolbox.sh"]
          imagePullPolicy: IfNotPresent
          env:
            - name: ROOK_CEPH_USERNAME
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-mon
                  key: ceph-username
            - name: ROOK_CEPH_SECRET
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-mon
                  key: ceph-secret
          volumeMounts:
            - mountPath: /etc/ceph
              name: ceph-config
            - name: mon-endpoint-volume
              mountPath: /etc/rook
      volumes:
        - name: mon-endpoint-volume
          configMap:
            name: rook-ceph-mon-endpoints
            items:
              - key: data
                path: mon-endpoints
        - name: ceph-config
          emptyDir: {}
      tolerations:
        - key: "node.rook.io/tolerable"
          operator: Exists
```

```bash
kubectl apply -f toolbox.yaml
kubectl get pod -n <NAMESPACE> -l app=rook-ceph-tools -w   # wait for Running
```

---

## 4. Verify

```bash
T=$(kubectl get pod -n <NAMESPACE> -l app=rook-ceph-tools -o name | head -1)

kubectl exec -n <NAMESPACE> $T -- ceph status       # expect HEALTH_OK
kubectl exec -n <NAMESPACE> $T -- ceph osd status    # all OSDs up/in
kubectl exec -n <NAMESPACE> $T -- ceph mon stat      # quorum size == <MON_COUNT>
kubectl get pods -n <NAMESPACE>                       # mon/mgr/osd pods all Running
```
