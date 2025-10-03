#!/bin/bash
# Redpanda management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="redpanda"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/redpanda.yaml"
NAMESPACE="${NAMESPACE:-default}"
STATEFULSET_NAME="redpanda"

# Deploy Redpanda
deploy() {
    print_header "Deploying Redpanda"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    print_info "Waiting for Redpanda to be ready..."
    wait_for_statefulset "$STATEFULSET_NAME" "$NAMESPACE" 1 180 || {
        print_error "Redpanda deployment failed"
        show_logs "app=redpanda" "$NAMESPACE" 50
        return 1
    }

    print_success "Redpanda deployed successfully"
    show_status
}

# Remove Redpanda
remove() {
    print_header "Removing Redpanda"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "Redpanda removed"
}

# Restart Redpanda
restart() {
    print_header "Restarting Redpanda"

    kubectl rollout restart statefulset/"$STATEFULSET_NAME" -n "$NAMESPACE" || {
        print_error "Failed to restart Redpanda"
        return 1
    }

    wait_for_statefulset "$STATEFULSET_NAME" "$NAMESPACE" 1 180

    print_success "Redpanda restarted successfully"
}

# Show Redpanda status
show_status() {
    print_header "Redpanda Status"

    if ! resource_exists statefulset "$STATEFULSET_NAME" "$NAMESPACE"; then
        print_warning "Redpanda is not deployed"
        return 1
    fi

    echo
    print_info "StatefulSet Status:"
    kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE"

    echo
    print_info "Pods:"
    get_pod_status "app=redpanda" "$NAMESPACE"

    echo
    print_info "Services:"
    kubectl get service -l "app=redpanda" -n "$NAMESPACE"

    echo
    print_info "Access URLs:"
    local minikube_ip=$(get_minikube_ip)
    local kafka_port=$(get_service_nodeport "redpanda-external" "$NAMESPACE" "kafka")
    local admin_port=$(get_service_nodeport "redpanda-external" "$NAMESPACE" "admin")
    local proxy_port=$(get_service_nodeport "redpanda-external" "$NAMESPACE" "http-proxy")
    local schema_port=$(get_service_nodeport "redpanda-external" "$NAMESPACE" "schema-registry")

    if [ -n "$minikube_ip" ] && [ -n "$kafka_port" ]; then
        echo "  Kafka API:         ${minikube_ip}:${kafka_port}"
        echo "  Admin API:         http://${minikube_ip}:${admin_port}"
        echo "  HTTP Proxy:        http://${minikube_ip}:${proxy_port}"
        echo "  Schema Registry:   http://${minikube_ip}:${schema_port}"
    fi
}

# Show Redpanda logs
show_logs() {
    local lines="${1:-50}"
    local follow="${2:-false}"

    print_header "Redpanda Logs"
    show_logs "app=redpanda" "$NAMESPACE" "$lines" "$follow"
}

# Execute rpk command
rpk_cmd() {
    local pod="${STATEFULSET_NAME}-0"

    if ! kubectl get pod "$pod" -n "$NAMESPACE" >/dev/null 2>&1; then
        print_error "Redpanda pod not found"
        return 1
    fi

    print_info "Executing: rpk $@"
    kubectl exec -it "$pod" -n "$NAMESPACE" -- rpk "$@"
}

# Create topic
create_topic() {
    local topic_name="${1:-test-topic}"
    local partitions="${2:-3}"
    local replicas="${3:-1}"

    print_info "Creating topic: $topic_name (partitions: $partitions, replicas: $replicas)"
    rpk_cmd topic create "$topic_name" --partitions "$partitions" --replicas "$replicas"
}

# List topics
list_topics() {
    print_info "Listing topics..."
    rpk_cmd topic list
}

# Produce message
produce() {
    local topic="${1:-test-topic}"

    print_info "Producing to topic: $topic"
    echo "Type messages (Ctrl+D to finish):"
    rpk_cmd topic produce "$topic"
}

# Consume messages
consume() {
    local topic="${1:-test-topic}"

    print_info "Consuming from topic: $topic"
    rpk_cmd topic consume "$topic"
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|status|logs|rpk|topic|produce|consume|help}"
    echo
    echo "Commands:"
    echo "  deploy              - Deploy Redpanda to Kubernetes"
    echo "  remove              - Remove Redpanda from Kubernetes"
    echo "  restart             - Restart Redpanda statefulset"
    echo "  status              - Show Redpanda status and access URLs"
    echo "  logs                - Show Redpanda logs [lines] [follow]"
    echo "  rpk <command>       - Execute rpk command"
    echo "  topic create        - Create topic [name] [partitions] [replicas]"
    echo "  topic list          - List all topics"
    echo "  produce <topic>     - Produce messages to topic"
    echo "  consume <topic>     - Consume messages from topic"
    echo "  help                - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
    echo
    echo "Examples:"
    echo "  $0 topic create my-topic 3 1"
    echo "  $0 produce my-topic"
    echo "  $0 consume my-topic"
    echo "  $0 rpk cluster info"
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
        rpk)
            shift
            rpk_cmd "$@"
            ;;
        topic)
            case "${2}" in
                create)
                    create_topic "$3" "$4" "$5"
                    ;;
                list)
                    list_topics
                    ;;
                *)
                    print_error "Unknown topic command: $2"
                    usage
                    exit 1
                    ;;
            esac
            ;;
        produce)
            produce "$2"
            ;;
        consume)
            consume "$2"
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
