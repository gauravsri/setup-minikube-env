#!/bin/bash
# Apache Spark management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="spark"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/spark.yaml"
NAMESPACE="${NAMESPACE:-default}"
MASTER_DEPLOYMENT="spark-master"
WORKER_DEPLOYMENT="spark-worker"

# Deploy Spark cluster
deploy() {
    print_header "Deploying Apache Spark Cluster"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    # Wait for master first
    print_info "Waiting for Spark Master to be ready..."
    wait_for_deployment "$MASTER_DEPLOYMENT" "$NAMESPACE" 180 || {
        print_error "Spark Master deployment failed"
        show_logs "app=spark,component=master" "$NAMESPACE" 50
        return 1
    }

    # Then wait for workers
    print_info "Waiting for Spark Workers to be ready..."
    wait_for_deployment "$WORKER_DEPLOYMENT" "$NAMESPACE" 180 || {
        print_error "Spark Worker deployment failed"
        show_logs "app=spark,component=worker" "$NAMESPACE" 50
        return 1
    }

    print_success "Spark cluster deployed successfully"
    show_status
}

# Remove Spark cluster
remove() {
    print_header "Removing Apache Spark Cluster"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "Spark cluster removed"
}

# Restart Spark cluster
restart() {
    print_header "Restarting Apache Spark Cluster"

    print_info "Restarting Spark Workers..."
    kubectl rollout restart deployment/"$WORKER_DEPLOYMENT" -n "$NAMESPACE"

    print_info "Restarting Spark Master..."
    kubectl rollout restart deployment/"$MASTER_DEPLOYMENT" -n "$NAMESPACE"

    wait_for_deployment "$MASTER_DEPLOYMENT" "$NAMESPACE" 180
    wait_for_deployment "$WORKER_DEPLOYMENT" "$NAMESPACE" 180

    print_success "Spark cluster restarted successfully"
}

# Scale Spark workers
scale_workers() {
    local replicas="${1:-2}"

    print_header "Scaling Spark Workers"

    print_info "Scaling workers to $replicas replicas..."
    kubectl scale deployment/"$WORKER_DEPLOYMENT" -n "$NAMESPACE" --replicas="$replicas" || {
        print_error "Failed to scale workers"
        return 1
    }

    wait_for_deployment "$WORKER_DEPLOYMENT" "$NAMESPACE" 180

    print_success "Spark workers scaled to $replicas"
    show_status
}

# Show Spark cluster status
show_status() {
    print_header "Apache Spark Cluster Status"

    if ! resource_exists deployment "$MASTER_DEPLOYMENT" "$NAMESPACE"; then
        print_warning "Spark cluster is not deployed"
        return 1
    fi

    echo
    print_info "Spark Master:"
    kubectl get deployment "$MASTER_DEPLOYMENT" -n "$NAMESPACE"
    get_pod_status "app=spark,component=master" "$NAMESPACE"

    echo
    print_info "Spark Workers:"
    kubectl get deployment "$WORKER_DEPLOYMENT" -n "$NAMESPACE"
    get_pod_status "app=spark,component=worker" "$NAMESPACE"

    echo
    print_info "Services:"
    kubectl get service -l "app=spark" -n "$NAMESPACE"

    echo
    print_info "Access URLs:"
    local minikube_ip=$(get_minikube_ip)
    local master_web_port=$(get_service_nodeport "spark-master" "$NAMESPACE" "web")
    local master_url_port=$(get_service_nodeport "spark-master" "$NAMESPACE" "master")

    if [ -n "$minikube_ip" ] && [ -n "$master_web_port" ]; then
        echo "  Master UI:  http://${minikube_ip}:${master_web_port}"
        echo "  Master URL: spark://${minikube_ip}:${master_url_port}"
        echo
        echo "  Submit job: kubectl exec -it <spark-master-pod> -n $NAMESPACE -- \\"
        echo "    /opt/bitnami/spark/bin/spark-submit \\"
        echo "    --master spark://spark-master:7077 \\"
        echo "    --class <main-class> <jar-file>"
    fi
}

# Show logs
show_logs() {
    local component="${1:-master}"
    local lines="${2:-50}"
    local follow="${3:-false}"

    print_header "Spark $component Logs"

    case "$component" in
        master)
            show_logs "app=spark,component=master" "$NAMESPACE" "$lines" "$follow"
            ;;
        worker)
            show_logs "app=spark,component=worker" "$NAMESPACE" "$lines" "$follow"
            ;;
        *)
            print_error "Unknown component: $component (use 'master' or 'worker')"
            return 1
            ;;
    esac
}

# Submit a Spark job
submit_job() {
    local jar_file="$1"
    local main_class="$2"
    shift 2
    local args="$@"

    if [ -z "$jar_file" ] || [ -z "$main_class" ]; then
        print_error "Usage: submit_job <jar-file> <main-class> [args...]"
        return 1
    fi

    local master_pod=$(kubectl get pods -l "app=spark,component=master" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$master_pod" ]; then
        print_error "Spark master pod not found"
        return 1
    fi

    print_info "Submitting Spark job to $master_pod..."

    kubectl exec -it "$master_pod" -n "$NAMESPACE" -- \
        /opt/bitnami/spark/bin/spark-submit \
        --master spark://spark-master:7077 \
        --class "$main_class" \
        "$jar_file" \
        $args
}

# Open Spark Master UI in browser
open_ui() {
    print_info "Opening Spark Master UI..."
    minikube service spark-master -n "$NAMESPACE" --url=false
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|scale|status|logs|submit|ui|help}"
    echo
    echo "Commands:"
    echo "  deploy           - Deploy Spark cluster to Kubernetes"
    echo "  remove           - Remove Spark cluster from Kubernetes"
    echo "  restart          - Restart Spark cluster"
    echo "  scale <replicas> - Scale Spark workers (default: 2)"
    echo "  status           - Show Spark cluster status and access URLs"
    echo "  logs <component> - Show logs [master|worker] [lines] [follow]"
    echo "  submit           - Submit Spark job <jar> <class> [args...]"
    echo "  ui               - Open Spark Master UI in browser"
    echo "  help             - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
    echo
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 scale 3"
    echo "  $0 logs master 100"
    echo "  $0 submit /path/to/app.jar com.example.Main arg1 arg2"
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
        restart)
            restart
            ;;
        scale)
            scale_workers "$2"
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "${2:-master}" "${3:-50}" "${4:-false}"
            ;;
        submit)
            shift
            submit_job "$@"
            ;;
        ui|web)
            open_ui
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
