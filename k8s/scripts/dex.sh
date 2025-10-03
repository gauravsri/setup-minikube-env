#!/bin/bash
# Dex OIDC management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="dex"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/dex.yaml"
NAMESPACE="${NAMESPACE:-default}"
DEPLOYMENT_NAME="dex"

# Deploy Dex
deploy() {
    print_header "Deploying Dex OIDC Provider"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    wait_for_deployment "$DEPLOYMENT_NAME" "$NAMESPACE" 60 || {
        print_error "Dex deployment failed"
        show_logs "app=dex" "$NAMESPACE" 50
        return 1
    }

    print_success "Dex deployed successfully"
    show_status
}

# Remove Dex
remove() {
    print_header "Removing Dex"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "Dex removed"
}

# Restart Dex
restart() {
    print_header "Restarting Dex"

    kubectl rollout restart deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" || {
        print_error "Failed to restart Dex"
        return 1
    }

    wait_for_deployment "$DEPLOYMENT_NAME" "$NAMESPACE" 60

    print_success "Dex restarted successfully"
}

# Show Dex status
show_status() {
    print_header "Dex Status"

    if ! resource_exists deployment "$DEPLOYMENT_NAME" "$NAMESPACE"; then
        print_warning "Dex is not deployed"
        return 1
    fi

    echo
    print_info "Deployment Status:"
    kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"

    echo
    print_info "Pods:"
    get_pod_status "app=dex" "$NAMESPACE"

    echo
    print_info "Service:"
    kubectl get service "$SERVICE_NAME" -n "$NAMESPACE"

    echo
    print_info "Access URLs:"
    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -n "$minikube_ip" ] && [ -n "$http_port" ]; then
        echo "  OIDC Issuer:  http://${minikube_ip}:${http_port}/dex"
        echo "  Config:       http://${minikube_ip}:${http_port}/dex/.well-known/openid-configuration"
        echo
        echo "  Test users:"
        echo "    admin@example.com / password"
        echo "    user@example.com / password"
    fi
}

# Show Dex logs
show_logs() {
    local lines="${1:-50}"
    local follow="${2:-false}"

    print_header "Dex Logs"
    show_logs "app=dex" "$NAMESPACE" "$lines" "$follow"
}

# Test OIDC configuration
test_oidc() {
    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -z "$minikube_ip" ] || [ -z "$http_port" ]; then
        print_error "Could not determine service URL"
        return 1
    fi

    local url="http://${minikube_ip}:${http_port}/dex/.well-known/openid-configuration"

    print_info "Testing OIDC configuration..."
    curl -s "$url" | jq .
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|status|logs|test|help}"
    echo
    echo "Commands:"
    echo "  deploy    - Deploy Dex to Kubernetes"
    echo "  remove    - Remove Dex from Kubernetes"
    echo "  restart   - Restart Dex deployment"
    echo "  status    - Show Dex status and access URLs"
    echo "  logs      - Show Dex logs [lines] [follow]"
    echo "  test      - Test OIDC configuration endpoint"
    echo "  help      - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
    echo
    echo "Notes:"
    echo "  - Default test users: admin@example.com, user@example.com"
    echo "  - Default password: password"
    echo "  - OIDC client ID: example-app"
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
        test)
            test_oidc
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
