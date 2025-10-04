# Changelog

All notable changes to the setup-minikube-env template will be documented in this file.

## [Unreleased]

### Added
- **Automatic PROJECT_PATH substitution** in spark.sh deploy script
  - No longer requires manual editing of spark.yaml manifest
  - Uses SPARK_PROJECT_PATH environment variable (defaults to current directory)
  - Template manifest remains generic with placeholder path

### Changed - Spark on Kubernetes Migration (October 2024)

**BREAKING CHANGE**: Replaced standalone Spark cluster with Kubernetes-native dynamic pods.

#### What Changed:
- **Removed**: Standalone Spark master, worker, and history server deployments (~260 lines)
- **Added**: Spark on Kubernetes RBAC configuration (ServiceAccount, Role, RoleBinding)
- **Added**: PersistentVolume/PVC for JAR access via hostPath
- **Added**: Comprehensive usage instructions in `k8s/manifests/spark.yaml`

#### Migration Guide:

**Before (Standalone Spark):**
```yaml
# 4 deployments: spark-master, spark-worker, spark-history
# 3 services: spark-master, spark-worker, spark-history
# Memory: ~6-8Gi consumed 24/7
```

**After (Spark on Kubernetes):**
```yaml
# 1 ServiceAccount, 1 Role, 1 RoleBinding, 1 PV, 1 PVC
# 0 persistent pods (dynamic creation only)
# Memory: ~0Gi idle, ~3-4Gi during job execution
```

**Code Changes Required:**

1. **Update PersistentVolume path** in `k8s/manifests/spark.yaml`:
   ```yaml
   hostPath:
     path: /path/to/your/project  # UPDATE THIS
   ```

2. **Airflow DAGs**: Replace `SparkSubmitOperator` with `KubernetesPodOperator`:
   ```python
   # Before
   from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator

   spark_task = SparkSubmitOperator(
       task_id='spark_job',
       application='/path/to/app.jar',
       conn_id='spark_default'
   )

   # After
   from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator

   spark_task = KubernetesPodOperator(
       task_id='spark_job',
       name='spark-submitter',
       namespace='your-namespace',
       service_account_name='spark',
       image='apache/spark:3.5.3',
       cmds=['/bin/sh', '-c'],
       arguments=[
           '/opt/spark/bin/spark-submit '
           '--master k8s://https://kubernetes.default.svc '
           '--deploy-mode cluster '
           '--conf spark.kubernetes.namespace=your-namespace '
           '--conf spark.kubernetes.authenticate.driver.serviceAccountName=spark '
           'local:///project/target/app.jar'
       ]
   )
   ```

3. **Remove environment variables** (no longer needed):
   ```bash
   # DEPRECATED:
   # SPARK_WORKER_REPLICAS="2"
   # SPARK_WORKER_MEMORY="2G"
   # SPARK_WORKER_CORES="2"
   ```

4. **Update monitoring approach**:
   ```bash
   # Before: Access Spark Master UI
   minikube service spark-master -n namespace

   # After: Monitor dynamic pods
   kubectl get pods -n namespace | grep spark
   kubectl logs -n namespace <driver-pod-name> -f
   ```

#### Benefits:

- ✅ **Memory Savings**: ~6Gi freed (no idle cluster)
- ✅ **Kubernetes-Native**: RBAC-based permissions
- ✅ **Simpler Deployment**: Single manifest file
- ✅ **Dynamic Scaling**: Pods created only when needed
- ✅ **Better Integration**: Works seamlessly with K8s ecosystem

#### Prerequisites:

- **minikube mount** required for hostPath PV access (if using local JARs)
- **Kubernetes 1.24+** recommended
- **Update project-specific PV path** before deployment

#### Resources:

- [Apache Spark on Kubernetes Docs](https://spark.apache.org/docs/latest/running-on-kubernetes.html)
- [KubernetesPodOperator Guide](https://airflow.apache.org/docs/apache-airflow-providers-cncf-kubernetes/stable/operators.html)
- Template file: `k8s/manifests/spark.yaml` (includes detailed usage examples)

---

## [1.0.0] - 2024-09-01

### Added
- Initial release with 9 containerized services
- Project wrapper framework for reusability
- M4 Apple Silicon optimization guide
- Modular service selection via ENABLED_SERVICES
