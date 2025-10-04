#!/bin/bash
# Apache Airflow management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="airflow"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/airflow.yaml"
NAMESPACE="${NAMESPACE:-default}"
POSTGRES_DEPLOYMENT="airflow-postgres"
WEBSERVER_DEPLOYMENT="airflow-webserver"
SCHEDULER_DEPLOYMENT="airflow-scheduler"

# Deploy Airflow
deploy() {
    print_header "Deploying Apache Airflow"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    # Check if standalone postgres is running (could be from core infra or airflow)
    local use_standalone_postgres=false
    if resource_exists statefulset "postgres" "$NAMESPACE" || resource_exists service "postgres" "$NAMESPACE"; then
        print_info "Using standalone PostgreSQL service (postgres.${NAMESPACE}.svc.cluster.local)"
        use_standalone_postgres=true
    else
        print_info "Using embedded PostgreSQL (will be deployed with Airflow)"
    fi

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    # Wait for PostgreSQL if embedded (not standalone)
    if [ "$use_standalone_postgres" = false ]; then
        print_info "Waiting for embedded PostgreSQL to be ready..."
        wait_for_deployment "$POSTGRES_DEPLOYMENT" "$NAMESPACE" 120 || {
            print_error "PostgreSQL deployment failed"
            show_logs "app=airflow-postgres" "$NAMESPACE" 50
            return 1
        }
    fi

    # Wait for webserver (includes DB init)
    print_info "Waiting for Airflow Webserver to be ready (this may take a few minutes)..."
    wait_for_deployment "$WEBSERVER_DEPLOYMENT" "$NAMESPACE" 300 || {
        print_error "Airflow Webserver deployment failed"
        show_logs "app=airflow,component=webserver" "$NAMESPACE" 50
        return 1
    }

    # Wait for scheduler
    print_info "Waiting for Airflow Scheduler to be ready..."
    wait_for_deployment "$SCHEDULER_DEPLOYMENT" "$NAMESPACE" 180 || {
        print_error "Airflow Scheduler deployment failed"
        show_logs "app=airflow,component=scheduler" "$NAMESPACE" 50
        return 1
    }

    print_success "Airflow deployed successfully"
    show_status
}

# Remove Airflow
remove() {
    print_header "Removing Apache Airflow"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "Airflow removed"
}

# Restart Airflow
restart() {
    print_header "Restarting Apache Airflow"

    print_info "Restarting Scheduler..."
    kubectl rollout restart deployment/"$SCHEDULER_DEPLOYMENT" -n "$NAMESPACE"

    print_info "Restarting Webserver..."
    kubectl rollout restart deployment/"$WEBSERVER_DEPLOYMENT" -n "$NAMESPACE"

    wait_for_deployment "$WEBSERVER_DEPLOYMENT" "$NAMESPACE" 300
    wait_for_deployment "$SCHEDULER_DEPLOYMENT" "$NAMESPACE" 180

    print_success "Airflow restarted successfully"
}

# Health check for Airflow webserver
health_check() {
    local timeout=5
    local result

    # Check if webserver is accessible via health endpoint
    result=$(kubectl run -n "$NAMESPACE" airflow-health-check --rm -i --restart=Never \
        --image=curlimages/curl:latest --quiet \
        --command -- timeout "$timeout" curl -f -s \
        "http://airflow-webserver.${NAMESPACE}.svc.cluster.local:8080/health" 2>&1)

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "✅ Healthy"
        return 0
    else
        echo "❌ Unhealthy"
        return 1
    fi
}

# Show Airflow status
show_status() {
    print_header "Apache Airflow Status"

    if ! resource_exists deployment "$WEBSERVER_DEPLOYMENT" "$NAMESPACE"; then
        print_warning "Airflow is not deployed"
        return 1
    fi

    echo
    print_info "PostgreSQL:"
    kubectl get deployment "$POSTGRES_DEPLOYMENT" -n "$NAMESPACE" 2>/dev/null || get_pod_status "app=postgres" "$NAMESPACE"

    echo
    print_info "Airflow Webserver:"
    kubectl get deployment "$WEBSERVER_DEPLOYMENT" -n "$NAMESPACE"
    get_pod_status "app=airflow,component=webserver" "$NAMESPACE"

    echo
    print_info "Airflow Scheduler:"
    kubectl get deployment "$SCHEDULER_DEPLOYMENT" -n "$NAMESPACE"
    get_pod_status "app=airflow,component=scheduler" "$NAMESPACE"

    echo
    print_info "Health Check:"
    echo -n "  "
    health_check

    echo
    print_info "Services:"
    kubectl get service -l "app=airflow" -n "$NAMESPACE"

    echo
    print_info "Access URLs:"
    local minikube_ip=$(get_minikube_ip)
    local web_port=$(get_service_nodeport "$WEBSERVER_DEPLOYMENT" "$NAMESPACE" "http")

    if [ -n "$minikube_ip" ] && [ -n "$web_port" ]; then
        echo "  Airflow UI: http://${minikube_ip}:${web_port}"
        echo "  Default credentials: admin/admin"
    fi
}

# Show logs
show_logs() {
    local component="${1:-webserver}"
    local lines="${2:-50}"
    local follow="${3:-false}"

    print_header "Airflow $component Logs"

    case "$component" in
        webserver|web)
            show_logs "app=airflow,component=webserver" "$NAMESPACE" "$lines" "$follow"
            ;;
        scheduler|sched)
            show_logs "app=airflow,component=scheduler" "$NAMESPACE" "$lines" "$follow"
            ;;
        postgres|db)
            show_logs "app=postgres" "$NAMESPACE" "$lines" "$follow"
            ;;
        *)
            print_error "Unknown component: $component (use 'webserver', 'scheduler', or 'postgres')"
            return 1
            ;;
    esac
}

# Execute Airflow CLI command
airflow_cli() {
    local webserver_pod=$(kubectl get pods -l "app=airflow,component=webserver" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$webserver_pod" ]; then
        print_error "Airflow webserver pod not found"
        return 1
    fi

    print_info "Executing: airflow $@"
    kubectl exec -it "$webserver_pod" -n "$NAMESPACE" -- airflow "$@"
}

# Create a new user
create_user() {
    local username="${1:-user}"
    local password="${2:-user}"
    local role="${3:-User}"

    print_info "Creating Airflow user: $username"

    airflow_cli users create \
        --username "$username" \
        --password "$password" \
        --firstname "User" \
        --lastname "Name" \
        --role "$role" \
        --email "${username}@example.com"
}

# Open Airflow UI in browser
open_ui() {
    print_info "Opening Airflow UI..."
    minikube service "$WEBSERVER_DEPLOYMENT" -n "$NAMESPACE" --url=false
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|status|logs|cli|create-user|ui|help}"
    echo
    echo "Commands:"
    echo "  deploy              - Deploy Airflow to Kubernetes"
    echo "  remove              - Remove Airflow from Kubernetes"
    echo "  restart             - Restart Airflow services"
    echo "  status              - Show Airflow status and access URLs"
    echo "  logs <component>    - Show logs [webserver|scheduler|postgres] [lines] [follow]"
    echo "  cli <command>       - Execute Airflow CLI command"
    echo "  create-user         - Create Airflow user [username] [password] [role]"
    echo "  ui                  - Open Airflow UI in browser"
    echo "  help                - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
    echo
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 logs webserver 100"
    echo "  $0 cli dags list"
    echo "  $0 create-user john password123 Admin"
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
            show_logs "${2:-webserver}" "${3:-50}" "${4:-false}"
            ;;
        cli|cmd)
            shift
            airflow_cli "$@"
            ;;
        create-user|adduser)
            create_user "$2" "$3" "$4"
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
