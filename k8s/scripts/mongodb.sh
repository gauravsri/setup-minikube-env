#!/bin/bash
# MongoDB management script for Kubernetes/Minikube

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SERVICE_NAME="mongodb"
MANIFEST_FILE="$SCRIPT_DIR/../manifests/mongodb.yaml"
NAMESPACE="${NAMESPACE:-default}"
STATEFULSET_NAME="mongodb"

# Deploy MongoDB
deploy() {
    print_header "Deploying MongoDB"

    ensure_minikube_running || return 1
    create_namespace "$NAMESPACE" || return 1

    apply_manifest "$MANIFEST_FILE" "$NAMESPACE" || return 1

    wait_for_statefulset "$STATEFULSET_NAME" "$NAMESPACE" 1 120 || {
        print_error "MongoDB deployment failed"
        show_logs "app=mongodb" "$NAMESPACE" 50
        return 1
    }

    print_success "MongoDB deployed successfully"
    show_status
}

# Remove MongoDB
remove() {
    print_header "Removing MongoDB"

    delete_manifest "$MANIFEST_FILE" "$NAMESPACE"

    print_success "MongoDB removed"
}

# Restart MongoDB
restart() {
    print_header "Restarting MongoDB"

    kubectl rollout restart statefulset/"$STATEFULSET_NAME" -n "$NAMESPACE" || {
        print_error "Failed to restart MongoDB"
        return 1
    }

    wait_for_statefulset "$STATEFULSET_NAME" "$NAMESPACE" 1 120

    print_success "MongoDB restarted successfully"
}

# Health check for MongoDB connectivity
health_check() {
    local timeout=5
    local result

    result=$(kubectl run -n "$NAMESPACE" mongodb-health-check --rm -i --restart=Never \
        --image=mongo:8.0 --quiet \
        --command -- timeout "$timeout" mongosh \
        --host "mongodb.${NAMESPACE}.svc.cluster.local" \
        --username admin \
        --password mongodb \
        --authenticationDatabase admin \
        --eval "db.adminCommand('ping')" 2>&1)

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "✅ Healthy"
        return 0
    else
        echo "❌ Unhealthy"
        return 1
    fi
}

# Show MongoDB status
show_status() {
    print_header "MongoDB Status"

    if ! resource_exists statefulset "$STATEFULSET_NAME" "$NAMESPACE"; then
        print_warning "MongoDB is not deployed"
        return 1
    fi

    echo
    print_info "StatefulSet Status:"
    kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE"

    echo
    print_info "Pods:"
    get_pod_status "app=mongodb" "$NAMESPACE"

    echo
    print_info "Service:"
    kubectl get service "$SERVICE_NAME" -n "$NAMESPACE"

    echo
    print_info "Persistent Volume:"
    kubectl get pvc mongodb-pvc -n "$NAMESPACE" 2>/dev/null || echo "  No PVC found"

    echo
    print_info "Health Check:"
    echo -n "  "
    health_check

    echo
    print_info "Access Information:"
    local minikube_ip=$(get_minikube_ip)
    local mongodb_port=$(get_service_nodeport "$SERVICE_NAME" "$NAMESPACE" "mongodb")

    if [ -n "$minikube_ip" ] && [ -n "$mongodb_port" ]; then
        echo "  Host: ${minikube_ip}:${mongodb_port}"
        echo "  Internal: mongodb.${NAMESPACE}.svc.cluster.local:27017"
        echo
        echo "  Connection String:"
        echo "    mongodb://admin:mongodb@${minikube_ip}:${mongodb_port}/admin"
        echo
        echo "  Default Credentials:"
        echo "    Username: admin"
        echo "    Password: mongodb"
        echo "    Database: admin"
    fi
}

# Show MongoDB logs
show_logs_cmd() {
    local lines="${1:-50}"
    local follow="${2:-false}"

    print_header "MongoDB Logs"

    local pod=$(kubectl get pods -l "app=mongodb" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$pod" ]; then
        print_error "MongoDB pod not found"
        return 1
    fi

    if [ "$follow" = "true" ]; then
        kubectl logs -f "$pod" -n "$NAMESPACE" --tail="$lines"
    else
        kubectl logs "$pod" -n "$NAMESPACE" --tail="$lines"
    fi
}

# MongoDB Shell access
mongosh_cli() {
    local pod=$(kubectl get pods -l "app=mongodb" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "MongoDB pod not found"
        return 1
    fi

    print_info "Connecting to MongoDB Shell..."
    kubectl exec -it "$pod" -n "$NAMESPACE" -- mongosh -u admin -p mongodb --authenticationDatabase admin "$@"
}

# Execute MongoDB command
execute_command() {
    local command="$1"
    local database="${2:-admin}"

    if [ -z "$command" ]; then
        print_error "No command provided"
        return 1
    fi

    local pod=$(kubectl get pods -l "app=mongodb" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "MongoDB pod not found"
        return 1
    fi

    print_info "Executing MongoDB command..."
    kubectl exec -it "$pod" -n "$NAMESPACE" -- mongosh -u admin -p mongodb --authenticationDatabase admin "$database" --eval "$command"
}

# List databases
list_databases() {
    print_info "Listing databases..."
    execute_command "db.adminCommand('listDatabases')" "admin"
}

# List collections in database
list_collections() {
    local database="${1:-admin}"
    print_info "Listing collections in database: $database"
    execute_command "db.getCollectionNames()" "$database"
}

# Create database (MongoDB creates on first write)
create_database() {
    local dbname="$1"

    if [ -z "$dbname" ]; then
        print_error "Database name required"
        echo "Usage: $0 create-db <dbname>"
        return 1
    fi

    print_info "Creating database: $dbname (will be created on first write)"
    execute_command "db.createCollection('_init')" "$dbname"
    print_success "Database '$dbname' initialized"
}

# Create user
create_user() {
    local username="$1"
    local password="$2"
    local database="${3:-admin}"
    local role="${4:-readWrite}"

    if [ -z "$username" ] || [ -z "$password" ]; then
        print_error "Username and password required"
        echo "Usage: $0 create-user <username> <password> [database] [role]"
        return 1
    fi

    print_info "Creating user: $username in database: $database with role: $role"
    execute_command "db.createUser({user: '$username', pwd: '$password', roles: [{role: '$role', db: '$database'}]})" "$database"
    print_success "User '$username' created"
}

# Grant role to user
grant_role() {
    local username="$1"
    local database="$2"
    local role="${3:-readWrite}"

    if [ -z "$username" ] || [ -z "$database" ]; then
        print_error "Username and database required"
        echo "Usage: $0 grant <username> <database> [role]"
        return 1
    fi

    print_info "Granting role '$role' on '$database' to '$username'"
    execute_command "db.grantRolesToUser('$username', [{role: '$role', db: '$database'}])" "admin"
    print_success "Role granted"
}

# Backup database
backup_database() {
    local dbname="${1:-admin}"
    local backup_dir="${2:-./mongodb-backup-$(date +%Y%m%d-%H%M%S)}"

    local pod=$(kubectl get pods -l "app=mongodb" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "MongoDB pod not found"
        return 1
    fi

    print_info "Backing up database: $dbname to $backup_dir"
    mkdir -p "$backup_dir"

    kubectl exec "$pod" -n "$NAMESPACE" -- mongodump \
        --username admin \
        --password mongodb \
        --authenticationDatabase admin \
        --db "$dbname" \
        --archive \
        --gzip > "$backup_dir/${dbname}.archive.gz"

    print_success "Backup saved to: $backup_dir/${dbname}.archive.gz"
}

# Restore database
restore_database() {
    local backup_file="$1"
    local dbname="${2}"

    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi

    if [ -z "$dbname" ]; then
        print_error "Database name required"
        echo "Usage: $0 restore <backup_file> <database>"
        return 1
    fi

    local pod=$(kubectl get pods -l "app=mongodb" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "MongoDB pod not found"
        return 1
    fi

    print_info "Restoring database: $dbname from $backup_file"
    cat "$backup_file" | kubectl exec -i "$pod" -n "$NAMESPACE" -- mongorestore \
        --username admin \
        --password mongodb \
        --authenticationDatabase admin \
        --db "$dbname" \
        --archive \
        --gzip

    print_success "Database restored"
}

# Show MongoDB version and server status
show_version() {
    local pod=$(kubectl get pods -l "app=mongodb" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "MongoDB pod not found"
        return 1
    fi

    kubectl exec "$pod" -n "$NAMESPACE" -- mongosh -u admin -p mongodb --authenticationDatabase admin --eval "db.version(); db.serverStatus().host"
}

# Show server statistics
show_stats() {
    print_info "MongoDB Server Statistics..."
    execute_command "db.serverStatus()" "admin"
}

# Import JSON data
import_json() {
    local file="$1"
    local database="$2"
    local collection="$3"

    if [ -z "$file" ] || [ -z "$database" ] || [ -z "$collection" ]; then
        print_error "File, database, and collection required"
        echo "Usage: $0 import <file.json> <database> <collection>"
        return 1
    fi

    if [ ! -f "$file" ]; then
        print_error "File not found: $file"
        return 1
    fi

    local pod=$(kubectl get pods -l "app=mongodb" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "MongoDB pod not found"
        return 1
    fi

    print_info "Importing $file to $database.$collection"

    # Copy file to pod
    kubectl cp "$file" "$NAMESPACE/$pod:/tmp/import.json"

    # Import data
    kubectl exec "$pod" -n "$NAMESPACE" -- mongoimport \
        --username admin \
        --password mongodb \
        --authenticationDatabase admin \
        --db "$database" \
        --collection "$collection" \
        --file /tmp/import.json \
        --jsonArray

    print_success "Data imported"
}

# Export collection to JSON
export_json() {
    local database="$1"
    local collection="$2"
    local output_file="${3:-${collection}-$(date +%Y%m%d-%H%M%S).json}"

    if [ -z "$database" ] || [ -z "$collection" ]; then
        print_error "Database and collection required"
        echo "Usage: $0 export <database> <collection> [output_file]"
        return 1
    fi

    local pod=$(kubectl get pods -l "app=mongodb" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$pod" ]; then
        print_error "MongoDB pod not found"
        return 1
    fi

    print_info "Exporting $database.$collection to $output_file"

    kubectl exec "$pod" -n "$NAMESPACE" -- mongoexport \
        --username admin \
        --password mongodb \
        --authenticationDatabase admin \
        --db "$database" \
        --collection "$collection" \
        --jsonArray > "$output_file"

    print_success "Data exported to: $output_file"
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|remove|restart|status|logs|mongosh|help}"
    echo
    echo "Commands:"
    echo "  deploy                     - Deploy MongoDB to Kubernetes"
    echo "  remove                     - Remove MongoDB from Kubernetes"
    echo "  restart                    - Restart MongoDB StatefulSet"
    echo "  status                     - Show MongoDB status and connection info"
    echo "  logs [lines]               - Show MongoDB logs"
    echo "  mongosh                    - Open MongoDB Shell (mongosh)"
    echo "  eval <cmd> [db]            - Execute MongoDB command"
    echo "  list-db                    - List all databases"
    echo "  list-collections [db]      - List collections in database"
    echo "  create-db <name>           - Create new database"
    echo "  create-user <user> <pass> [db] [role] - Create new user"
    echo "  grant <user> <db> [role]   - Grant role to user"
    echo "  backup [db] [dir]          - Backup database"
    echo "  restore <file> <db>        - Restore database from backup"
    echo "  import <file> <db> <coll>  - Import JSON data"
    echo "  export <db> <coll> [file]  - Export collection to JSON"
    echo "  version                    - Show MongoDB version"
    echo "  stats                      - Show server statistics"
    echo "  help                       - Show this help message"
    echo
    echo "Environment Variables:"
    echo "  NAMESPACE - Kubernetes namespace (default: default)"
    echo
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 mongosh"
    echo "  $0 eval \"db.users.find()\" mydb"
    echo "  $0 create-db myapp"
    echo "  $0 create-user appuser mypassword myapp readWrite"
    echo "  $0 grant appuser myapp dbAdmin"
    echo "  $0 backup mydb ./backups"
    echo "  $0 import data.json mydb users"
    echo "  $0 export mydb users users.json"
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
            show_logs_cmd "${2:-50}" "${3:-false}"
            ;;
        mongosh|shell|cli)
            shift
            mongosh_cli "$@"
            ;;
        eval|exec|command)
            execute_command "$2" "$3"
            ;;
        list-db|databases)
            list_databases
            ;;
        list-collections|collections)
            list_collections "$2"
            ;;
        create-db|createdb)
            create_database "$2"
            ;;
        create-user|createuser)
            create_user "$2" "$3" "$4" "$5"
            ;;
        grant)
            grant_role "$2" "$3" "$4"
            ;;
        backup)
            backup_database "$2" "$3"
            ;;
        restore)
            restore_database "$2" "$3"
            ;;
        import)
            import_json "$2" "$3" "$4"
            ;;
        export)
            export_json "$2" "$3" "$4"
            ;;
        version)
            show_version
            ;;
        stats|statistics)
            show_stats
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
