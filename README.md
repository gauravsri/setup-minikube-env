# Modular Minikube Environment Setup

A production-ready, modular Kubernetes environment template for Minikube with 8 containerized services. Optimized for Apple Silicon (M4) and designed for cross-project reusability.

[![Kubernetes](https://img.shields.io/badge/Kubernetes-Ready-326CE5?logo=kubernetes)](https://kubernetes.io/)
[![Minikube](https://img.shields.io/badge/Minikube-Optimized-orange)](https://minikube.sigs.k8s.io/)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M4_Optimized-000000?logo=apple)](https://www.apple.com/mac/)

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Available Services](#available-services)
- [Hardware Requirements](#hardware-requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [M4 Optimization Guide](#m4-optimization-guide)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)

## Features

### 🎯 **Project Wrapper Framework**
- **Minimal code**: Project scripts reduced to ~25 lines
- **Reusable functions**: Common utilities in `project-wrapper.sh`
- **Flexible service selection**: Choose services via `ENABLED_SERVICES`
- **Git submodule ready**: Version-controlled templates

### 🐳 **9 Production-Ready Services**
- **Database**: PostgreSQL (relational database)
- **Data Storage**: MinIO (S3), Dremio (SQL federation)
- **Processing**: Apache Spark (distributed computing)
- **Orchestration**: Apache Airflow (workflow management)
- **Streaming**: Redpanda (Kafka-compatible)
- **Search**: ZincSearch (full-text search)
- **Auth**: Dex (OIDC provider)
- **Email**: Postfix (SMTP relay)

### 🔧 **Kubernetes Native**
- Declarative YAML manifests
- Built-in health checks & readiness probes
- Resource limits & requests
- NodePort services for easy access
- Persistent volume support
- **100% feature parity** with setup-podman-env

## Quick Start

### 5-Minute Setup

```bash
# 1. Clone or add as submodule
git submodule add https://github.com/gauravsri/setup-minikube-env.git
cd setup-minikube-env

# 2. Start Minikube (M4 optimized)
minikube start --cpus=6 --memory=12288 --disk-size=40g

# 3. Deploy services
export NAMESPACE=demo
./k8s/scripts/minio.sh deploy
./k8s/scripts/spark.sh deploy

# 4. Check status
./k8s/scripts/minio.sh status
minikube service minio -n demo --url
```

### Generate Project Setup

```bash
# Create project-specific setup
./project-wrapper.sh generate my-project "My Description" ../my-project/scripts

# Configure and start
cd ../my-project/scripts
# Edit .env: ENABLED_SERVICES="minio,spark,airflow"
./setup-env.sh start
```

## Available Services

| Service | Description | Memory | Port(s) |
|---------|-------------|---------|---------|
| **PostgreSQL** | Relational database | ~2Gi | 5432 |
| **MinIO** | S3-compatible storage | ~1Gi | 9000, 9001 |
| **Dremio** | SQL federation engine | ~4Gi | 9999, 9047 |
| **Spark** | Distributed computing (master + workers + history) | ~8Gi | 8080, 7077, 18080 |
| **Airflow** | Workflow orchestration | ~5Gi | 8080 |
| **Redpanda** | Kafka streaming | ~3Gi | 9092, 9644 |
| **ZincSearch** | Search engine | ~1Gi | 4080 |
| **Dex** | OIDC authentication | ~256Mi | 5556 |
| **Postfix** | Email relay | ~256Mi | 25 |

### Service Commands

```bash
# Individual service management
./k8s/scripts/postgres.sh {deploy|remove|status|psql|create-db|backup}
./k8s/scripts/minio.sh {deploy|remove|status|logs|console}
./k8s/scripts/spark.sh {deploy|remove|scale|status|submit|ui|history-ui}
./k8s/scripts/airflow.sh {deploy|remove|status|cli|ui}
./k8s/scripts/dremio.sh {deploy|remove|status|ui}
./k8s/scripts/redpanda.sh {deploy|remove|status|topic|rpk}
./k8s/scripts/zincsearch.sh {deploy|remove|status|index|search}
./k8s/scripts/dex.sh {deploy|remove|status|test}
./k8s/scripts/postfix.sh {deploy|remove|status|test|queue}
```

## Hardware Requirements

### Minimum
- **CPU**: 2 cores
- **Memory**: 4 GB
- **Disk**: 20 GB
- **Services**: 1-2 (MinIO, ZincSearch)

### Recommended (Apple M4 - 16GB)
- **CPU**: 6 cores (60% of M4's 10 cores)
- **Memory**: 12 GB (75% of 16GB)
- **Disk**: 40 GB
- **Services**: 3-5 (minio,spark,airflow)

### High-End (32GB+ RAM)
- **CPU**: 8+ cores
- **Memory**: 16+ GB
- **Disk**: 60+ GB
- **Services**: All 8 services

## Installation

### Prerequisites

**macOS (M4 Optimized)**
```bash
brew install minikube kubectl
```

**Linux**
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl
```

**Windows**
```powershell
choco install minikube kubectl
```

### Docker Desktop (Apple Silicon)
```
Resources:
  CPUs: 6-8 cores
  Memory: 12-14 GB
  Disk: 60 GB+

Advanced:
  ✓ Use VirtioFS
  ✓ Enable Rosetta
```

## Usage

### Project-Level Commands

```bash
# Using project wrapper
./setup-env.sh start              # Deploy all enabled services
./setup-env.sh stop               # Remove all services
./setup-env.sh restart            # Restart all services
./setup-env.sh status             # Show status
./setup-env.sh logs [service]     # View logs
./setup-env.sh minikube status    # Minikube status
```

### Service Examples

**PostgreSQL (Database)**
```bash
./k8s/scripts/postgres.sh deploy
./k8s/scripts/postgres.sh psql                      # Open PostgreSQL CLI
./k8s/scripts/postgres.sh create-db myapp           # Create database
./k8s/scripts/postgres.sh create-user myuser pass123
./k8s/scripts/postgres.sh grant myapp myuser        # Grant privileges
./k8s/scripts/postgres.sh backup mydb backup.sql    # Backup database

# Access: postgres/postgres
# Connection: postgresql://postgres:postgres@<minikube-ip>:30432/postgres
```

**MinIO (S3 Storage)**
```bash
./k8s/scripts/minio.sh deploy
./k8s/scripts/minio.sh console    # Opens UI
# Access: minioadmin/minioadmin
```

**Spark (Processing)**
```bash
./k8s/scripts/spark.sh deploy
./k8s/scripts/spark.sh scale 3    # 3 workers
./k8s/scripts/spark.sh ui         # Opens Master UI (port 8080)
./k8s/scripts/spark.sh history-ui # Opens History Server UI (port 18080)

# Submit job with event logging enabled
kubectl exec -it spark-master-0 -- \
  /opt/bitnami/spark/bin/spark-submit \
  --master spark://spark-master:7077 \
  --conf spark.eventLog.enabled=true \
  --conf spark.eventLog.dir=s3a://spark-events/ \
  --class com.example.Main /app/job.jar

# Note: History Server displays completed applications from s3a://spark-events/
```

**Airflow (Orchestration)**
```bash
./k8s/scripts/airflow.sh deploy
./k8s/scripts/airflow.sh ui              # Opens UI (admin/admin)
./k8s/scripts/airflow.sh cli dags list   # List DAGs
```

**Redpanda (Streaming)**
```bash
./k8s/scripts/redpanda.sh deploy
./k8s/scripts/redpanda.sh topic create my-topic 3 1
./k8s/scripts/redpanda.sh produce my-topic
./k8s/scripts/redpanda.sh consume my-topic
```

## Configuration

### Environment Variables (.env)

```bash
# Project
PROJECT_NAME="my-project"
NAMESPACE="${PROJECT_NAME}"

# Service Selection (8 available)
ENABLED_SERVICES="minio,spark,airflow"

# Minikube (M4 Optimized)
MINIKUBE_CPUS="6"           # Use 6 of 10 M4 cores
MINIKUBE_MEMORY="12288"     # 12GB (leave 4GB for macOS)
MINIKUBE_DISK_SIZE="40g"

# Service Resources (examples)
SPARK_WORKER_REPLICAS="2"
SPARK_WORKER_MEMORY="2G"
SPARK_WORKER_CORES="2"
MINIO_STORAGE_SIZE="10Gi"
```

### Service Combinations

```bash
# Minimal Database (2Gi)
ENABLED_SERVICES="postgres"

# Database + Storage (3Gi)
ENABLED_SERVICES="postgres,minio"

# Basic Data Stack (9Gi)
ENABLED_SERVICES="minio,spark"

# SQL Federation (7Gi)
ENABLED_SERVICES="postgres,minio,dremio"

# Full Orchestration with standalone postgres (16Gi) - MAX for M4 16GB
ENABLED_SERVICES="postgres,minio,spark,airflow"

# Full Orchestration with embedded postgres (14Gi)
ENABLED_SERVICES="minio,spark,airflow"

# Streaming Platform (12Gi)
ENABLED_SERVICES="redpanda,spark,minio"

# All 9 Services (25Gi+) - Requires 32GB+ RAM
ENABLED_SERVICES="postgres,minio,dremio,spark,airflow,redpanda,zincsearch,dex,postfix"
```

## M4 Optimization Guide

### Hardware Specs
- **Chip**: Apple M4
- **Cores**: 10 (4 performance + 6 efficiency)
- **Memory**: 16 GB unified
- **Strategy**: Use 60-75% resources

### Optimized Settings

**Balanced (Recommended)**
```bash
minikube start --cpus=6 --memory=12288 --disk-size=40g
ENABLED_SERVICES="minio,spark,airflow"  # ~14Gi
```

**Conservative (1-3 services)**
```bash
minikube start --cpus=4 --memory=8192 --disk-size=20g
ENABLED_SERVICES="minio,spark"  # ~9Gi
```

**Aggressive (5-6 services)**
```bash
minikube start --cpus=8 --memory=14336 --disk-size=40g
ENABLED_SERVICES="minio,spark,airflow,redpanda,zincsearch"  # ~18Gi
# ⚠️ Monitor macOS memory pressure
```

### M4-Specific Optimizations

1. **Performance Cores** - Used by:
   - Dremio (SQL processing)
   - Spark Master (scheduling)
   - Airflow Scheduler

2. **Efficiency Cores** - Used by:
   - Background tasks (Redpanda replication)
   - Lightweight services (Dex, Postfix)

3. **Unified Memory Benefits**:
   - Faster inter-service communication
   - Better Spark shuffle performance
   - Reduced memory copying

4. **Spark Optimization**:
   ```bash
   # Fewer, larger workers (better for M4)
   SPARK_WORKER_REPLICAS="2"
   SPARK_WORKER_CORES="2"      # 2 cores per worker
   SPARK_WORKER_MEMORY="2G"

   # vs. Many small workers (less efficient)
   # SPARK_WORKER_REPLICAS="4"
   # SPARK_WORKER_CORES="1"
   ```

### Memory Planning (M4 - 16GB)

| Stack | Services | Memory | Minikube Config |
|-------|----------|--------|-----------------|
| Minimal | minio | ~1Gi | --cpus=2 --memory=4096 |
| Basic | minio,spark | ~9Gi | --cpus=4 --memory=10240 |
| SQL | minio,dremio | ~5Gi | --cpus=4 --memory=8192 |
| Streaming | redpanda,spark,minio | ~12Gi | --cpus=6 --memory=12288 |
| **Full** | minio,spark,airflow | ~14Gi | --cpus=6 --memory=14336 |
| ❌ All 8 | All services | ~23Gi | **NOT POSSIBLE** |

### Performance Monitoring

```bash
# Enable metrics
minikube addons enable metrics-server

# Check resources
kubectl top nodes
kubectl top pods -n <namespace>

# Monitor macOS memory
memory_pressure
# or Activity Monitor

# Signs of overcommitment:
# - kernel_task using >50% CPU
# - Swap >2GB
# - Apps unresponsive
```

## Project Structure

```
setup-minikube-env/
├── README.md                      # This file
├── project-wrapper.sh             # Project framework
├── setup-env.sh.example           # Example setup script
└── k8s/
    ├── manifests/                 # Kubernetes YAML
    │   ├── minio.yaml
    │   ├── dremio.yaml
    │   ├── spark.yaml
    │   ├── airflow.yaml
    │   ├── redpanda.yaml
    │   ├── zincsearch.yaml
    │   ├── dex.yaml
    │   └── postfix.yaml
    └── scripts/                   # Service management
        ├── .env.example           # Configuration template
        ├── common.sh              # Shared utilities
        ├── minio.sh
        ├── dremio.sh
        ├── spark.sh
        ├── airflow.sh
        ├── redpanda.sh
        ├── zincsearch.sh
        ├── dex.sh
        └── postfix.sh
```

## Troubleshooting

### Minikube Won't Start
```bash
# Check driver
minikube start --driver=docker

# Delete and recreate
minikube delete
minikube start --cpus=6 --memory=12288
```

### Pod Won't Start
```bash
# Check status
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>

# Check logs
./k8s/scripts/minio.sh logs 100

# Or directly
kubectl logs <pod-name> -n <namespace>
```

### Out of Memory (M4)
```bash
# Check usage
kubectl top nodes
kubectl top pods -n <namespace>

# Reduce services
ENABLED_SERVICES="minio,spark"  # instead of 5+ services

# Or reduce Minikube memory
minikube delete
minikube start --cpus=4 --memory=8192
```

### Service Not Accessible
```bash
# Get service URL
minikube service <service-name> -n <namespace> --url

# Or check NodePort
kubectl get svc -n <namespace>

# Get Minikube IP
minikube ip
```

### Slow Performance on M4
```bash
# Check if using ARM64 images
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'

# Enable Rosetta in Docker Desktop for x86 images

# Check thermal throttling
# Solution: Use laptop on hard surface, reduce CPU allocation
```

## Advanced Topics

### Multiple Minikube Profiles

```bash
# Create profiles for different workloads
minikube start -p data-eng --cpus=6 --memory=12288
minikube start -p analytics --cpus=4 --memory=8192
minikube start -p dev --cpus=2 --memory=4096

# Switch profiles
minikube profile data-eng
```

### Custom Resource Allocation

Edit your project's `.env`:
```bash
# Increase Spark resources
SPARK_WORKER_MEMORY="3G"
SPARK_WORKER_MEMORY_LIMIT="4Gi"
SPARK_WORKER_REPLICAS="3"

# Increase Dremio for heavy queries
DREMIO_MEMORY_LIMIT="6Gi"
DREMIO_CPU_LIMIT="4000m"
```

### Port Forwarding

```bash
# Direct access without NodePort
kubectl port-forward -n <namespace> service/minio 9000:9000
kubectl port-forward -n <namespace> service/spark-master 8080:8080
```

## Comparison with setup-podman-env

| Feature | setup-podman-env | setup-minikube-env |
|---------|------------------|-------------------|
| **Runtime** | Podman containers | Kubernetes (Minikube) |
| **Services** | 8 | 8 (100% parity) |
| **Orchestration** | Shell scripts | K8s manifests + scripts |
| **Scaling** | Manual | Declarative (`kubectl scale`) |
| **Health Checks** | Custom scripts | Built-in K8s probes |
| **Service Discovery** | Podman network | K8s Services/DNS |
| **Resource Usage** | Lower | Higher (K8s overhead) |
| **Production Path** | Needs orchestration | Direct to K8s |
| **Best For** | Quick dev, low resources | K8s learning, prod-like env |

## Contributing

1. Fork this repository
2. Create feature branch
3. Add service modules in `k8s/manifests/` and `k8s/scripts/`
4. Update `.env.example` with new configurations
5. Submit pull request

## License

MIT License

## Acknowledgments

- Inspired by [setup-podman-env](https://github.com/gauravsri/setup-podman-env)
- Optimized for Apple M4 MacBook Pro
- All 8 services ported from Podman to Kubernetes

---

**Quick Links:**
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
