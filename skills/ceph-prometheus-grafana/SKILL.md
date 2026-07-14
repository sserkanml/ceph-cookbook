---
name: ceph-prometheus-grafana
description: This skill should be used when the user asks to monitor a Ceph cluster with Prometheus/Grafana — e.g. "enable ceph prometheus module", "ceph grafana dashboard", "monitor ceph metrics", "ceph exporter", "wire ceph into an existing prometheus". Covers the mgr prometheus module, the cephadm-bundled monitoring stack, external scrape config, and dashboard import.
version: 0.1.0
---

# Ceph Metrics with Prometheus & Grafana (cephadm)

## Overview

Exposing Ceph cluster metrics via the built-in `prometheus` mgr module and wiring them into
a Prometheus + Grafana stack — either cephadm's bundled monitoring stack (Prometheus,
Grafana, Alertmanager, node-exporter, all deployed as orchestrated daemons) or an existing
external Prometheus via scrape config.

## Placeholders

| Placeholder              | Meaning                                                | Example                     |
|-----------------------------|--------------------------------------------------------------|---------------------------------|
| `<PROMETHEUS_PORT>`        | mgr Prometheus exporter port                                    | `9283`                          |
| `<MGR_HOST_1>` / `<MGR_HOST_2>` | Mgr host(s) to scrape (repeat per mgr for HA)               | `mgr01` / `mgr02`               |
| `<SCRAPE_INTERVAL>`        | External Prometheus scrape interval                             | `15s`                            |
| `<EXTERNAL_PROMETHEUS_HOST>` | Address of an existing, already-deployed Prometheus            | `prom.example.com:9090`         |
| `<PROMETHEUS_HOST>`        | Host serving the Prometheus UI/API (bundled or external)         | `10.0.0.20`                      |
| `<DASHBOARD_ID>`           | Ceph Grafana dashboard id/uid to import                          | `2842` (Ceph Cluster)            |

## Prerequisites

1. Healthy cephadm-managed cluster with `ceph orch` available.
2. Decide up front: cephadm's bundled monitoring stack, or scrape into an already-existing
   external Prometheus.
3. Network path from the Prometheus host to each mgr's `<PROMETHEUS_PORT>`.

---

## 1. Enable the mgr Module (always required)

```bash
ceph mgr module enable prometheus
ceph mgr module ls | grep prometheus            # confirm "on"
curl -s http://<MGR_HOST_1>:<PROMETHEUS_PORT>/metrics | head   # raw metrics reachable
```

---

## 2. Option A — Deploy cephadm's Bundled Monitoring Stack

```bash
ceph orch apply node-exporter
ceph orch apply alertmanager
ceph orch apply prometheus
ceph orch apply grafana --placement="1"
ceph orch ps --daemon-type prometheus
ceph orch ps --daemon-type grafana
```

cephadm auto-generates the Prometheus scrape config (every mgr + node-exporter target) and
pre-wires the Ceph dashboards into Grafana — skip straight to Verify below.

---

## 2. Option B — Scrape into an Existing External Prometheus

```yaml
# prometheus.yml (add under scrape_configs:)
- job_name: 'ceph'
  scrape_interval: <SCRAPE_INTERVAL>
  static_configs:
    - targets: ['<MGR_HOST_1>:<PROMETHEUS_PORT>', '<MGR_HOST_2>:<PROMETHEUS_PORT>']
```

```bash
curl -X POST http://<EXTERNAL_PROMETHEUS_HOST>/-/reload   # requires --web.enable-lifecycle
```

---

## 3. Import Grafana Dashboards

cephadm's bundled Grafana ships these already. For an external Grafana: **Dashboards →
Import → dashboard id `<DASHBOARD_ID>`**, then select the Ceph Prometheus datasource.

---

## 4. Alertmanager Routing (optional)

```bash
ceph orch apply alertmanager --placement="1"
```

Edit the mounted `alertmanager.yml` to add receivers/routes, then:

```bash
ceph orch restart alertmanager
```

---

## Verify

```bash
ceph orch ps --daemon-type prometheus
ceph orch ps --daemon-type grafana
ceph orch ps --daemon-type alertmanager
curl -s http://<PROMETHEUS_HOST>:9095/api/v1/targets | grep ceph   # target reports "up"
```

Open the **Ceph Cluster** dashboard in Grafana and confirm panels populate (no "No data").
