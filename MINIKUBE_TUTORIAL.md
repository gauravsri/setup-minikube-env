# Minikube Tutorial for Beginners

A comprehensive guide to understanding and using Minikube, from basics to advanced usage.

## Table of Contents

- [What is Minikube?](#what-is-minikube)
- [Core Concepts](#core-concepts)
- [Installation](#installation)
- [Getting Started](#getting-started)
- [Basic Operations](#basic-operations)
- [Working with Services](#working-with-services)
- [Resource Management](#resource-management)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)
- [Best Practices](#best-practices)

## What is Minikube?

**Minikube** is a tool that runs a single-node Kubernetes cluster on your local machine. It's designed for:

- **Learning Kubernetes** - Practice K8s without cloud costs
- **Local Development** - Test applications before deploying to production
- **CI/CD Testing** - Automated testing in isolated environments

### Why Minikube?

| Feature | Benefit |
|---------|---------|
| **Local** | No cloud costs, works offline |
| **Fast** | Quick cluster creation/deletion |
| **Isolated** | Won't affect production systems |
| **Production-like** | Real Kubernetes, not a simulation |
| **Multi-driver** | Works on Mac, Linux, Windows |

## Core Concepts

### 1. Kubernetes Cluster

A **cluster** is a set of machines (nodes) that run containerized applications. Minikube creates a single-node cluster on your laptop.

```
┌─────────────────────────────────────┐
│  Minikube Cluster (Your Laptop)    │
│  ┌───────────────────────────────┐  │
│  │  Node (VM or Container)       │  │
│  │  ├─ Kubernetes Control Plane  │  │
│  │  ├─ Container Runtime         │  │
│  │  └─ Your Applications (Pods)  │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### 2. Drivers

A **driver** is the virtualization technology Minikube uses to create the cluster:

| Driver | Platform | Description |
|--------|----------|-------------|
| **vfkit** | macOS (M-series) | Native Apple virtualization - **Recommended** |
| **docker** | All platforms | Uses Docker containers |
| **hyperkit** | macOS (Intel) | macOS native hypervisor |
| **kvm2** | Linux | KVM virtualization |
| **hyperv** | Windows | Windows native hypervisor |

**For M4 Max**: Use `vfkit` - it's optimized for Apple Silicon and doesn't require Docker Desktop.

### 3. Container Runtime

The **container runtime** runs your containers inside the cluster:

- **containerd** - Lightweight, industry standard (recommended)
- **docker** - Traditional Docker runtime
- **cri-o** - Kubernetes-native runtime

### 4. Kubernetes Resources

- **Pod** - Smallest unit, contains one or more containers
- **Deployment** - Manages replicas of your application
- **Service** - Network access to your pods
- **Namespace** - Logical separation of resources
- **PersistentVolume** - Storage that persists beyond pod lifecycle

## Installation

### macOS (Apple Silicon)

```bash
# Install via Homebrew
brew install minikube kubectl

# Verify installation
minikube version
kubectl version --client
```

### macOS (Intel)

```bash
brew install minikube kubectl
```

### Linux

```bash
# Download Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Download kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl
```

### Windows

```powershell
# Using Chocolatey
choco install minikube kubectl

# Or using Scoop
scoop install minikube kubectl
```

## Getting Started

### 1. Start Your First Cluster

**Basic Start (Minimal Resources)**
```bash
minikube start
# Uses default: 2 CPUs, 2GB RAM, 20GB disk
```

**Recommended Start (M4 Max - 48GB RAM)**
```bash
minikube start \
  --cpus=10 \
  --memory=20480 \
  --disk-size=100g \
  --driver=vfkit \
  --container-runtime=containerd
```

**What's Happening?**
1. Downloads Kubernetes ISO (~200MB, first time only)
2. Creates a virtual machine
3. Installs Kubernetes components
4. Configures kubectl to connect to the cluster

### 2. Verify Cluster is Running

```bash
# Check cluster status
minikube status

# Expected output:
# minikube
# type: Control Plane
# host: Running
# kubelet: Running
# apiserver: Running
# kubeconfig: Configured
```

### 3. Access the Kubernetes Dashboard

```bash
# Enable dashboard addon
minikube addons enable metrics-server
minikube dashboard

# Opens browser with Kubernetes web UI
```

### 4. Your First Application

```bash
# Create a deployment (runs nginx web server)
kubectl create deployment hello-nginx --image=nginx

# Expose it as a service
kubectl expose deployment hello-nginx --type=NodePort --port=80

# Access the service
minikube service hello-nginx --url
# Opens browser or shows URL: http://192.168.64.2:30123
```

## Basic Operations

### Starting and Stopping

```bash
# Start cluster
minikube start

# Stop cluster (preserves state)
minikube stop

# Delete cluster (removes everything)
minikube delete

# Pause cluster (saves resources)
minikube pause

# Resume paused cluster
minikube unpause
```

### Checking Status

```bash
# Overall status
minikube status

# Cluster information
kubectl cluster-info

# Node information
kubectl get nodes

# View all resources
kubectl get all --all-namespaces
```

### Accessing Logs

```bash
# Minikube logs
minikube logs

# Follow logs in real-time
minikube logs -f

# Last 50 lines
minikube logs --length=50

# Application logs
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # Follow
```

### SSH into Minikube

```bash
# SSH into the cluster node
minikube ssh

# Once inside:
$ docker ps          # See running containers (if using docker runtime)
$ df -h              # Check disk usage
$ free -h            # Check memory usage
$ exit               # Exit SSH session
```

## Working with Services

### Service Types

1. **ClusterIP** (default) - Internal cluster access only
2. **NodePort** - Accessible via Node IP:Port
3. **LoadBalancer** - External load balancer (works with minikube tunnel)

### Accessing Services

```bash
# Get service URL (NodePort services)
minikube service <service-name> --url

# Open service in browser
minikube service <service-name>

# List all service URLs
minikube service list
```

### Example: Deploy MinIO

```bash
# Create namespace
kubectl create namespace demo

# Deploy MinIO (from this project)
export NAMESPACE=demo
./k8s/scripts/minio.sh deploy

# Access MinIO console
minikube service minio-console -n demo
```

### Port Forwarding

```bash
# Forward local port to service
kubectl port-forward service/minio 9000:9000 -n demo

# Access at: http://localhost:9000
```

## Resource Management

### Viewing Resource Usage

```bash
# Enable metrics server
minikube addons enable metrics-server

# Wait 30 seconds for metrics to collect, then:

# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods --all-namespaces

# Sort by CPU
kubectl top pods --all-namespaces --sort-by=cpu

# Sort by memory
kubectl top pods --all-namespaces --sort-by=memory
```

### Resizing Your Cluster

```bash
# Stop current cluster
minikube stop

# Delete and recreate with new size
minikube delete
minikube start --cpus=12 --memory=32768 --disk-size=100g

# Note: This deletes all data! Back up important data first.
```

### Setting Resource Limits

When deploying applications, set resource requests and limits:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: nginx
    resources:
      requests:
        memory: "256Mi"
        cpu: "500m"
      limits:
        memory: "512Mi"
        cpu: "1000m"
```

## Troubleshooting

### Minikube Won't Start

```bash
# Check system resources
# Ensure you have enough RAM and disk space

# Try specifying driver explicitly
minikube start --driver=vfkit  # macOS M-series
minikube start --driver=docker  # Any platform with Docker

# Check logs
minikube logs

# Delete and start fresh
minikube delete --all --purge
minikube start
```

### Out of Memory

```bash
# Check usage
kubectl top nodes
kubectl top pods --all-namespaces

# Solutions:
# 1. Reduce number of running services
kubectl delete deployment <unused-deployment>

# 2. Increase Minikube memory
minikube stop
minikube delete
minikube start --memory=32768  # 32GB

# 3. Restart Minikube to clear caches
minikube stop && minikube start
```

### Pod Won't Start

```bash
# Check pod status
kubectl get pods -n <namespace>

# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# Common issues:
# - ImagePullBackOff: Can't download image
# - CrashLoopBackOff: Container keeps crashing
# - Pending: Not enough resources

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check previous crashed container logs
kubectl logs <pod-name> -n <namespace> --previous
```

### Service Not Accessible

```bash
# Verify service exists
kubectl get svc -n <namespace>

# Check endpoints
kubectl get endpoints <service-name> -n <namespace>

# Get Minikube IP
minikube ip

# Use minikube service command
minikube service <service-name> -n <namespace> --url
```

### Disk Full

```bash
# Check disk usage
minikube ssh "df -h"

# Clean up unused images
minikube ssh "docker system prune -a"

# Or increase disk size (requires recreating cluster)
minikube delete
minikube start --disk-size=150g
```

## Advanced Topics

### Multiple Profiles

Create separate clusters for different projects:

```bash
# Create profiles
minikube start -p dev --cpus=4 --memory=8192
minikube start -p prod-test --cpus=8 --memory=16384
minikube start -p experiments --cpus=2 --memory=4096

# List profiles
minikube profile list

# Switch profile
minikube profile dev

# Use specific profile
minikube status -p prod-test
kubectl get pods  # Uses active profile
```

### Addons

Extend Minikube with useful tools:

```bash
# List available addons
minikube addons list

# Enable useful addons
minikube addons enable metrics-server    # Resource metrics
minikube addons enable dashboard         # Web UI
minikube addons enable ingress           # Ingress controller
minikube addons enable registry          # Local Docker registry
minikube addons enable storage-provisioner  # Dynamic PVs

# Disable addon
minikube addons disable dashboard
```

### Custom Docker Images

Build and use local images:

```bash
# Point terminal to Minikube's Docker daemon
eval $(minikube docker-env)

# Build your image
docker build -t my-app:v1 .

# Use in Kubernetes (imagePullPolicy: Never or IfNotPresent)
kubectl run my-app --image=my-app:v1 --image-pull-policy=Never

# Reset to local Docker daemon
eval $(minikube docker-env -u)
```

### LoadBalancer Services

```bash
# Enable tunnel (required for LoadBalancer type)
minikube tunnel
# Keep this running in a separate terminal

# Now LoadBalancer services get external IPs
kubectl get svc
```

### Mounting Local Directories

```bash
# Mount host directory to cluster
minikube mount /Users/you/data:/mnt/data
# Keep running in separate terminal

# Or specify at start
minikube start --mount --mount-string="/Users/you/data:/data"
```

### Multi-Node Cluster

```bash
# Create cluster with worker nodes
minikube start --nodes=3 --cpus=8 --memory=16384

# Check nodes
kubectl get nodes

# NAME           STATUS   ROLES           AGE   VERSION
# minikube       Ready    control-plane   5m    v1.28.0
# minikube-m02   Ready    <none>          4m    v1.28.0
# minikube-m03   Ready    <none>          3m    v1.28.0
```

## Best Practices

### 1. Resource Allocation

**Don't allocate all your RAM/CPU to Minikube!**

| Total RAM | Allocate to Minikube | Leave for OS |
|-----------|---------------------|--------------|
| 8 GB | 4-6 GB | 2-4 GB |
| 16 GB | 8-12 GB | 4-8 GB |
| 32 GB | 16-24 GB | 8-16 GB |
| 48 GB | 20-32 GB | 16-28 GB |

### 2. Use Namespaces

Organize resources logically:

```bash
# Create namespace
kubectl create namespace my-project

# Deploy to namespace
kubectl apply -f deployment.yaml -n my-project

# Set default namespace
kubectl config set-context --current --namespace=my-project
```

### 3. Clean Up Regularly

```bash
# Delete unused resources
kubectl delete deployment <name>
kubectl delete service <name>

# Clean Docker images (inside Minikube)
minikube ssh "docker system prune -a"

# Stop when not in use
minikube stop  # Saves resources, preserves state
```

### 4. Version Management

```bash
# Use specific Kubernetes version
minikube start --kubernetes-version=v1.28.0

# List available versions
minikube config view kubernetes-version
```

### 5. Backup Important Data

```bash
# Backup persistent volumes before deleting cluster
kubectl get pv
kubectl get pvc --all-namespaces

# Export resources
kubectl get all -n <namespace> -o yaml > backup.yaml

# Restore
kubectl apply -f backup.yaml
```

### 6. Use containerd Runtime

```bash
# containerd is lighter and faster than docker runtime
minikube start --container-runtime=containerd
```

### 7. Monitor Resource Usage

```bash
# Enable metrics
minikube addons enable metrics-server

# Check regularly
kubectl top nodes
kubectl top pods --all-namespaces

# Use dashboard for visual monitoring
minikube dashboard
```

## Common Workflows

### Development Workflow

```bash
# 1. Start cluster
minikube start --cpus=6 --memory=12288

# 2. Create namespace for your project
kubectl create namespace myapp

# 3. Deploy your app
kubectl apply -f k8s/manifests/ -n myapp

# 4. Access services
minikube service myapp-frontend -n myapp

# 5. Make changes, rebuild, redeploy
kubectl rollout restart deployment/myapp -n myapp

# 6. View logs
kubectl logs -f deployment/myapp -n myapp

# 7. Stop when done
minikube stop
```

### Testing Workflow

```bash
# 1. Start fresh cluster
minikube delete && minikube start

# 2. Deploy full stack
./deploy-all.sh

# 3. Run tests
kubectl run test-runner --image=test:latest --restart=Never

# 4. Check results
kubectl logs test-runner

# 5. Cleanup
kubectl delete pod test-runner
minikube delete
```

## Useful Commands Reference

### Cluster Management
```bash
minikube start              # Start cluster
minikube stop               # Stop cluster
minikube delete             # Delete cluster
minikube status             # Show status
minikube pause              # Pause cluster
minikube unpause            # Resume cluster
minikube ip                 # Get cluster IP
minikube ssh                # SSH into node
```

### Service Access
```bash
minikube service <name>              # Open service in browser
minikube service <name> --url        # Get service URL
minikube service list                # List all services
minikube tunnel                      # Enable LoadBalancer
```

### Addons
```bash
minikube addons list                 # List addons
minikube addons enable <name>        # Enable addon
minikube addons disable <name>       # Disable addon
```

### Information
```bash
minikube version                     # Minikube version
minikube logs                        # Cluster logs
minikube profile list                # List profiles
minikube config view                 # View config
```

### kubectl Essentials
```bash
kubectl get pods                     # List pods
kubectl get svc                      # List services
kubectl get deployments              # List deployments
kubectl describe pod <name>          # Pod details
kubectl logs <pod-name>              # View logs
kubectl logs -f <pod-name>           # Follow logs
kubectl exec -it <pod> -- /bin/bash  # Shell into pod
kubectl delete pod <name>            # Delete pod
kubectl apply -f file.yaml           # Apply manifest
```

## Learning Path

### Beginner (Week 1-2)
1. Install Minikube and kubectl
2. Start your first cluster
3. Deploy nginx and access it
4. Learn kubectl basics: get, describe, logs
5. Use the Kubernetes dashboard

### Intermediate (Week 3-4)
1. Work with namespaces
2. Deploy multi-container applications
3. Use ConfigMaps and Secrets
4. Set up persistent storage
5. Understand Services (ClusterIP, NodePort, LoadBalancer)

### Advanced (Month 2)
1. Create multi-node clusters
2. Use Helm for package management
3. Set up Ingress controllers
4. Deploy StatefulSets
5. Configure resource limits and autoscaling

## Additional Resources

- **Official Docs**: https://minikube.sigs.k8s.io/docs/
- **Kubernetes Docs**: https://kubernetes.io/docs/home/
- **kubectl Cheat Sheet**: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
- **Interactive Tutorial**: https://kubernetes.io/docs/tutorials/kubernetes-basics/

## Quick Reference Card

```bash
# START
minikube start --cpus=10 --memory=20480 --driver=vfkit --container-runtime=containerd

# CHECK STATUS
minikube status
kubectl get all --all-namespaces

# DEPLOY APP
kubectl create deployment myapp --image=nginx
kubectl expose deployment myapp --type=NodePort --port=80
minikube service myapp --url

# VIEW LOGS
minikube logs
kubectl logs <pod-name> -f

# RESOURCE USAGE
kubectl top nodes
kubectl top pods --all-namespaces

# CLEANUP
kubectl delete deployment myapp
kubectl delete service myapp

# STOP
minikube stop

# DELETE
minikube delete
```

---

**Need help?** Run `minikube help` or `kubectl help` for command documentation.

**Ready to deploy services?** Return to the [main README](README.md) to deploy the full data platform!
