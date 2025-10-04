#!/bin/bash
# PostgreSQL management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="postgres"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/postgres.yaml"
NAMESPACE="${NAMESPACE:-default}"
STATEFULSET_NAME="postgres"

# Deploy PostgreSQL
deploy() {
    print_header "Deploying PostgreSQL"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    wait_for_statefulset "$STATEFULSET_NAME" "$NAMESPACE" 1 120 || {
        print_error "PostgreSQL deployment failed"
        show_logs "app=postgres" "$NAMESPACE" 50
        return 1
    }

    print_success "PostgreSQL deployed successfully"
    show_status
}

# Remove PostgreSQL
remove() {
    print_header "Removing PostgreSQL"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "PostgreSQL removed"
}

# Restart PostgreSQL
restart() {
    print_header "Restarting PostgreSQL"

    kubectl rollout restart statefulset/"$STATEFULSET_NAME" -n "$NAMESPACE" || {
        print_error "Failed to restart PostgreSQL"
        return 1
    }

    wait_for_statefulset "$STATEFULSET_NAME" "$NAMESPACE" 1 120

    print_success "PostgreSQL restarted successfully"
}

# Health check for PostgreSQL connectivity
health_check() {
    local timeout=5
    local result

    result=$(kubectl run -n "$NAMESPACE" postgres-health-check --rm -i --restart=Never \
        --image=postgres:15 --env="PGPASSWORD=postgres" --quiet \
        --command -- timeout "$timeout" psql \
        -h "postgres.${NAMESPACE}.svc.cluster.local" \
        -U postgres -c "SELECT 1;" 2>&1)

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "✅ Healthy"
        return 0
    else
        echo "❌ Unhealthy"
        return 1
    fi
}

# Show PostgreSQL status
show_status() {
    print_header "PostgreSQL Status"

    if ! resource_exists statefulset "$STATEFULSET_NAME" "$NAMESPACE"; then
        print_warning "PostgreSQL is not deployed"
        return 1
    fi

    echo
    print_info "StatefulSet Status:"
    kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE"

    echo
    print_info "Pods:"
    get_pod_status "app=postgres" "$NAMESPACE"

    echo
    print_info "Service:"
    kubectl get service "$SERVICE_NAME" -n "$NAMESPACE"

    echo
    print_info "Persistent Volume:"
    kubectl get pvc postgres-pvc -n "$NAMESPACE" 2>/dev/null || echo "  No PVC found"

    echo
    print_info "Health Check:"
    echo -n "  "
    health_check

    echo
    print_info "Access Information:"
    local minikube_ip=$(get_minikube_ip)
    local postgres_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "postgres")

    if [ -n "$minikube_ip" ] && [ -n "$postgres_port" ]; then
        echo "  Host: ${minikube_ip}:${postgres_port}"
        echo "  Internal: postgres.${NAMESPACE}.svc.cluster.local:5432"
        echo
        echo "  Connection String:"
        echo "    postgresql://postgres:postgres@${minikube_ip}:${postgres_port}/postgres"
        echo
        echo "  Default Credentials:"
        echo "    Username: postgres"
        echo "    Password: postgres"
        echo "    Database: postgres"
    fi
}

# Show PostgreSQL logs
show_logs() {
    local lines="${1:-50}"
    local follow="${2:-false}"

    print_header "PostgreSQL Logs"
    show_logs "app=postgres" "$NAMESPACE" "$lines" "$follow"
}

# PostgreSQL CLI access
psql_cli() {
    local pod=$(kubectl get pods -l "app=postgres" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "PostgreSQL pod not found"
        return 1
    fi

    print_info "Connecting to PostgreSQL CLI..."
    kubectl exec -it "$pod" -n "$NAMESPACE" -- psql -U postgres "$@"
}

# Execute SQL query
execute_sql() {
    local query="$1"
    local database="${2:-postgres}"

    if [ -z "$query" ]; then
        print_error "No SQL query provided"
        return 1
    fi

    local pod=$(kubectl get pods -l "app=postgres" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "PostgreSQL pod not found"
        return 1
    fi

    print_info "Executing SQL query..."
    kubectl exec -it "$pod" -n "$NAMESPACE" -- psql -U postgres -d "$database" -c "$query"
}

# List databases
list_databases() {
    print_info "Listing databases..."
    execute_sql "\l"
}

# List tables in database
list_tables() {
    local database="${1:-postgres}"
    print_info "Listing tables in database: $database"
    execute_sql "\dt" "$database"
}

# Create database
create_database() {
    local dbname="$1"
    local owner="${2:-postgres}"

    if [ -z "$dbname" ]; then
        print_error "Database name required"
        echo "Usage: $0 create-db <dbname> [owner]"
        return 1
    fi

    print_info "Creating database: $dbname"
    execute_sql "CREATE DATABASE $dbname OWNER $owner;" "postgres"
    print_success "Database '$dbname' created"
}

# Create user
create_user() {
    local username="$1"
    local password="$2"

    if [ -z "$username" ] || [ -z "$password" ]; then
        print_error "Username and password required"
        echo "Usage: $0 create-user <username> <password>"
        return 1
    fi

    print_info "Creating user: $username"
    execute_sql "CREATE USER $username WITH PASSWORD '$password';" "postgres"
    print_success "User '$username' created"
}

# Grant privileges
grant_privileges() {
    local dbname="$1"
    local username="$2"

    if [ -z "$dbname" ] || [ -z "$username" ]; then
        print_error "Database name and username required"
        echo "Usage: $0 grant <dbname> <username>"
        return 1
    fi

    print_info "Granting privileges on $dbname to $username"
    execute_sql "GRANT ALL PRIVILEGES ON DATABASE $dbname TO $username;" "postgres"
    print_success "Privileges granted"
}

# Backup database
backup_database() {
    local dbname="${1:-postgres}"
    local backup_file="${2:-backup-$(date +%Y%m%d-%H%M%S).sql}"

    local pod=$(kubectl get pods -l "app=postgres" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "PostgreSQL pod not found"
        return 1
    fi

    print_info "Backing up database: $dbname to $backup_file"
    kubectl exec "$pod" -n "$NAMESPACE" -- pg_dump -U postgres "$dbname" > "$backup_file"
    print_success "Backup saved to: $backup_file"
}

# Restore database
restore_database() {
    local backup_file="$1"
    local dbname="${2:-postgres}"

    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi

    local pod=$(kubectl get pods -l "app=postgres" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "PostgreSQL pod not found"
        return 1
    fi

    print_info "Restoring database: $dbname from $backup_file"
    cat "$backup_file" | kubectl exec -i "$pod" -n "$NAMESPACE" -- psql -U postgres "$dbname"
    print_success "Database restored"
}

# Show PostgreSQL version
show_version() {
    local pod=$(kubectl get pods -l "app=postgres" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "PostgreSQL pod not found"
        return 1
    fi

    kubectl exec "$pod" -n "$NAMESPACE" -- psql -U postgres -c "SELECT version();"
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|status|logs|psql|sql|help}"
    echo
    echo "Commands:"
    echo "  deploy              - Deploy PostgreSQL to Kubernetes"
    echo "  remove              - Remove PostgreSQL from Kubernetes"
    echo "  restart             - Restart PostgreSQL StatefulSet"
    echo "  status              - Show PostgreSQL status and connection info"
    echo "  logs [lines]        - Show PostgreSQL logs"
    echo "  psql                - Open PostgreSQL CLI"
    echo "  sql <query> [db]    - Execute SQL query"
    echo "  list-db             - List all databases"
    echo "  list-tables [db]    - List tables in database"
    echo "  create-db <name> [owner] - Create new database"
    echo "  create-user <user> <pass> - Create new user"
    echo "  grant <db> <user>   - Grant privileges to user"
    echo "  backup [db] [file]  - Backup database"
    echo "  restore <file> [db] - Restore database from backup"
    echo "  version             - Show PostgreSQL version"
    echo "  help                - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
    echo
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 psql"
    echo "  $0 sql \"SELECT * FROM users;\" mydb"
    echo "  $0 create-db myapp postgres"
    echo "  $0 create-user appuser mypassword"
    echo "  $0 grant myapp appuser"
    echo "  $0 backup mydb backup.sql"
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
        psql|cli)
            shift
            psql_cli "$@"
            ;;
        sql|query|exec)
            execute_sql "$2" "$3"
            ;;
        list-db|databases)
            list_databases
            ;;
        list-tables|tables)
            list_tables "$2"
            ;;
        create-db|createdb)
            create_database "$2" "$3"
            ;;
        create-user|createuser)
            create_user "$2" "$3"
            ;;
        grant)
            grant_privileges "$2" "$3"
            ;;
        backup)
            backup_database "$2" "$3"
            ;;
        restore)
            restore_database "$2" "$3"
            ;;
        version)
            show_version
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
