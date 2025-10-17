#!/bin/bash
# Minikube Startup Script for M4 Max (48GB RAM, 16 cores)
# Optimized configuration with containerd runtime and essential addons

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - M4 Max Optimized
MINIKUBE_CPUS="${MINIKUBE_CPUS:-10}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-20480}"
MINIKUBE_DISK_SIZE="${MINIKUBE_DISK_SIZE:-100g}"
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-vfkit}"
MINIKUBE_RUNTIME="${MINIKUBE_RUNTIME:-containerd}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-v1.28.0}"
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"

# Addons to enable
ENABLE_ADDONS=(
    "metrics-server"
    "storage-provisioner"
    "default-storageclass"
)

# Optional addons (commented out by default)
# OPTIONAL_ADDONS=(
#     "dashboard"
#     "ingress"
#     "registry"
# )

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_info() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check if minikube is installed
    if ! command -v minikube &> /dev/null; then
        print_error "minikube is not installed"
        echo "Install with: brew install minikube"
        exit 1
    fi
    print_info "minikube found: $(minikube version --short)"

    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        print_warn "kubectl is not installed"
        echo "Install with: brew install kubectl"
        echo "You can use 'minikube kubectl' as alternative"
    else
        print_info "kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    fi

    # Check available resources
    local total_memory=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
    local total_cores=$(sysctl -n hw.ncpu)

    print_info "System resources: ${total_cores} cores, ${total_memory}GB RAM"

    if [ "$total_memory" -lt 16 ]; then
        print_warn "Low memory detected. Consider reducing MINIKUBE_MEMORY"
    fi

    echo ""
}

check_existing_cluster() {
    print_header "Checking Existing Cluster"

    if minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
        local current_status=$(minikube status -p "$MINIKUBE_PROFILE" -o json 2>/dev/null)
        if echo "$current_status" | grep -q '"Host":"Running"'; then
            print_warn "Cluster '$MINIKUBE_PROFILE' is already running"
            echo ""
            minikube profile list
            echo ""
            read -p "Do you want to delete and recreate? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_info "Deleting existing cluster..."
                minikube delete -p "$MINIKUBE_PROFILE"
            else
                print_info "Using existing cluster"
                return 1
            fi
        fi
    fi

    echo ""
    return 0
}

start_minikube() {
    print_header "Starting Minikube Cluster"

    echo "Configuration:"
    echo "  Profile:     $MINIKUBE_PROFILE"
    echo "  CPUs:        $MINIKUBE_CPUS cores"
    echo "  Memory:      $MINIKUBE_MEMORY MB ($(($MINIKUBE_MEMORY / 1024))GB)"
    echo "  Disk:        $MINIKUBE_DISK_SIZE"
    echo "  Driver:      $MINIKUBE_DRIVER"
    echo "  Runtime:     $MINIKUBE_RUNTIME"
    echo "  K8s Version: $KUBERNETES_VERSION"
    echo ""

    print_info "Starting cluster... (this may take 1-2 minutes)"

    minikube start \
        -p "$MINIKUBE_PROFILE" \
        --cpus="$MINIKUBE_CPUS" \
        --memory="$MINIKUBE_MEMORY" \
        --disk-size="$MINIKUBE_DISK_SIZE" \
        --driver="$MINIKUBE_DRIVER" \
        --container-runtime="$MINIKUBE_RUNTIME" \
        --kubernetes-version="$KUBERNETES_VERSION"

    print_info "Cluster started successfully"
    echo ""
}

enable_addons() {
    print_header "Enabling Addons"

    for addon in "${ENABLE_ADDONS[@]}"; do
        if minikube addons list -p "$MINIKUBE_PROFILE" | grep -q "$addon.*enabled"; then
            print_info "$addon already enabled"
        else
            print_info "Enabling $addon..."
            minikube addons enable "$addon" -p "$MINIKUBE_PROFILE"
        fi
    done

    echo ""
}

wait_for_cluster() {
    print_header "Waiting for Cluster to be Ready"

    print_info "Waiting for API server..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if kubectl get nodes &> /dev/null; then
            print_info "API server is ready"
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    if [ $attempt -eq $max_attempts ]; then
        print_error "Timeout waiting for API server"
        exit 1
    fi

    print_info "Waiting for system pods..."
    kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=120s

    print_info "Cluster is ready"
    echo ""
}

show_cluster_info() {
    print_header "Cluster Information"

    # Show profile list
    minikube profile list
    echo ""

    # Show node info
    echo "Nodes:"
    kubectl get nodes -o wide
    echo ""

    # Show system pods
    echo "System Pods:"
    kubectl get pods -n kube-system
    echo ""

    # Show enabled addons
    echo "Enabled Addons:"
    minikube addons list -p "$MINIKUBE_PROFILE" | grep enabled
    echo ""

    # Show cluster IP
    local cluster_ip=$(minikube ip -p "$MINIKUBE_PROFILE")
    print_info "Cluster IP: $cluster_ip"
    print_info "Dashboard:  minikube dashboard -p $MINIKUBE_PROFILE"
    print_info "SSH:        minikube ssh -p $MINIKUBE_PROFILE"

    echo ""
}

show_next_steps() {
    print_header "Next Steps"

    echo "Cluster is ready! Here's what you can do:"
    echo ""
    echo "1. Check resource usage:"
    echo "   kubectl top nodes"
    echo "   kubectl top pods --all-namespaces"
    echo ""
    echo "2. Deploy services:"
    echo "   export NAMESPACE=demo"
    echo "   ./k8s/scripts/minio.sh deploy"
    echo "   ./k8s/scripts/spark.sh deploy"
    echo ""
    echo "3. Access Kubernetes dashboard:"
    echo "   minikube dashboard"
    echo ""
    echo "4. View this script's configuration:"
    echo "   cat $0"
    echo ""
    echo "5. Stop cluster (preserves state):"
    echo "   minikube stop -p $MINIKUBE_PROFILE"
    echo ""
    echo "6. Delete cluster:"
    echo "   minikube delete -p $MINIKUBE_PROFILE"
    echo ""
}

main() {
    print_header "Minikube Cluster Startup"
    echo "M4 Max Optimized Configuration"
    echo ""

    check_prerequisites

    if check_existing_cluster; then
        start_minikube
        enable_addons
        wait_for_cluster
    fi

    show_cluster_info
    show_next_steps

    print_header "Startup Complete!"
}

# Run main function
main "$@"
