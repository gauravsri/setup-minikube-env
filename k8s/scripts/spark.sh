#!/bin/bash
# Spark on Kubernetes management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="spark"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/spark.yaml"
NAMESPACE="${NAMESPACE:-default}"
PROJECT_PATH="${SPARK_PROJECT_PATH:-$(pwd)}"

# Deploy Spark on Kubernetes (RBAC + PVC)
deploy() {
    print_header "Deploying Spark on Kubernetes"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    # Apply manifest with dynamic PROJECT_PATH substitution
    print_info "Using project path: $PROJECT_PATH"

    # Create temporary manifest with substituted PROJECT_PATH
    local temp_manifest=$(mktemp)
    sed "s|path: /path/to/your/project|path: $PROJECT_PATH|g" "$MANIFEST_FILE" > "$temp_manifest"

    apply_manifest "$temp_manifest" "$NAMESPACE" || {
        rm -f "$temp_manifest"
        return 1
    }
    rm -f "$temp_manifest"

    # Wait for ServiceAccount
    print_info "Waiting for Spark ServiceAccount..."
    kubectl get serviceaccount spark -n "$NAMESPACE" &>/dev/null || {
        print_error "Spark ServiceAccount creation failed"
        return 1
    }

    # Wait for PVC to be bound
    print_info "Waiting for PVC to be bound..."
    local max_wait=60
    local count=0
    while [ $count -lt $max_wait ]; do
        local status=$(kubectl get pvc spark-project-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$status" == "Bound" ]; then
            print_success "PVC is bound"
            break
        fi
        count=$((count + 1))
        sleep 2
    done

    if [ $count -ge $max_wait ]; then
        print_warning "PVC not bound yet. You may need to start minikube mount:"
        echo
        echo "  minikube mount $PROJECT_PATH:$PROJECT_PATH --9p-version=9p2000.L --uid=1000 --gid=1000 &"
        echo
    fi

    print_success "Spark on Kubernetes deployed successfully"
    echo
    print_info "Components deployed:"
    echo "  ✓ ServiceAccount: spark"
    echo "  ✓ Role: spark-role"
    echo "  ✓ RoleBinding: spark-role-binding"
    echo "  ✓ PersistentVolume: spark-project-pv"
    echo "  ✓ PersistentVolumeClaim: spark-project-pvc"
    echo
    show_status
}

# Remove Spark RBAC and PVC
remove() {
    print_header "Removing Spark on Kubernetes"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "Spark resources removed"
}

# Show Spark on Kubernetes status
show_status() {
    print_header "Spark on Kubernetes Status"

    if ! resource_exists serviceaccount "spark" "$NAMESPACE"; then
        print_warning "Spark on Kubernetes is not deployed"
        return 1
    fi

    echo
    print_info "RBAC Resources:"
    kubectl get serviceaccount spark -n "$NAMESPACE" 2>/dev/null && echo "  ✓ ServiceAccount: spark"
    kubectl get role spark-role -n "$NAMESPACE" 2>/dev/null && echo "  ✓ Role: spark-role"
    kubectl get rolebinding spark-role-binding -n "$NAMESPACE" 2>/dev/null && echo "  ✓ RoleBinding: spark-role-binding"

    echo
    print_info "Storage Resources:"
    kubectl get pv spark-project-pv 2>/dev/null
    echo
    kubectl get pvc spark-project-pvc -n "$NAMESPACE" 2>/dev/null

    echo
    print_info "Dynamic Spark Pods (currently running):"
    local spark_pods=$(kubectl get pods -n "$NAMESPACE" -l spark-role=driver -o name 2>/dev/null)
    if [ -z "$spark_pods" ]; then
        echo "  (none - pods are created on-demand when jobs run)"
    else
        kubectl get pods -n "$NAMESPACE" -l spark-role=driver
    fi

    echo
    print_info "Usage:"
    echo "  See detailed examples in: $MANIFEST_FILE"
    echo
    echo "  Quick start:"
    echo "    # 1. Ensure minikube mount is active"
    echo "    minikube mount $PROJECT_PATH:$PROJECT_PATH --9p-version=9p2000.L --uid=1000 --gid=1000 &"
    echo
    echo "    # 2. Submit a Spark job"
    echo "    kubectl run spark-job --rm -i --tty --restart=Never \\"
    echo "      --namespace=$NAMESPACE \\"
    echo "      --serviceaccount=spark \\"
    echo "      --image=apache/spark:3.5.3 \\"
    echo "      -- /opt/spark/bin/spark-submit \\"
    echo "         --master k8s://https://kubernetes.default.svc \\"
    echo "         --deploy-mode cluster \\"
    echo "         --conf spark.kubernetes.namespace=$NAMESPACE \\"
    echo "         --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \\"
    echo "         local:///project/target/your-app.jar"
    echo
}

# Setup minikube mount
setup_mount() {
    local mount_path="${1:-$PROJECT_PATH}"

    print_header "Setting up Minikube Mount"

    # Check if mount is already active
    if ps aux | grep -q "[m]inikube mount $mount_path"; then
        print_success "Minikube mount already active for: $mount_path"
        return 0
    fi

    print_info "Starting minikube mount for: $mount_path"
    minikube mount "$mount_path:$mount_path" --9p-version=9p2000.L --uid=1000 --gid=1000 &
    local mount_pid=$!

    print_success "Minikube mount started (PID: $mount_pid)"
    print_info "Mount will remain active in background"

    # Wait a bit for mount to be ready
    sleep 3

    # Verify PVC binding
    print_info "Verifying PVC binding..."
    local count=0
    while [ $count -lt 30 ]; do
        local status=$(kubectl get pvc spark-project-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$status" == "Bound" ]; then
            print_success "PVC is now bound"
            return 0
        fi
        count=$((count + 1))
        sleep 2
    done

    print_warning "PVC not bound yet, but mount is running"
}

# Check mount status
check_mount() {
    print_header "Minikube Mount Status"

    local mount_process=$(ps aux | grep "[m]inikube mount")
    if [ -z "$mount_process" ]; then
        print_warning "No minikube mount process found"
        echo
        echo "Start mount with:"
        echo "  ./spark.sh mount [path]"
        return 1
    fi

    echo "$mount_process"
    echo
    print_success "Minikube mount is active"
}

# Show logs for Spark driver/executor pods
show_logs() {
    local pod_name="$1"
    local lines="${2:-50}"
    local follow="${3:-false}"

    print_header "Spark Pod Logs"

    if [ -z "$pod_name" ]; then
        # Find most recent driver pod
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l spark-role=driver --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null)

        if [ -z "$pod_name" ]; then
            print_error "No Spark driver pods found"
            echo
            echo "List all pods with:"
            echo "  kubectl get pods -n $NAMESPACE | grep spark"
            return 1
        fi

        print_info "Showing logs for most recent driver: $pod_name"
    fi

    if [ "$follow" == "true" ]; then
        kubectl logs -n "$NAMESPACE" "$pod_name" -f --tail="$lines"
    else
        kubectl logs -n "$NAMESPACE" "$pod_name" --tail="$lines"
    fi
}

# Submit example Spark job
submit_example() {
    print_header "Submitting Example Spark Job"

    cat <<'EOF'
kubectl run spark-example --rm -i --tty --restart=Never \
  --namespace=spark-tutorial \
  --serviceaccount=spark \
  --image=apache/spark:3.5.3 \
  -- /opt/spark/bin/spark-submit \
     --master k8s://https://kubernetes.default.svc \
     --deploy-mode cluster \
     --name SparkPiExample \
     --class org.apache.spark.examples.SparkPi \
     --conf spark.kubernetes.namespace=spark-tutorial \
     --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
     --conf spark.kubernetes.container.image=apache/spark:3.5.3 \
     --conf spark.executor.instances=2 \
     local:///opt/spark/examples/jars/spark-examples_2.12-3.5.3.jar 1000
EOF

    echo
    read -p "Run this example? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl run spark-example --rm -i --tty --restart=Never \
          --namespace="$NAMESPACE" \
          --serviceaccount=spark \
          --image=apache/spark:3.5.3 \
          -- /opt/spark/bin/spark-submit \
             --master k8s://https://kubernetes.default.svc \
             --deploy-mode cluster \
             --name SparkPiExample \
             --class org.apache.spark.examples.SparkPi \
             --conf spark.kubernetes.namespace="$NAMESPACE" \
             --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
             --conf spark.kubernetes.container.image=apache/spark:3.5.3 \
             --conf spark.executor.instances=2 \
             local:///opt/spark/examples/jars/spark-examples_2.12-3.5.3.jar 1000
    fi
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|status|mount|check-mount|logs|example|help}"
    echo
    echo "Commands:"
    echo "  deploy           - Deploy Spark on Kubernetes (RBAC + PVC)"
    echo "  remove           - Remove Spark resources from Kubernetes"
    echo "  status           - Show Spark on Kubernetes status"
    echo "  mount [path]     - Setup minikube mount (required for PV)"
    echo "  check-mount      - Check if minikube mount is active"
    echo "  logs [pod] [n]   - Show logs from Spark pod (default: most recent driver)"
    echo "  example          - Submit example SparkPi job"
    echo "  help             - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE           - Kubernetes namespace (default: default)"
    echo "  SPARK_PROJECT_PATH  - Project path to mount (default: current directory)"
    echo
    echo "Examples:"
    echo "  # Deploy Spark on Kubernetes"
    echo "  $0 deploy"
    echo
    echo "  # Setup mount for current project"
    echo "  export SPARK_PROJECT_PATH=/Users/username/my-project"
    echo "  $0 mount"
    echo
    echo "  # Check status"
    echo "  $0 status"
    echo
    echo "  # Run example job"
    echo "  $0 example"
    echo
    echo "  # View logs"
    echo "  $0 logs"
    echo "  $0 logs my-driver-pod 100"
    echo
    echo "Notes:"
    echo "  - Update PV path in manifests/spark.yaml before deployment"
    echo "  - Minikube mount must be active for PV access"
    echo "  - Pods are created dynamically when jobs run (no persistent cluster)"
}

# Main command handler
main() {
    case "${1:-status}" in
        deploy|start)
            deploy
            ;;
        remove|stop|delete)
            remove
            ;;
        status)
            show_status
            ;;
        mount|setup-mount)
            setup_mount "$2"
            ;;
        check-mount|mount-status)
            check_mount
            ;;
        logs)
            show_logs "${2}" "${3:-50}" "${4:-false}"
            ;;
        example|submit-example)
            submit_example
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
