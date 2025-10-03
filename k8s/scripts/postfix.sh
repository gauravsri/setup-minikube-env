#!/bin/bash
# Postfix management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="postfix"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/postfix.yaml"
NAMESPACE="${NAMESPACE:-default}"
DEPLOYMENT_NAME="postfix"

# Deploy Postfix
deploy() {
    print_header "Deploying Postfix"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    wait_for_deployment "$DEPLOYMENT_NAME" "$NAMESPACE" 120 || {
        print_error "Postfix deployment failed"
        show_logs "app=postfix" "$NAMESPACE" 50
        return 1
    }

    print_success "Postfix deployed successfully"
    show_status
}

# Remove Postfix
remove() {
    print_header "Removing Postfix"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "Postfix removed"
}

# Restart Postfix
restart() {
    print_header "Restarting Postfix"

    kubectl rollout restart deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" || {
        print_error "Failed to restart Postfix"
        return 1
    }

    wait_for_deployment "$DEPLOYMENT_NAME" "$NAMESPACE" 120

    print_success "Postfix restarted successfully"
}

# Show Postfix status
show_status() {
    print_header "Postfix Status"

    if ! resource_exists deployment "$DEPLOYMENT_NAME" "$NAMESPACE"; then
        print_warning "Postfix is not deployed"
        return 1
    fi

    echo
    print_info "Deployment Status:"
    kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"

    echo
    print_info "Pods:"
    get_pod_status "app=postfix" "$NAMESPACE"

    echo
    print_info "Service:"
    kubectl get service "$SERVICE_NAME" -n "$NAMESPACE"

    echo
    print_info "Access Information:"
    local minikube_ip=$(get_minikube_ip)
    local smtp_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "smtp")

    if [ -n "$minikube_ip" ] && [ -n "$smtp_port" ]; then
        echo "  SMTP Server: ${minikube_ip}:${smtp_port}"
        echo "  Domain: example.com"
        echo "  Auth: user:password"
    fi
}

# Show Postfix logs
show_logs() {
    local lines="${1:-50}"
    local follow="${2:-false}"

    print_header "Postfix Logs"
    show_logs "app=postfix" "$NAMESPACE" "$lines" "$follow"
}

# Send test email
send_test_email() {
    local to="${1:-test@example.com}"
    local from="${2:-sender@example.com}"
    local subject="${3:-Test Email}"
    local body="${4:-This is a test email from Postfix}"

    local pod=$(kubectl get pods -l "app=postfix" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "Postfix pod not found"
        return 1
    fi

    print_info "Sending test email to: $to"

    kubectl exec -it "$pod" -n "$NAMESPACE" -- bash -c "
        echo '$body' | mail -s '$subject' -a 'From: $from' '$to'
    " 2>/dev/null || {
        # Fallback method
        kubectl exec -it "$pod" -n "$NAMESPACE" -- bash -c "
            echo -e 'Subject: $subject\nFrom: $from\nTo: $to\n\n$body' | sendmail -v '$to'
        "
    }

    print_success "Email sent (check logs for delivery status)"
}

# Check mail queue
check_queue() {
    local pod=$(kubectl get pods -l "app=postfix" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "Postfix pod not found"
        return 1
    fi

    print_info "Checking mail queue..."
    kubectl exec -it "$pod" -n "$NAMESPACE" -- postqueue -p
}

# Flush mail queue
flush_queue() {
    local pod=$(kubectl get pods -l "app=postfix" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "Postfix pod not found"
        return 1
    fi

    print_info "Flushing mail queue..."
    kubectl exec -it "$pod" -n "$NAMESPACE" -- postqueue -f

    print_success "Mail queue flushed"
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|status|logs|test|queue|flush|help}"
    echo
    echo "Commands:"
    echo "  deploy          - Deploy Postfix to Kubernetes"
    echo "  remove          - Remove Postfix from Kubernetes"
    echo "  restart         - Restart Postfix deployment"
    echo "  status          - Show Postfix status and access info"
    echo "  logs            - Show Postfix logs [lines] [follow]"
    echo "  test            - Send test email [to] [from] [subject] [body]"
    echo "  queue           - Check mail queue"
    echo "  flush           - Flush mail queue"
    echo "  help            - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
    echo
    echo "Examples:"
    echo "  $0 test user@example.com"
    echo "  $0 test user@example.com sender@example.com 'Hello' 'Test message'"
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
        test|send)
            send_test_email "$2" "$3" "$4" "$5"
            ;;
        queue)
            check_queue
            ;;
        flush)
            flush_queue
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
