#!/bin/bash
# MinIO management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="minio"
DEFAULT_MANIFEST_FILE="$SCRIPT_DIR/../manifests/minio.yaml"
NAMESPACE="${NAMESPACE:-default}"
DEPLOYMENT_NAME="minio"

# Deploy MinIO
deploy() {
    print_header "Deploying MinIO"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    # Resolve manifest path with project-specific override
    MANIFEST_FILE=$(resolve_manifest_path "$DEFAULT_MANIFEST_FILE" "$SERVICE_NAME")

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    wait_for_deployment "$DEPLOYMENT_NAME" "$NAMESPACE" 120 || {
        print_error "MinIO deployment failed"
        show_logs "app=minio" "$NAMESPACE" 50
        return 1
    }

    print_success "MinIO deployed successfully"
    show_status
}

# Remove MinIO
remove() {
    print_header "Removing MinIO"

    # Resolve manifest path with project-specific override
    MANIFEST_FILE=$(resolve_manifest_path "$DEFAULT_MANIFEST_FILE" "$SERVICE_NAME")

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "MinIO removed"
}

# Restart MinIO
restart() {
    print_header "Restarting MinIO"

    kubectl rollout restart deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" || {
        print_error "Failed to restart MinIO"
        return 1
    }

    wait_for_deployment "$DEPLOYMENT_NAME" "$NAMESPACE" 120

    print_success "MinIO restarted successfully"
}

# Health check for MinIO connectivity
health_check() {
    local timeout=5
    local result

    result=$(kubectl run -n "$NAMESPACE" minio-health-check --rm -i --restart=Never \
        --image=minio/mc --quiet \
        --command -- timeout "$timeout" mc alias set healthcheck \
        "http://minio.${NAMESPACE}.svc.cluster.local:9000" minioadmin minioadmin 2>&1)

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "✅ Healthy"
        return 0
    else
        echo "❌ Unhealthy"
        return 1
    fi
}

# Show MinIO status
show_status() {
    print_header "MinIO Status"

    if ! resource_exists deployment "$DEPLOYMENT_NAME" "$NAMESPACE"; then
        print_warning "MinIO is not deployed"
        return 1
    fi

    echo
    print_info "Deployment Status:"
    kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"

    echo
    print_info "Pods:"
    get_pod_status "app=minio" "$NAMESPACE"

    echo
    print_info "Service:"
    kubectl get service "$SERVICE_NAME" -n "$NAMESPACE"

    echo
    print_info "Health Check:"
    echo -n "  "
    health_check

    echo
    print_info "Access URLs:"
    local minikube_ip=$(get_minikube_ip)
    local api_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "api")
    local console_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "console")

    if [ -n "$minikube_ip" ] && [ -n "$api_port" ]; then
        echo "  API:     http://${minikube_ip}:${api_port}"
        echo "  Console: http://${minikube_ip}:${console_port}"
        echo "  Default credentials: minioadmin/minioadmin"
    fi
}

# Show MinIO logs
show_logs() {
    local lines="${1:-50}"
    local follow="${2:-false}"

    print_header "MinIO Logs"
    show_logs "app=minio" "$NAMESPACE" "$lines" "$follow"
}

# Open MinIO console in browser
open_console() {
    print_info "Opening MinIO console..."
    minikube service "$SERVICE_NAME" -n "$NAMESPACE" --url=false
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|status|logs|console|help}"
    echo
    echo "Commands:"
    echo "  deploy    - Deploy MinIO to Kubernetes"
    echo "  remove    - Remove MinIO from Kubernetes"
    echo "  restart   - Restart MinIO deployment"
    echo "  status    - Show MinIO status and access URLs"
    echo "  logs      - Show MinIO logs [lines] [follow]"
    echo "  console   - Open MinIO console in browser"
    echo "  help      - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
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
        status)
            show_status
            ;;
        logs)
            show_logs "${2:-50}" "${3:-false}"
            ;;
        console|ui)
            open_console
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
