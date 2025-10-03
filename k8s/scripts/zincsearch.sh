#!/bin/bash
# ZincSearch management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="zincsearch"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/zincsearch.yaml"
NAMESPACE="${NAMESPACE:-default}"
DEPLOYMENT_NAME="zincsearch"

# Deploy ZincSearch
deploy() {
    print_header "Deploying ZincSearch"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    wait_for_deployment "$DEPLOYMENT_NAME" "$NAMESPACE" 120 || {
        print_error "ZincSearch deployment failed"
        show_logs "app=zincsearch" "$NAMESPACE" 50
        return 1
    }

    print_success "ZincSearch deployed successfully"
    show_status
}

# Remove ZincSearch
remove() {
    print_header "Removing ZincSearch"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "ZincSearch removed"
}

# Restart ZincSearch
restart() {
    print_header "Restarting ZincSearch"

    kubectl rollout restart deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" || {
        print_error "Failed to restart ZincSearch"
        return 1
    }

    wait_for_deployment "$DEPLOYMENT_NAME" "$NAMESPACE" 120

    print_success "ZincSearch restarted successfully"
}

# Show ZincSearch status
show_status() {
    print_header "ZincSearch Status"

    if ! resource_exists deployment "$DEPLOYMENT_NAME" "$NAMESPACE"; then
        print_warning "ZincSearch is not deployed"
        return 1
    fi

    echo
    print_info "Deployment Status:"
    kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"

    echo
    print_info "Pods:"
    get_pod_status "app=zincsearch" "$NAMESPACE"

    echo
    print_info "Service:"
    kubectl get service "$SERVICE_NAME" -n "$NAMESPACE"

    echo
    print_info "Access URLs:"
    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -n "$minikube_ip" ] && [ -n "$http_port" ]; then
        echo "  Web UI:      http://${minikube_ip}:${http_port}"
        echo "  API Docs:    http://${minikube_ip}:${http_port}/ui/"
        echo "  Default credentials: admin/admin"
    fi
}

# Show ZincSearch logs
show_logs() {
    local lines="${1:-50}"
    local follow="${2:-false}"

    print_header "ZincSearch Logs"
    show_logs "app=zincsearch" "$NAMESPACE" "$lines" "$follow"
}

# Create index
create_index() {
    local index_name="${1:-test-index}"
    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -z "$minikube_ip" ] || [ -z "$http_port" ]; then
        print_error "Could not determine service URL"
        return 1
    fi

    local url="http://${minikube_ip}:${http_port}/api/index"

    print_info "Creating index: $index_name"
    curl -u admin:admin -X PUT "$url" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$index_name\", \"storage_type\": \"disk\"}"
    echo
}

# List indices
list_indices() {
    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -z "$minikube_ip" ] || [ -z "$http_port" ]; then
        print_error "Could not determine service URL"
        return 1
    fi

    local url="http://${minikube_ip}:${http_port}/api/index"

    print_info "Listing indices..."
    curl -u admin:admin -s "$url" | jq .
}

# Index document
index_doc() {
    local index_name="${1:-test-index}"
    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -z "$minikube_ip" ] || [ -z "$http_port" ]; then
        print_error "Could not determine service URL"
        return 1
    fi

    local url="http://${minikube_ip}:${http_port}/api/${index_name}/_doc"

    shift
    local doc="$@"

    if [ -z "$doc" ]; then
        doc='{"message": "test document", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
    fi

    print_info "Indexing document to: $index_name"
    curl -u admin:admin -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$doc"
    echo
}

# Search documents
search() {
    local index_name="${1:-test-index}"
    local query="${2:-*}"
    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -z "$minikube_ip" ] || [ -z "$http_port" ]; then
        print_error "Could not determine service URL"
        return 1
    fi

    local url="http://${minikube_ip}:${http_port}/api/${index_name}/_search"

    print_info "Searching index: $index_name for: $query"
    curl -u admin:admin -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{\"search_type\": \"match\", \"query\": {\"term\": \"$query\"}, \"from\": 0, \"max_results\": 20}" | jq .
}

# Open ZincSearch UI in browser
open_ui() {
    print_info "Opening ZincSearch UI..."
    minikube service "$SERVICE_NAME" -n "$NAMESPACE" --url=false
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|status|logs|index|search|ui|help}"
    echo
    echo "Commands:"
    echo "  deploy              - Deploy ZincSearch to Kubernetes"
    echo "  remove              - Remove ZincSearch from Kubernetes"
    echo "  restart             - Restart ZincSearch deployment"
    echo "  status              - Show ZincSearch status and access URLs"
    echo "  logs                - Show ZincSearch logs [lines] [follow]"
    echo "  index create        - Create index [name]"
    echo "  index list          - List all indices"
    echo "  index doc           - Index document [index] [json]"
    echo "  search              - Search documents [index] [query]"
    echo "  ui                  - Open ZincSearch UI in browser"
    echo "  help                - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
    echo
    echo "Examples:"
    echo "  $0 index create my-index"
    echo "  $0 index doc my-index '{\"message\":\"hello\"}'"
    echo "  $0 search my-index hello"
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
        index)
            case "${2}" in
                create)
                    create_index "$3"
                    ;;
                list)
                    list_indices
                    ;;
                doc)
                    index_doc "$3" "$4"
                    ;;
                *)
                    print_error "Unknown index command: $2"
                    usage
                    exit 1
                    ;;
            esac
            ;;
        search)
            search "$2" "$3"
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
