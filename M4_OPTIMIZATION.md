# Apple M4 Optimization Guide

## Hardware Specifications

- **Chip**: Apple M4
- **CPU**: 10 cores (4 performance + 6 efficiency)
- **Memory**: 16 GB
- **Architecture**: ARM64 (Apple Silicon)

## Optimized Configuration

### Recommended Minikube Settings

```bash
# Balanced configuration (RECOMMENDED for 3-5 services)
minikube start \
  --cpus=6 \
  --memory=12288 \
  --disk-size=40g \
  --driver=docker

# Conservative (1-3 services)
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=20g \
  --driver=docker

# Aggressive (5-6 services) - Use with caution
minikube start \
  --cpus=8 \
  --memory=14336 \
  --disk-size=40g \
  --driver=docker
```

## Service Combinations for M4

### ✅ Recommended Stacks (Within 16GB limit)

#### Minimal Data Stack
```bash
ENABLED_SERVICES="minio"
# Memory: ~1Gi, CPU: ~1 core
```

#### Basic Processing
```bash
ENABLED_SERVICES="minio,spark"
# Memory: ~9Gi, CPU: ~5 cores
# Minikube: --cpus=6 --memory=10240
```

#### SQL Federation
```bash
ENABLED_SERVICES="minio,dremio"
# Memory: ~5Gi, CPU: ~4 cores
# Minikube: --cpus=4 --memory=8192
```

#### Streaming Platform
```bash
ENABLED_SERVICES="redpanda,spark,minio"
# Memory: ~12Gi, CPU: ~8 cores
# Minikube: --cpus=6 --memory=12288
```

#### Full Orchestration (Maximum recommended)
```bash
ENABLED_SERVICES="minio,spark,airflow"
# Memory: ~14Gi, CPU: ~8 cores
# Minikube: --cpus=6 --memory=14336
# ⚠️ Close to limit, monitor macOS memory pressure
```

### ⚠️ Not Recommended for 16GB M4

#### Complete Platform (Requires 32GB+ RAM)
```bash
ENABLED_SERVICES="minio,dremio,spark,airflow,redpanda,zincsearch,dex,postfix"
# Memory: ~23Gi+ (EXCEEDS 16GB)
# CPU: ~15 cores
# ❌ Will cause heavy swapping and poor performance
```

**Alternative**: Deploy in multiple Minikube clusters or use selective services.

## Resource Optimization Tips

### 1. Leverage M4 Performance Cores

The M4 has 4 high-performance cores that are excellent for:
- **Dremio**: SQL query processing benefits from fast cores
- **Spark Master**: Scheduling and coordination
- **Airflow Scheduler**: Task scheduling

Configuration:
```bash
# Allocate more CPU to compute-heavy services
DREMIO_CPU_LIMIT="3000m"      # 3 cores
SPARK_MASTER_CPU_LIMIT="2000m" # 2 cores
```

### 2. Optimize Spark Workers

Instead of many small workers, use fewer large workers:

```bash
# Optimized for M4
SPARK_WORKER_REPLICAS="2"
SPARK_WORKER_MEMORY="2G"
SPARK_WORKER_CORES="2"
SPARK_WORKER_CPU_LIMIT="2000m"

# vs. Default (less efficient on M4)
# SPARK_WORKER_REPLICAS="3"
# SPARK_WORKER_MEMORY="1G"
# SPARK_WORKER_CORES="1"
```

### 3. Memory Allocation Strategy

**Total Available**: 16GB
**Reserve for macOS**: 3-4GB
**Available for Minikube**: 12-13GB

```bash
# Service memory tiers for M4:
Tier 1 (Lightweight):  256Mi - 512Mi  (Dex, Postfix)
Tier 2 (Standard):     1Gi   - 2Gi    (MinIO, ZincSearch, Postgres)
Tier 3 (Memory-heavy): 2Gi   - 4Gi    (Dremio, Airflow, Redpanda)
Tier 4 (Compute):      2Gi   - 3Gi    (Spark workers)
```

### 4. Storage Optimization

The M4 MacBook Pro has fast SSD - take advantage:

```bash
# Increased storage allocations for M4
MINIO_STORAGE_SIZE="10Gi"      # was 5Gi
DREMIO_STORAGE_SIZE="20Gi"     # was 10Gi
POSTGRES_STORAGE_SIZE="5Gi"    # was 2Gi
REDPANDA_STORAGE_SIZE="10Gi"   # was 5Gi
ZINCSEARCH_STORAGE_SIZE="10Gi" # was 5Gi
```

### 5. Docker Desktop Settings

For optimal performance with M4:

```
Preferences > Resources:
  CPUs: 6-8 cores
  Memory: 12-14 GB
  Disk: 60GB+
  Swap: 2GB

Advanced:
  ✓ Use VirtioFS (faster file sharing)
  ✓ Enable Rosetta emulation (if needed for x86 images)
```

## Performance Monitoring

### Enable Metrics Server

```bash
minikube addons enable metrics-server

# Check resource usage
kubectl top nodes
kubectl top pods -n <namespace>
```

### Monitor macOS Memory Pressure

```bash
# Check memory pressure
memory_pressure

# Or use Activity Monitor
open -a "Activity Monitor"
```

### Signs of Overcommitment

- macOS kernel_task using >50% CPU
- Swap file usage >2GB
- Applications becoming unresponsive
- Increased fan noise/heat

**Solution**: Reduce Minikube memory or disable some services.

## Service-Specific M4 Optimizations

### Dremio
- Benefits significantly from M4 performance cores
- JVM heap size: `-Xms2g -Xmx4g`
- Can handle complex SQL queries efficiently

### Spark
- Use 2 workers with 2 cores each (not 4 workers with 1 core)
- M4's unified memory architecture helps with shuffle operations
- Enable dynamic allocation for variable workloads

### Airflow
- LocalExecutor is sufficient for M4
- Don't need CeleryExecutor for development
- 2Gi per component (webserver/scheduler) is optimal

### Redpanda
- Single-node cluster is fast enough on M4
- M4's efficiency cores handle background tasks well
- Consider `--overprovisioned` flag for better single-node performance

## Recommended Service Combinations by Use Case

### Data Engineering Workflow
```bash
ENABLED_SERVICES="minio,spark,airflow"
Memory: ~14Gi
# Perfect for ETL pipelines and data transformation
```

### Analytics & BI
```bash
ENABLED_SERVICES="minio,dremio,zincsearch"
Memory: ~6Gi
# Great for SQL analytics and search workloads
```

### Streaming Pipeline
```bash
ENABLED_SERVICES="redpanda,spark,minio"
Memory: ~12Gi
# Good for real-time data processing
```

### Development Stack
```bash
ENABLED_SERVICES="minio,dex,postfix"
Memory: ~2Gi
# Lightweight stack for app development
```

## Troubleshooting M4-Specific Issues

### Issue: Slow container startup

**Cause**: ARM64 architecture may require image pulling
**Solution**:
```bash
# Verify using ARM64 images
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'

# For x86 images, enable Rosetta in Docker Desktop
```

### Issue: Memory pressure/swapping

**Cause**: Too many services or over-allocated memory
**Solution**:
```bash
# Reduce Minikube memory
minikube delete
minikube start --cpus=4 --memory=8192

# Or reduce service count
ENABLED_SERVICES="minio,spark"  # instead of 5+ services
```

### Issue: CPU throttling

**Cause**: Thermal throttling on sustained workloads
**Solution**:
- Use laptop on hard surface (not bed/couch)
- Consider cooling pad
- Reduce CPU allocation: `--cpus=4` instead of `--cpus=8`

## Best Practices for M4

1. **Start Conservative**: Begin with 4 CPUs / 8GB, scale up as needed
2. **Monitor First**: Enable metrics-server before deploying all services
3. **Sequential Deployment**: Deploy services one at a time to check resource usage
4. **Use Profiles**: Create different Minikube profiles for different workloads
5. **Cleanup Regularly**: Stop unused services to free resources

```bash
# Create separate profiles for different workloads
minikube start -p data-eng --cpus=6 --memory=12288
minikube start -p analytics --cpus=4 --memory=8192
minikube start -p dev --cpus=2 --memory=4096

# Switch between profiles
minikube profile data-eng
minikube profile analytics
```

## Conclusion

The M4 MacBook Pro with 16GB RAM is **excellent** for running 3-5 Kubernetes services simultaneously. The performance cores handle compute-intensive workloads well, and the unified memory architecture provides good throughput.

**Sweet Spot**: 6 CPUs, 12GB RAM, 3-5 services
**Maximum**: 8 CPUs, 14GB RAM, 5-6 services (with monitoring)
**Not Recommended**: All 8 services (requires 32GB+ RAM)

For production-scale testing with all 8 services, consider:
- Cloud Kubernetes (GKE, EKS, AKS)
- Local machine with 32GB+ RAM
- Multiple Minikube instances
