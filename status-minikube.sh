#!/bin/bash
# Minikube Status Script
# Shows comprehensive status of the cluster and resource usage

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-minikube}"

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_info() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header "Minikube Cluster Status"

# Check if cluster exists
if ! minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
    print_error "Cluster '$MINIKUBE_PROFILE' not found"
    echo ""
    echo "To start: ./start-minikube.sh"
    exit 1
fi

# Show profile list
echo "Profiles:"
minikube profile list
echo ""

# Show detailed status
echo "Cluster Status:"
minikube status -p "$MINIKUBE_PROFILE"
echo ""

# Check if cluster is running
if ! kubectl get nodes &> /dev/null; then
    print_error "Cluster is not accessible"
    echo "Try: minikube start -p $MINIKUBE_PROFILE"
    exit 1
fi

# Show nodes
echo "Nodes:"
kubectl get nodes -o wide
echo ""

# Show resource usage if metrics-server is available
if kubectl get apiservices | grep -q metrics.k8s.io; then
    echo "Resource Usage:"
    echo ""
    echo "Nodes:"
    kubectl top nodes || print_error "Metrics not ready yet (wait 30 seconds)"
    echo ""

    echo "Top Pods by CPU:"
    kubectl top pods --all-namespaces --sort-by=cpu 2>/dev/null | head -10 || echo "No pods running"
    echo ""

    echo "Top Pods by Memory:"
    kubectl top pods --all-namespaces --sort-by=memory 2>/dev/null | head -10 || echo "No pods running"
    echo ""
fi

# Show pod count by namespace
echo "Pods by Namespace:"
kubectl get pods --all-namespaces --no-headers | awk '{print $1}' | sort | uniq -c | sort -rn
echo ""

# Show services
echo "Services:"
kubectl get svc --all-namespaces
echo ""

# Show cluster info
cluster_ip=$(minikube ip -p "$MINIKUBE_PROFILE" 2>/dev/null || echo "N/A")
echo "Cluster IP: $cluster_ip"
echo ""

# Show disk usage
echo "Disk Usage (inside cluster):"
minikube ssh -p "$MINIKUBE_PROFILE" "df -h /" 2>/dev/null || echo "N/A"
echo ""

# Show enabled addons
echo "Enabled Addons:"
minikube addons list -p "$MINIKUBE_PROFILE" | grep enabled
echo ""

print_header "Quick Commands"
echo "Dashboard:   minikube dashboard -p $MINIKUBE_PROFILE"
echo "SSH:         minikube ssh -p $MINIKUBE_PROFILE"
echo "Logs:        minikube logs -p $MINIKUBE_PROFILE"
echo "Stop:        ./stop-minikube.sh"
echo "Delete:      minikube delete -p $MINIKUBE_PROFILE"
echo ""
