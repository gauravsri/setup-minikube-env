#!/bin/bash
# Elasticsearch management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="elasticsearch"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/elasticsearch.yaml"
NAMESPACE="${NAMESPACE:-default}"
STATEFULSET_NAME="elasticsearch"

# Deploy Elasticsearch
deploy() {
    print_header "Deploying Elasticsearch"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    wait_for_statefulset "$STATEFULSET_NAME" "$NAMESPACE" 180 || {
        print_error "Elasticsearch deployment failed"
        show_logs "app=elasticsearch" "$NAMESPACE" 50
        return 1
    }

    print_success "Elasticsearch deployed successfully"
    show_status
}

# Remove Elasticsearch
remove() {
    print_header "Removing Elasticsearch"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    # Also delete PVCs created by StatefulSet
    print_info "Removing persistent volume claims..."
    kubectl delete pvc -l app=elasticsearch -n "$NAMESPACE" 2>/dev/null || true

    print_success "Elasticsearch removed"
}

# Restart Elasticsearch
restart() {
    print_header "Restarting Elasticsearch"

    kubectl rollout restart statefulset/"$STATEFULSET_NAME" -n "$NAMESPACE" || {
        print_error "Failed to restart Elasticsearch"
        return 1
    }

    wait_for_statefulset "$STATEFULSET_NAME" "$NAMESPACE" 180

    print_success "Elasticsearch restarted successfully"
}

# Show Elasticsearch status
show_status() {
    print_header "Elasticsearch Status"

    if ! resource_exists statefulset "$STATEFULSET_NAME" "$NAMESPACE"; then
        print_warning "Elasticsearch is not deployed"
        return 1
    fi

    echo
    print_info "StatefulSet Status:"
    kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE"

    echo
    print_info "Pods:"
    get_pod_status "app=elasticsearch" "$NAMESPACE"

    echo
    print_info "Service:"
    kubectl get service "$SERVICE_NAME" -n "$NAMESPACE"

    echo
    print_info "Persistent Volume Claims:"
    kubectl get pvc -l app=elasticsearch -n "$NAMESPACE"

    echo
    print_info "Access URLs:"
    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -n "$minikube_ip" ] && [ -n "$http_port" ]; then
        echo "  REST API:    http://${minikube_ip}:${http_port}"
        echo "  Health:      http://${minikube_ip}:${http_port}/_cluster/health"
        echo "  Cluster:     http://${minikube_ip}:${http_port}/_cluster/state"
        echo ""
        echo "  Security is disabled for development - no authentication required"
    fi

    # Show cluster health
    echo
    cluster_health
}

# Show Elasticsearch logs
show_logs() {
    local lines="${1:-50}"
    local follow="${2:-false}"

    print_header "Elasticsearch Logs"

    local pod_name=$(kubectl get pods -n "$NAMESPACE" -l app=elasticsearch -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$pod_name" ]; then
        print_error "No Elasticsearch pods found"
        return 1
    fi

    if [ "$follow" == "true" ]; then
        kubectl logs -n "$NAMESPACE" "$pod_name" -f --tail="$lines"
    else
        kubectl logs -n "$NAMESPACE" "$pod_name" --tail="$lines"
    fi
}

# Get cluster health
cluster_health() {
    print_info "Cluster Health:"

    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -z "$minikube_ip" ] || [ -z "$http_port" ]; then
        print_error "Could not determine service URL"
        return 1
    fi

    local url="http://${minikube_ip}:${http_port}/_cluster/health?pretty"

    curl -s "$url" 2>/dev/null || {
        print_error "Failed to connect to Elasticsearch"
        return 1
    }
}

# Get cluster stats
cluster_stats() {
    print_header "Cluster Statistics"

    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -z "$minikube_ip" ] || [ -z "$http_port" ]; then
        print_error "Could not determine service URL"
        return 1
    fi

    local url="http://${minikube_ip}:${http_port}/_cluster/stats?pretty"

    curl -s "$url"
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

    local url="http://${minikube_ip}:${http_port}/${index_name}"

    print_info "Creating index: $index_name"
    curl -X PUT "$url" \
        -H "Content-Type: application/json" \
        -d '{
            "settings": {
                "number_of_shards": 1,
                "number_of_replicas": 0
            }
        }' | jq .
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

    local url="http://${minikube_ip}:${http_port}/_cat/indices?v"

    print_info "Listing indices..."
    curl -s "$url"
    echo
}

# Delete index
delete_index() {
    local index_name="${1}"

    if [ -z "$index_name" ]; then
        print_error "Index name required"
        return 1
    fi

    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -z "$minikube_ip" ] || [ -z "$http_port" ]; then
        print_error "Could not determine service URL"
        return 1
    fi

    local url="http://${minikube_ip}:${http_port}/${index_name}"

    print_info "Deleting index: $index_name"
    curl -X DELETE "$url" | jq .
    echo
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

    local url="http://${minikube_ip}:${http_port}/${index_name}/_doc"

    shift
    local doc="$@"

    if [ -z "$doc" ]; then
        doc='{"message": "test document", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "value": 123}'
    fi

    print_info "Indexing document to: $index_name"
    curl -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$doc" | jq .
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

    local url="http://${minikube_ip}:${http_port}/${index_name}/_search"

    print_info "Searching index: $index_name for: $query"

    if [ "$query" == "*" ]; then
        curl -X GET "$url" \
            -H "Content-Type: application/json" \
            -d '{"query": {"match_all": {}}}' | jq .
    else
        curl -X GET "$url" \
            -H "Content-Type: application/json" \
            -d "{\"query\": {\"match\": {\"message\": \"$query\"}}}" | jq .
    fi
    echo
}

# Get node info
node_info() {
    print_header "Node Information"

    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -z "$minikube_ip" ] || [ -z "$http_port" ]; then
        print_error "Could not determine service URL"
        return 1
    fi

    local url="http://${minikube_ip}:${http_port}/_nodes?pretty"

    curl -s "$url"
}

# Open Elasticsearch in browser (show cluster health)
open_ui() {
    local minikube_ip=$(get_minikube_ip)
    local http_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "http")

    if [ -z "$minikube_ip" ] || [ -z "$http_port" ]; then
        print_error "Could not determine service URL"
        return 1
    fi

    local url="http://${minikube_ip}:${http_port}/_cluster/health?pretty"

    print_info "Opening Elasticsearch cluster health..."
    if command -v open &> /dev/null; then
        open "$url"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$url"
    else
        echo "URL: $url"
    fi
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|status|logs|index|search|health|stats|nodes|help}"
    echo
    echo "Commands:"
    echo "  deploy              - Deploy Elasticsearch to Kubernetes"
    echo "  remove              - Remove Elasticsearch from Kubernetes"
    echo "  restart             - Restart Elasticsearch StatefulSet"
    echo "  status              - Show Elasticsearch status and access URLs"
    echo "  logs                - Show Elasticsearch logs [lines] [follow]"
    echo "  health              - Show cluster health"
    echo "  stats               - Show cluster statistics"
    echo "  nodes               - Show node information"
    echo "  index create        - Create index [name]"
    echo "  index list          - List all indices"
    echo "  index delete        - Delete index [name]"
    echo "  index doc           - Index document [index] [json]"
    echo "  search              - Search documents [index] [query]"
    echo "  ui                  - Open Elasticsearch health in browser"
    echo "  help                - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
    echo
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 index create my-index"
    echo "  $0 index doc my-index '{\"message\":\"hello world\"}'"
    echo "  $0 search my-index hello"
    echo "  $0 health"
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
        health)
            cluster_health
            ;;
        stats)
            cluster_stats
            ;;
        nodes)
            node_info
            ;;
        index)
            case "${2}" in
                create)
                    create_index "$3"
                    ;;
                list)
                    list_indices
                    ;;
                delete)
                    delete_index "$3"
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
