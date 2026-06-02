# Enterprise Data Platform Core
## Master Platform Engineering Deployment Runbook

> **A unified infrastructure layer for 10 production-grade distributed systems: multi-tier Terraform provisioning, Kubernetes deployment manifests with strict health gates, automated data catalog extraction, and a complete FinOps cost model.**

---

## Table of Contents

1. [Platform Overview](#1-platform-overview)
2. [System Architecture Topology](#2-system-architecture-topology)
3. [Component Inventory](#3-component-inventory)
4. [Deployment Runbook](#4-deployment-runbook)
5. [Data Catalog Integration](#5-data-catalog-integration)
6. [FinOps Cost Projection Matrix](#6-finops-cost-projection-matrix)
7. [Operational Procedures](#7-operational-procedures)

---

## 1. Platform Overview

This repository provides the infrastructure layer that elevates 10 independently deployed engineering projects into a unified **Enterprise Data Platform Core**. Rather than 10 isolated services, the platform treats them as a cohesive data mesh: shared network topology, unified observability, centralized secret management, auto-scaling compute, and a live data catalog that continuously documents every schema.

The infrastructure is designed for **zero-cost local simulation** via LocalStack and Docker, with a production upgrade path to AWS that requires only changing three Terraform variables.

### Design Principles

- **Defense in depth** — network isolation (VPC tiers) + application middleware (NestJS) + database enforcement (PostgreSQL RLS) = three independent breach prevention layers
- **Infrastructure as Code** — every resource defined in Terraform, every deployment in Kubernetes YAML, zero manual cloud console operations
- **FinOps by default** — resource limits on every pod, auto-scaling with cooldown windows, Spot/Fargate mix, S3 lifecycle policies, and reserved capacity for predictable workloads
- **Observability first** — Prometheus metrics, CloudWatch alarms, structured logging, and an automated data catalog that runs on every deployment

---

## 2. System Architecture Topology

```
═══════════════════════════════════════════════════════════════════════════════
                  ENTERPRISE DATA PLATFORM CORE — TOPOLOGY
═══════════════════════════════════════════════════════════════════════════════

  EXTERNAL TRAFFIC
  HTTPS :443
       │
       ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  PUBLIC TIER (10.0.0.0/24, 10.0.1.0/24)                                      │
│  ┌───────────────┐   ┌───────────────┐                                       │
│  │  ALB / Nginx  │   │  NAT Gateway  │                                       │
│  │  Ingress      │   │  (per AZ)     │                                       │
│  └───────┬───────┘   └───────────────┘                                       │
└──────────┼───────────────────────────────────────────────────────────────────┘
           │ HTTP/HTTPS (SG: allow from ALB only)
           ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  APPLICATION TIER (10.0.10.0/24, 10.0.11.0/24)                               │
│                                                                              │
│  ┌─────────────────────┐  ┌──────────────────────┐  ┌───────────────────┐   │
│  │  multitenant-api    │  │  rag-engine           │  │  ai-agent-fleet   │   │
│  │  NestJS + Prisma    │  │  FastAPI + ChromaDB   │  │  LangGraph + Groq │   │
│  │  3 replicas         │  │  2 replicas           │  │  2 replicas       │   │
│  │  CPU: 250m→1000m    │  │  CPU: 500m→2000m      │  │  CPU: 500m→2000m  │   │
│  │  MEM: 256→512Mi     │  │  MEM: 1Gi→2Gi         │  │  MEM: 512→2Gi     │   │
│  │  HPA: 3→20 pods     │  │  HPA: 2→8 pods        │  │  HPA: 2→6 pods    │   │
│  └─────────┬───────────┘  └──────────┬───────────┘  └─────────┬─────────┘   │
│            │                         │                         │             │
│  ┌─────────────────────┐  ┌──────────────────────┐  ┌───────────────────┐   │
│  │  observability      │  │  secure-supply-chain  │  │  finops-anomaly   │   │
│  │  Prometheus+Grafana │  │  Security Scanner     │  │  Cost Analyzer    │   │
│  │  1 replica          │  │  1 replica (batch)    │  │  1 replica        │   │
│  └─────────────────────┘  └──────────────────────┘  └───────────────────┘   │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │ TCP (SG: allow from app tier only)
                                   ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  DATA TIER (10.0.20.0/24, 10.0.21.0/24)                                      │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  RDS PostgreSQL 16 — db.t3.medium → db.r6g.xlarge (auto-scale)      │   │
│  │  Multi-AZ standby (production) | Row-Level Security on 5 tables      │   │
│  │  Encrypted: KMS | Backup: 30 days | Performance Insights: enabled    │   │
│  │  Port 5432 — accessible ONLY from application security group         │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  MSK Kafka 3.6 — kafka.t3.small → kafka.m5.xlarge (3 brokers)       │   │
│  │  Topics: edp-agents, edp-orders, edp-audit, edp-metrics              │   │
│  │  Encrypted: TLS + KMS | IAM auth | Prometheus JMX export             │   │
│  │  Ports 9092/9094 — accessible ONLY from application security group   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │ TCP 6379 (SG: allow from app tier only)
                                   ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  CACHE TIER (10.0.30.0/24, 10.0.31.0/24)                                     │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  ElastiCache Redis 7 — cache.t3.micro → cache.r7g.large              │   │
│  │  3-node cluster (production) | maxmemory-policy: allkeys-lru         │   │
│  │  Encrypted: TLS + at-rest | Auto-failover: enabled                   │   │
│  │  Port 6379 — accessible ONLY from application security group         │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│  STORAGE (Cross-AZ, Encrypted)                                               │
│                                                                              │
│  S3: data-lake    (KMS, versioned, Glacier after 90d, WORM 7yr compliance)  │
│  S3: sbom-artifacts (versioned, SBOM from every CI/CD run)                  │
│  S3: audit-logs   (KMS, Object Lock COMPLIANCE mode, 7yr retention)         │
└──────────────────────────────────────────────────────────────────────────────┘

KUBERNETES HEALTH CHECK FLOW:
══════════════════════════════

  Pod startup
       │
       ▼ startupProbe (httpGet /health/live, 5s interval, 12 failures = 60s max)
  Container running
       │
       ▼ livenessProbe (httpGet /health/live, 20s interval, 3 failures = restart)
  Traffic eligible
       │
       ▼ readinessProbe (httpGet /health/ready, 10s interval, 3 failures = remove from LB)
  Receiving traffic
```

---

## 3. Component Inventory

| Project | Service Name | Replicas | CPU (req→limit) | Memory (req→limit) | HPA Range |
|---|---|---|---|---|---|
| Multi-Tenant SaaS | `multitenant-api` | 3 | 250m→1000m | 256Mi→512Mi | 3→20 |
| RAG Context Engine | `rag-engine` | 2 | 500m→2000m | 1Gi→2Gi | 2→8 |
| AI Agent Fleet | `ai-agent-fleet` | 2 | 500m→2000m | 512Mi→2Gi | 2→6 |
| Observability Stack | `observability-stack` | 1 | 200m→1000m | 384Mi→1.5Gi | 1→3 |
| Microservices Arch | `microservices-api` | 3 | 250m→500m | 256Mi→512Mi | 3→15 |
| RBAC Engine | `rbac-engine` | 2 | 250m→500m | 256Mi→512Mi | 2→10 |
| FinOps Engine | `finops-anomaly` | 1 | 100m→500m | 128Mi→256Mi | 1→4 |
| DR Pipeline | `dr-pipeline` | 1 | 100m→250m | 128Mi→256Mi | 1→2 |
| Secure Supply Chain | `supply-chain-scanner` | 1 | 500m→2000m | 512Mi→1Gi | 1→3 |
| Lead Navigator UI | `lead-navigator` | 2 | 100m→250m | 128Mi→256Mi | 2→8 |

---

## 4. Deployment Runbook

### Prerequisites

```bash
# Required tools
terraform --version   # >= 1.6.0
kubectl version       # >= 1.28.0
docker --version      # >= 24.0.0
python3 --version     # >= 3.11.0
```

### Step 1 — Start LocalStack (free AWS simulation)

```bash
pip install localstack
localstack start -d
localstack status services
```

### Step 2 — Provision infrastructure with Terraform

```bash
cd terraform/
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Expected outputs:
```
postgres_endpoint    = "localhost.localstack.cloud:5432"
redis_endpoint       = "localhost.localstack.cloud:6379"
kafka_bootstrap_brokers = "localhost.localstack.cloud:9092"
data_lake_bucket     = "edp-core-xxxx-data-lake"
ecs_cluster_name     = "edp-core-xxxx-cluster"
```

### Step 3 — Deploy to Kubernetes

```bash
# Create namespace and apply all manifests
kubectl apply -f kubernetes/deployment.yaml

# Verify deployments
kubectl get pods -n enterprise-platform
kubectl get hpa   -n enterprise-platform
kubectl get pdb   -n enterprise-platform

# Watch rollout
kubectl rollout status deployment/multitenant-api -n enterprise-platform
kubectl rollout status deployment/rag-engine       -n enterprise-platform
```

### Step 4 — Run data catalog extraction

```bash
cd catalog/
pip install psycopg2-binary rich
python build_catalog.py --format all

# Outputs:
ls output/
# data_catalog.json     ← machine-readable schema dictionary
# data_catalog.md       ← human-readable documentation
# quality_report.json   ← RLS, tenant isolation, index coverage scores
```

### Step 5 — Verify platform health

```bash
# Check all pods running
kubectl get pods -n enterprise-platform | grep -v Running

# Check HPA metrics
kubectl describe hpa -n enterprise-platform

# Check PDB status (ensure min available met)
kubectl describe pdb -n enterprise-platform

# Tail platform logs
kubectl logs -n enterprise-platform -l app.kubernetes.io/part-of=enterprise-platform --tail=50
```

### Step 6 — Run breach simulation (multi-tenant validation)

```bash
cd ../multitenant-saas/
node tests/tenant_test.js --verbose
# Expected: 24/24 tests passed, 0 breaches
```

---

## 5. Data Catalog Integration

The `catalog/build_catalog.py` script runs against any PostgreSQL instance and produces:

### JSON Catalog (`data_catalog.json`)
Machine-readable schema dictionary with full column types, constraints, RLS policies, row counts, and null percentages. Consumed by data governance tools, CI/CD pipelines, and documentation generators.

### Markdown Dictionary (`data_catalog.md`)
Human-readable table reference with column-level documentation. Auto-committed to the repository on every deployment via the CI/CD pipeline.

### Quality Report (`quality_report.json`)
Scores the database against three enterprise governance checks:
- **RLS Coverage** (35 points) — what % of tables have Row-Level Security enabled
- **Tenant Isolation** (30 points) — what % of tables have `tenant_id` isolation
- **Index Coverage** (35 points) — what % of tables have at least one index

A quality score below 70/100 fails the pipeline.

---

## 6. FinOps Cost Projection Matrix

### Development Environment (LocalStack — $0/month)

| Component | Instance | Monthly Cost |
|---|---|---|
| PostgreSQL (LocalStack) | Simulated | $0.00 |
| Redis (LocalStack) | Simulated | $0.00 |
| Kafka (LocalStack) | Simulated | $0.00 |
| ECS/Kubernetes (Docker) | Local | $0.00 |
| S3 (LocalStack) | Simulated | $0.00 |
| **TOTAL** | | **$0.00** |

### Staging Environment (AWS — Minimal Footprint)

| Component | Instance | Unit Cost | Monthly Estimate |
|---|---|---|---|
| RDS PostgreSQL | db.t3.medium (single-AZ) | $0.068/hr | $49.00 |
| ElastiCache Redis | cache.t3.micro (1 node) | $0.017/hr | $12.00 |
| MSK Kafka | kafka.t3.small (1 broker) | $0.072/hr | $52.00 |
| ECS Fargate Spot | 4 vCPU / 8GB avg | $0.013/vCPU-hr | $38.00 |
| S3 Storage | 50GB + requests | $0.023/GB | $8.00 |
| CloudWatch | Logs + metrics | per use | $12.00 |
| NAT Gateway | 1 AZ | $0.045/hr + $0.045/GB | $35.00 |
| ALB | 1 instance | $0.008/hr + LCU | $15.00 |
| **TOTAL STAGING** | | | **$221.00/month** |

### Production Environment (AWS — High Availability)

| Component | Instance | Config | Monthly Estimate |
|---|---|---|---|
| RDS PostgreSQL | db.r6g.large | Multi-AZ, 100GB gp3 | $290.00 |
| ElastiCache Redis | cache.r7g.medium | 3-node cluster | $185.00 |
| MSK Kafka | kafka.m5.large | 3 brokers, 300GB | $580.00 |
| ECS Fargate (base) | 8 vCPU reserved | 70% Fargate, 30% Spot | $210.00 |
| ECS Fargate Spot | Burst capacity | Auto-scaled | $65.00 |
| S3 Data Lake | 500GB + Glacier | Lifecycle to IA/Glacier | $28.00 |
| S3 Audit Logs | 100GB WORM | Object Lock | $12.00 |
| CloudWatch | Full metrics+logs | Dashboards + alarms | $45.00 |
| NAT Gateway | 2 AZ | HA pair | $95.00 |
| ALB | 2 instance | Cross-AZ | $35.00 |
| KMS | 1 key + API calls | Encryption | $8.00 |
| Secrets Manager | 5 secrets | Auto-rotation | $3.00 |
| **TOTAL PRODUCTION** | | | **$1,556.00/month** |

### FinOps Savings vs Naive Multi-Database Architecture

| Cost Driver | Naive (1 DB per tenant) | This Architecture | Monthly Saving |
|---|---|---|---|
| Database instances (100 tenants) | $6,800 (100x db.t3.small) | $290 (1x db.r6g.large) | **$6,510** |
| Backup storage (100 databases) | $1,200 | $45 | **$1,155** |
| DBA maintenance overhead | $4,000 (engineer time) | $200 (automation) | **$3,800** |
| Schema migration (100 deployments) | $2,500 (engineer time) | $0 (single migration) | **$2,500** |
| Monitoring (100 RDS instances) | $450 | $45 | **$405** |
| **TOTAL MONTHLY SAVING** | | | **$14,370** |
| **ANNUAL SAVING** | | | **$172,440** |

### Auto-Scaling Cost Efficiency

The Kubernetes HPA configuration prevents both under-provisioning (user-facing latency) and over-provisioning (wasted budget):

| Scenario | Without HPA | With HPA | Saving |
|---|---|---|---|
| Low traffic (2 AM) | 20 pods running | 3 pods running | 85% reduction |
| Peak traffic (9 AM) | 20 pods running | 12 pods running | 40% reduction |
| Burst traffic (sale event) | 20 pods (capped) | 20 pods (auto-scaled) | Zero latency cost |
| Monthly compute (est.) | $840 (fixed 20 pods) | $320 (avg 7 pods) | **$520/month** |

Scale-down stabilization window of 300 seconds prevents flapping — the cluster doesn't spin down during brief traffic dips, avoiding cold-start costs.

---

## 7. Operational Procedures

### Rolling Deployment (Zero Downtime)

```bash
# Update image tag and apply
kubectl set image deployment/multitenant-api \
  multitenant-api=randyrozario/multitenant-saas:v1.1.0 \
  -n enterprise-platform

# Monitor rollout
kubectl rollout status deployment/multitenant-api -n enterprise-platform

# Rollback if issues detected
kubectl rollout undo deployment/multitenant-api -n enterprise-platform
```

### Database Schema Migration

```bash
# Run migration inside the running pod (Prisma)
kubectl exec -n enterprise-platform \
  $(kubectl get pods -n enterprise-platform -l app=multitenant-api -o name | head -1) \
  -- npx prisma migrate deploy
```

### Catalog Refresh (post-deployment)

```bash
python catalog/build_catalog.py --format all --verify
```

### Force HPA Scale-Down (cost optimization outside business hours)

```bash
kubectl patch hpa multitenant-api-hpa -n enterprise-platform \
  -p '{"spec":{"minReplicas":1}}'
```

---

*Built with Terraform · Kubernetes · PostgreSQL RLS · MSK Kafka · ElastiCache Redis · LocalStack · Python*
