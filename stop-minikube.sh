#!/bin/bash
# Minikube Stop Script
# Gracefully stops the Minikube cluster (preserves state)

set -e

# Colors
GREEN='\033[0;32m'
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

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_header "Stopping Minikube Cluster"

# Check if cluster is running
if ! minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
    print_warn "Cluster '$MINIKUBE_PROFILE' is not running"
    exit 0
fi

echo "Stopping cluster: $MINIKUBE_PROFILE"
echo ""

# Stop the cluster
minikube stop -p "$MINIKUBE_PROFILE"

print_info "Cluster stopped successfully"
echo ""
echo "To start again: ./start-minikube.sh"
echo "To delete:      minikube delete -p $MINIKUBE_PROFILE"
echo ""
