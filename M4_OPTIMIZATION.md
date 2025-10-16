# Apple M4 Max Optimization Guide

## Hardware Specifications

- **Chip**: Apple M4 Max
- **CPU**: 16 cores (12 performance + 4 efficiency)
- **Memory**: 48 GB
- **GPU**: 40 cores with Metal 4 support
- **Architecture**: ARM64 (Apple Silicon)

## Optimized Configuration

### Recommended Minikube Settings for M4 Max (48GB RAM, 16 cores)

```bash
# Conservative (1-5 services)
minikube start \
  --cpus=8 \
  --memory=16384 \
  --disk-size=60g \
  --driver=docker

# Balanced configuration (RECOMMENDED for 5-7 services)
minikube start \
  --cpus=12 \
  --memory=32768 \
  --disk-size=80g \
  --driver=docker

# Maximum (ALL 9 services) - Full power
minikube start \
  --cpus=14 \
  --memory=40960 \
  --disk-size=100g \
  --driver=docker
```

### Comparison with Base M4 (16GB RAM)

The M4 Max provides **3x more RAM** and **60% more CPU cores**, enabling:
- ✅ **All 9 services simultaneously** (not possible on base M4)
- ✅ **Larger worker pools** (4-6 Spark workers vs 2)
- ✅ **Higher resource limits** (4-8GB per service vs 2-4GB)
- ✅ **Production-like workloads** (realistic data volumes)

## Service Combinations for M4 Max

### ✅ ALL Stacks Supported (48GB RAM is plenty!)

#### Minimal Data Stack
```bash
ENABLED_SERVICES="minio"
# Memory: ~1Gi, CPU: ~1 core
# Minikube: --cpus=4 --memory=4096
```

#### Basic Processing
```bash
ENABLED_SERVICES="minio,spark"
# Memory: ~9Gi, CPU: ~5 cores
# Minikube: --cpus=8 --memory=12288
```

#### SQL Federation
```bash
ENABLED_SERVICES="postgres,minio,dremio"
# Memory: ~7Gi, CPU: ~5 cores
# Minikube: --cpus=8 --memory=10240
```

#### Streaming Platform
```bash
ENABLED_SERVICES="redpanda,spark,minio"
# Memory: ~12Gi, CPU: ~8 cores
# Minikube: --cpus=10 --memory=16384
```

#### Full Orchestration
```bash
ENABLED_SERVICES="postgres,minio,spark,airflow"
# Memory: ~16Gi, CPU: ~9 cores
# Minikube: --cpus=12 --memory=20480
```

#### Complete Platform (✅ NOW POSSIBLE on M4 Max!)
```bash
ENABLED_SERVICES="postgres,minio,dremio,spark,airflow,redpanda,zincsearch,dex,postfix"
# Memory: ~25-30Gi, CPU: ~16 cores
# Minikube: --cpus=14 --memory=40960 --disk-size=100g
# ✅ Runs comfortably with room to spare!
```

### 🚀 M4 Max Advantage

With 48GB RAM, you can:
- **Run all 9 services** with production-like resource allocations
- **Scale Spark workers** to 4-6 replicas (vs 2 on base M4)
- **Increase JVM heaps** for Dremio and Airflow
- **Test realistic workloads** without resource constraints
- **Still have 8GB+** free for macOS and other apps

## Resource Optimization Tips

### 1. Leverage M4 Max Performance Cores

The M4 Max has **12 high-performance cores** (vs 4 on base M4) - perfect for:
- **Dremio**: Complex SQL query processing and aggregations
- **Spark Master & Workers**: Distributed computing and data processing
- **Airflow Scheduler**: Parallel task execution
- **Redpanda**: High-throughput streaming

Configuration for M4 Max:
```bash
# Allocate significantly more CPU to compute-heavy services
DREMIO_CPU_LIMIT="6000m"        # 6 cores (vs 3 on M4)
SPARK_MASTER_CPU_LIMIT="3000m"  # 3 cores (vs 2 on M4)
SPARK_WORKER_CPU_LIMIT="4000m"  # 4 cores per worker (vs 2 on M4)
AIRFLOW_SCHEDULER_CPU_LIMIT="3000m"  # 3 cores (vs 2 on M4)
```

### 2. Optimize Spark Workers for M4 Max

With abundant resources, use more powerful workers:

```bash
# Optimized for M4 Max (48GB RAM)
SPARK_WORKER_REPLICAS="4"       # 4 workers (vs 2 on M4)
SPARK_WORKER_MEMORY="4G"        # 4GB per worker (vs 2G on M4)
SPARK_WORKER_CORES="3"          # 3 cores per worker (vs 2 on M4)
SPARK_WORKER_CPU_LIMIT="4000m"  # 4 core limit (vs 2 on M4)
SPARK_WORKER_MEMORY_LIMIT="6Gi" # 6GB limit (vs 3Gi on M4)

# This gives you:
# - 4 workers × 4GB = 16GB total worker memory
# - 4 workers × 3 cores = 12 total cores for parallel processing
# - Excellent for realistic Spark workloads
```

### 3. Memory Allocation Strategy for M4 Max

**Total Available**: 48GB
**Reserve for macOS**: 6-8GB
**Available for Minikube**: 40-42GB

```bash
# Service memory tiers for M4 Max (upgraded from M4):
Tier 1 (Lightweight):  256Mi - 512Mi  (Dex, Postfix) - unchanged
Tier 2 (Standard):     2Gi   - 4Gi    (MinIO, ZincSearch, Postgres) - 2x M4
Tier 3 (Memory-heavy): 4Gi   - 8Gi    (Dremio, Airflow, Redpanda) - 2x M4
Tier 4 (Compute):      4Gi   - 6Gi    (Spark workers) - 2x M4
```

### 4. Storage Optimization for M4 Max

With ample RAM and fast SSD, significantly increase storage allocations:

```bash
# M4 Max storage allocations (2-3x base M4)
MINIO_STORAGE_SIZE="30Gi"       # was 10Gi on M4, 5Gi on base
DREMIO_STORAGE_SIZE="50Gi"      # was 20Gi on M4, 10Gi on base
POSTGRES_STORAGE_SIZE="15Gi"    # was 5Gi on M4, 2Gi on base
REDPANDA_STORAGE_SIZE="30Gi"    # was 10Gi on M4, 5Gi on base
ZINCSEARCH_STORAGE_SIZE="20Gi"  # was 10Gi on M4, 5Gi on base
AIRFLOW_POSTGRES_STORAGE_SIZE="10Gi"  # was 5Gi

# Total: ~155Gi for all services (fits comfortably in 100Gi+ disk allocation)
```

### 5. Docker Desktop Settings for M4 Max

For optimal performance with 48GB RAM and 16 cores:

```
Preferences > Resources:
  CPUs: 12-14 cores  (vs 6-8 on M4)
  Memory: 32-40 GB   (vs 12-14 on M4)
  Disk: 100GB+       (vs 60GB on M4)
  Swap: 4GB          (vs 2GB on M4)

Advanced:
  ✓ Use VirtioFS (faster file sharing)
  ✓ Enable Rosetta emulation (if needed for x86 images)
  ✓ Enable host network sharing (for better performance)
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

## Service-Specific M4 Max Optimizations

### Dremio
- Benefits **massively** from M4 Max's 12 performance cores
- JVM heap size: `-Xms4g -Xmx8g` (vs 2-4g on M4)
- Can handle production-scale SQL queries and complex joins
- Perfect for realistic BI/analytics workloads

### Spark
- Use 4-6 workers with 3-4 cores each (vs 2 workers on M4)
- M4 Max's unified memory architecture + 48GB enables:
  - Larger shuffle buffers
  - More aggressive caching
  - Realistic dataset sizes (10GB+ datasets)
- Enable dynamic allocation: `spark.dynamicAllocation.enabled=true`

### Airflow
- LocalExecutor still recommended for development
- CeleryExecutor is viable if you want to test distributed execution
- 3-4Gi per component (webserver/scheduler) for production-like load
- Can run 10+ concurrent tasks comfortably

### Redpanda
- Single-node cluster with high partition counts
- M4 Max can handle 100+ partitions efficiently
- Use production-like replication settings (3 replicas)
- No need for `--overprovisioned` flag - plenty of resources

## Recommended Service Combinations by Use Case (M4 Max Optimized)

### Data Engineering Workflow (Enhanced)
```bash
ENABLED_SERVICES="postgres,minio,spark,airflow"
Memory: ~20Gi (vs ~14Gi on M4)
Minikube: --cpus=12 --memory=24576
# Production-scale ETL pipelines with persistent storage
```

### Analytics & BI Platform
```bash
ENABLED_SERVICES="postgres,minio,dremio,zincsearch"
Memory: ~12Gi
Minikube: --cpus=10 --memory=16384
# Full-featured analytics with SQL federation and search
```

### Streaming Platform (Complete)
```bash
ENABLED_SERVICES="postgres,redpanda,spark,minio,zincsearch"
Memory: ~18Gi
Minikube: --cpus=12 --memory=20480
# Production-like streaming with persistence and search
```

### Complete Data Platform (ALL SERVICES!)
```bash
ENABLED_SERVICES="postgres,minio,dremio,spark,airflow,redpanda,zincsearch,dex,postfix"
Memory: ~30Gi
Minikube: --cpus=14 --memory=40960 --disk-size=100g
# ✅ Finally possible! Full stack for realistic testing
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

## Best Practices for M4 Max

1. **Start Balanced**: Begin with 12 CPUs / 32GB for most workloads
2. **Monitor First**: Enable metrics-server before deploying all services
3. **Deploy All Services**: You can deploy all 9 services comfortably!
4. **Use Profiles**: Create different Minikube profiles for different workloads
5. **Cleanup Optional**: With 48GB, you can keep services running

```bash
# Create separate profiles for different workloads
minikube start -p full-stack --cpus=14 --memory=40960    # All services
minikube start -p data-eng --cpus=12 --memory=24576      # Data engineering
minikube start -p analytics --cpus=10 --memory=16384     # Analytics
minikube start -p dev --cpus=6 --memory=8192             # Development

# Switch between profiles
minikube profile full-stack
minikube profile data-eng
```

## Conclusion

The **M4 Max MacBook Pro with 48GB RAM** is **exceptional** for running Kubernetes development environments. With 16 cores (12 performance + 4 efficiency) and triple the RAM of the base M4, it handles production-like workloads with ease.

**Sweet Spot**: 12 CPUs, 32GB RAM, 5-7 services (balanced performance)
**Recommended**: 14 CPUs, 40GB RAM, **ALL 9 services** (full platform!)
**Advantage**: Can run complete data platform locally without compromises

### M4 Max vs Base M4 Summary

| Metric | Base M4 (16GB) | M4 Max (48GB) | Improvement |
|--------|----------------|---------------|-------------|
| CPU Cores | 10 (4P+6E) | 16 (12P+4E) | +60% cores, +200% P-cores |
| Memory | 16GB | 48GB | **+200%** |
| Max Services | 5-6 | **All 9** | Full platform |
| Spark Workers | 2 × 2GB | 4-6 × 4GB | **4x capacity** |
| Dremio JVM | 2-4GB | 4-8GB | **2x heap** |
| Minikube RAM | 12-14GB | 32-40GB | **2.5-3x** |

### When to Use M4 Max

✅ **Perfect for:**
- Full-stack data platform development
- Production-like workload testing
- Large Spark datasets (10GB+)
- Complex SQL queries in Dremio
- High-throughput streaming with Redpanda
- Running all services for integration testing

⚠️ **Overkill for:**
- Simple REST API development (use lightweight profiles)
- Single-service testing
- Learning Kubernetes basics

### Next Steps

1. **Start with full stack**: `minikube start --cpus=14 --memory=40960 --disk-size=100g`
2. **Deploy all services**: `ENABLED_SERVICES="postgres,minio,dremio,spark,airflow,redpanda,zincsearch,dex,postfix"`
3. **Enjoy** having a complete data platform on your laptop! 🚀
