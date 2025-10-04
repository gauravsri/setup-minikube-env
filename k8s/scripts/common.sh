#!/bin/bash
# Common utilities for Minikube Kubernetes environment management
# Provides shared functions for service deployment and management

# =============================================================================
# COLOR OUTPUT
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() {
    echo -e "${1}${2}${NC}"
}

print_header() {
    echo
    print_color "$BLUE" "=============================================="
    print_color "$BLUE" "$1"
    print_color "$BLUE" "=============================================="
}

print_success() {
    print_color "$GREEN" "✅ $1"
}

print_warning() {
    print_color "$YELLOW" "⚠️  $1"
}

print_error() {
    print_color "$RED" "❌ $1"
}

print_info() {
    print_color "$BLUE" "ℹ️  $1"
}

# =============================================================================
# MINIKUBE UTILITIES
# =============================================================================

# Check if minikube is running
is_minikube_running() {
    minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"
}

# Start minikube if not running
ensure_minikube_running() {
    if ! is_minikube_running; then
        print_warning "Minikube is not running. Starting minikube..."

        # Use environment variables or defaults
        local cpus="${MINIKUBE_CPUS:-4}"
        local memory="${MINIKUBE_MEMORY:-8192}"
        local disk="${MINIKUBE_DISK_SIZE:-40g}"
        local driver="${MINIKUBE_DRIVER:-}"

        print_info "Minikube configuration:"
        echo "  CPUs: $cpus"
        echo "  Memory: ${memory}MB"
        echo "  Disk: $disk"

        # Build minikube start command
        local start_cmd="minikube start --cpus=$cpus --memory=$memory --disk-size=$disk"
        if [ -n "$driver" ]; then
            start_cmd="$start_cmd --driver=$driver"
        fi

        print_info "Starting: $start_cmd"
        eval "$start_cmd" || {
            print_error "Failed to start minikube"
            return 1
        }
        print_success "Minikube started successfully"
    else
        print_info "Minikube is already running"
    fi
}

# Get minikube IP
get_minikube_ip() {
    minikube ip 2>/dev/null
}

# =============================================================================
# KUBERNETES UTILITIES
# =============================================================================

# Create namespace if it doesn't exist
create_namespace() {
    local namespace="${1:-default}"

    if kubectl get namespace "$namespace" >/dev/null 2>&1; then
        print_info "Namespace '$namespace' already exists"
    else
        print_info "Creating namespace '$namespace'..."
        kubectl create namespace "$namespace" || {
            print_error "Failed to create namespace '$namespace'"
            return 1
        }
        print_success "Namespace '$namespace' created"
    fi
}

# Wait for deployment to be ready
wait_for_deployment() {
    local deployment="$1"
    local namespace="${2:-default}"
    local timeout="${3:-300}"

    print_info "Waiting for deployment '$deployment' to be ready (timeout: ${timeout}s)..."

    if kubectl wait --for=condition=available \
        --timeout="${timeout}s" \
        deployment/"$deployment" \
        -n "$namespace" >/dev/null 2>&1; then
        print_success "Deployment '$deployment' is ready"
        return 0
    else
        print_error "Deployment '$deployment' failed to become ready within ${timeout}s"
        return 1
    fi
}

# Wait for statefulset to be ready
wait_for_statefulset() {
    local statefulset="$1"
    local namespace="${2:-default}"
    local replicas="${3:-1}"
    local timeout="${4:-300}"

    print_info "Waiting for statefulset '$statefulset' to be ready (timeout: ${timeout}s)..."

    local end_time=$((SECONDS + timeout))
    while [ $SECONDS -lt $end_time ]; do
        local ready=$(kubectl get statefulset "$statefulset" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        if [ "$ready" = "$replicas" ]; then
            print_success "StatefulSet '$statefulset' is ready"
            return 0
        fi
        sleep 5
    done

    print_error "StatefulSet '$statefulset' failed to become ready within ${timeout}s"
    return 1
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-default}"

    kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1
}

# Get pod status
get_pod_status() {
    local label="$1"
    local namespace="${2:-default}"

    kubectl get pods -l "$label" -n "$namespace" -o wide 2>/dev/null
}

# Get service URL
get_service_url() {
    local service="$1"
    local namespace="${2:-default}"

    minikube service "$service" -n "$namespace" --url 2>/dev/null
}

# Get NodePort for service
get_service_nodeport() {
    local service="$1"
    local namespace="${2:-default}"
    local port_name="${3:-http}"

    kubectl get service "$service" -n "$namespace" \
        -o jsonpath="{.spec.ports[?(@.name=='$port_name')].nodePort}" 2>/dev/null
}

# Get service external URL
get_service_external_url() {
    local service="$1"
    local namespace="${2:-default}"
    local port_name="${3:-http}"

    local nodeport=$(get_service_nodeport "$service" "$namespace" "$port_name")
    local minikube_ip=$(get_minikube_ip)

    if [ -n "$nodeport" ] && [ -n "$minikube_ip" ]; then
        echo "http://${minikube_ip}:${nodeport}"
    fi
}

# =============================================================================
# DEPLOYMENT MANAGEMENT
# =============================================================================

# Resolve manifest file path with project-specific overrides
# Usage: resolve_manifest_path <default_manifest_path> <service_name>
# Returns: Path to manifest file (project-specific if exists, otherwise template default)
resolve_manifest_path() {
    local default_manifest="$1"
    local service_name="$2"

    # If PROJECT_MANIFESTS_DIR is set, check for project-specific manifest
    if [[ -n "$PROJECT_MANIFESTS_DIR" && -n "$PROJECT_ROOT" ]]; then
        local project_manifest_dir

        if [[ "$PROJECT_MANIFESTS_DIR" =~ ^/ ]]; then
            # Absolute path
            project_manifest_dir="$PROJECT_MANIFESTS_DIR"
        else
            # Relative path - resolve from project's scripts directory (PROJECT_ROOT/scripts)
            # This allows paths like "../k8s/manifests" to work correctly
            project_manifest_dir="$(cd "$PROJECT_ROOT/scripts/$PROJECT_MANIFESTS_DIR" 2>/dev/null && pwd)"
        fi

        # Check if project-specific manifest exists
        if [[ -n "$project_manifest_dir" && -f "$project_manifest_dir/${service_name}.yaml" ]]; then
            echo "$project_manifest_dir/${service_name}.yaml"
            return 0
        fi
    fi

    # Fall back to default template manifest
    echo "$default_manifest"
}

# Apply Kubernetes manifest
apply_manifest() {
    local manifest_file="$1"
    local namespace="${2:-default}"

    if [ ! -f "$manifest_file" ]; then
        print_error "Manifest file not found: $manifest_file"
        return 1
    fi

    print_info "Applying manifest: $manifest_file"
    kubectl apply -f "$manifest_file" -n "$namespace" || {
        print_error "Failed to apply manifest: $manifest_file"
        return 1
    }
    print_success "Manifest applied successfully"
}

# Delete Kubernetes manifest
delete_manifest() {
    local manifest_file="$1"
    local namespace="${2:-default}"

    if [ ! -f "$manifest_file" ]; then
        print_warning "Manifest file not found: $manifest_file"
        return 0
    fi

    print_info "Deleting resources from manifest: $manifest_file"
    kubectl delete -f "$manifest_file" -n "$namespace" --ignore-not-found=true || {
        print_warning "Some resources may not have been deleted"
    }
    print_success "Resources deleted"
}

# =============================================================================
# PERSISTENT VOLUME MANAGEMENT
# =============================================================================

# Create persistent volume
create_pv() {
    local pv_name="$1"
    local size="${2:-1Gi}"
    local storage_class="${3:-standard}"

    if resource_exists pv "$pv_name" ""; then
        print_info "PersistentVolume '$pv_name' already exists"
        return 0
    fi

    print_info "Creating PersistentVolume '$pv_name' (${size})..."

    cat <<EOF | kubectl apply -f - || return 1
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $pv_name
spec:
  capacity:
    storage: $size
  accessModes:
    - ReadWriteOnce
  storageClassName: $storage_class
  hostPath:
    path: /data/$pv_name
EOF

    print_success "PersistentVolume '$pv_name' created"
}

# =============================================================================
# LOG MANAGEMENT
# =============================================================================

# Show logs for a deployment
show_logs() {
    local label="$1"
    local namespace="${2:-default}"
    local lines="${3:-50}"
    local follow="${4:-false}"

    print_info "Fetching logs for label: $label"

    local pod=$(kubectl get pods -l "$label" -n "$namespace" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$pod" ]; then
        print_error "No pods found with label: $label"
        return 1
    fi

    if [ "$follow" = "true" ]; then
        kubectl logs -f "$pod" -n "$namespace" --tail="$lines"
    else
        kubectl logs "$pod" -n "$namespace" --tail="$lines"
    fi
}

# =============================================================================
# HEALTH CHECK UTILITIES
# =============================================================================

# Check if service is healthy
check_service_health() {
    local service="$1"
    local namespace="${2:-default}"
    local endpoint="${3:-/health}"

    local url=$(get_service_external_url "$service" "$namespace")

    if [ -z "$url" ]; then
        print_warning "Could not determine service URL for $service"
        return 1
    fi

    if curl -sf "${url}${endpoint}" >/dev/null 2>&1; then
        print_success "Service '$service' is healthy"
        return 0
    else
        print_warning "Service '$service' health check failed"
        return 1
    fi
}

# =============================================================================
# VALIDATION UTILITIES
# =============================================================================

# Validate required tools
validate_tools() {
    local missing_tools=()

    if ! command -v minikube &> /dev/null; then
        missing_tools+=("minikube")
    fi

    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again."
        echo
        echo "Installation instructions:"
        echo "  - minikube: https://minikube.sigs.k8s.io/docs/start/"
        echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "  - curl: Usually pre-installed or available via package manager"
        return 1
    fi

    print_success "All required tools are installed"
}

# =============================================================================
# CLEANUP UTILITIES
# =============================================================================

# Clean up failed pods
cleanup_failed_pods() {
    local namespace="${1:-default}"

    print_info "Cleaning up failed pods in namespace '$namespace'..."

    kubectl delete pods --field-selector status.phase=Failed -n "$namespace" 2>/dev/null || true
    kubectl delete pods --field-selector status.phase=Unknown -n "$namespace" 2>/dev/null || true

    print_success "Cleanup completed"
}

# Port forward to service
port_forward() {
    local service="$1"
    local local_port="$2"
    local remote_port="$3"
    local namespace="${4:-default}"

    print_info "Port forwarding: localhost:$local_port -> $service:$remote_port"
    kubectl port-forward -n "$namespace" "service/$service" "$local_port:$remote_port"
}

# Export functions if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f print_color print_header print_success print_warning print_error print_info
    export -f is_minikube_running ensure_minikube_running get_minikube_ip
    export -f create_namespace wait_for_deployment wait_for_statefulset resource_exists
    export -f get_pod_status get_service_url get_service_nodeport get_service_external_url
    export -f resolve_manifest_path apply_manifest delete_manifest show_logs
    export -f check_service_health validate_tools cleanup_failed_pods port_forward
fi
