#!/bin/bash
# Dremio management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="dremio"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/dremio.yaml"
NAMESPACE="${NAMESPACE:-default}"
DEPLOYMENT_NAME="dremio"

# Deploy Dremio
deploy() {
    print_header "Deploying Dremio"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    print_info "Waiting for Dremio to be ready (this may take 3-5 minutes)..."
    wait_for_deployment "$DEPLOYMENT_NAME" "$NAMESPACE" 600 || {
        print_error "Dremio deployment failed"
        show_logs "app=dremio" "$NAMESPACE" 50
        return 1
    }

    print_success "Dremio deployed successfully"
    show_status
}

# Remove Dremio
remove() {
    print_header "Removing Dremio"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "Dremio removed"
}

# Restart Dremio
restart() {
    print_header "Restarting Dremio"

    kubectl rollout restart deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" || {
        print_error "Failed to restart Dremio"
        return 1
    }

    wait_for_deployment "$DEPLOYMENT_NAME" "$NAMESPACE" 600

    print_success "Dremio restarted successfully"
}

# Show Dremio status
show_status() {
    print_header "Dremio Status"

    if ! resource_exists deployment "$DEPLOYMENT_NAME" "$NAMESPACE"; then
        print_warning "Dremio is not deployed"
        return 1
    fi

    echo
    print_info "Deployment Status:"
    kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"

    echo
    print_info "Pods:"
    get_pod_status "app=dremio" "$NAMESPACE"

    echo
    print_info "Service:"
    kubectl get service "$SERVICE_NAME" -n "$NAMESPACE"

    echo
    print_info "Access URLs:"
    local minikube_ip=$(get_minikube_ip)
    local web_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "web")
    local jdbc_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "jdbc")

    if [ -n "$minikube_ip" ] && [ -n "$web_port" ]; then
        echo "  Web UI:  http://${minikube_ip}:${web_port}"
        echo "  JDBC:    jdbc:dremio:direct=${minikube_ip}:${jdbc_port}"
        echo
        echo "  First-time setup: Create admin account on Web UI"
    fi
}

# Show Dremio logs
show_logs() {
    local lines="${1:-50}"
    local follow="${2:-false}"

    print_header "Dremio Logs"
    show_logs "app=dremio" "$NAMESPACE" "$lines" "$follow"
}

# Open Dremio UI in browser
open_ui() {
    print_info "Opening Dremio UI..."
    minikube service "$SERVICE_NAME" -n "$NAMESPACE" --url=false
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|status|logs|ui|help}"
    echo
    echo "Commands:"
    echo "  deploy    - Deploy Dremio to Kubernetes"
    echo "  remove    - Remove Dremio from Kubernetes"
    echo "  restart   - Restart Dremio deployment"
    echo "  status    - Show Dremio status and access URLs"
    echo "  logs      - Show Dremio logs [lines] [follow]"
    echo "  ui        - Open Dremio UI in browser"
    echo "  help      - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
    echo
    echo "Notes:"
    echo "  - First deployment takes 3-5 minutes to start"
    echo "  - Initial setup requires creating admin account via Web UI"
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
