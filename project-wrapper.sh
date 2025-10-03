#!/bin/bash
# Project Wrapper Framework for setup-minikube-env template
# Provides common functionality for project-specific setup scripts

# =============================================================================
# COMMON PROJECT WRAPPER FUNCTIONS
# =============================================================================

# Initialize project wrapper with configuration loading and validation
init_project_wrapper() {
    local script_dir="$1"
    local project_name="$2"

    # Set global variables
    SCRIPT_DIR="$script_dir"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

    # Load project-specific configuration
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        set -a
        source "$SCRIPT_DIR/.env"
        set +a
    else
        print_error "Project .env file not found at $SCRIPT_DIR/.env"
        print_info "Copy from template: cp ../setup-minikube-env/k8s/scripts/.env.example .env"
        exit 1
    fi

    # Resolve template path
    if [[ "$TEMPLATE_PATH" =~ ^\.\./ ]]; then
        TEMPLATE_FULL_PATH="$(cd "$SCRIPT_DIR/$TEMPLATE_PATH" && pwd)"
    else
        TEMPLATE_FULL_PATH="$TEMPLATE_PATH"
    fi

    # Validate template exists
    if [[ ! -d "$TEMPLATE_FULL_PATH" ]]; then
        print_error "Template repository not found at: $TEMPLATE_FULL_PATH"
        print_info "Please ensure setup-minikube-env is available at the specified path"
        print_info "Expected path in .env: TEMPLATE_PATH=\"$TEMPLATE_PATH\""
        exit 1
    fi

    # Validate template has required files
    if [[ ! -d "$TEMPLATE_FULL_PATH/k8s/scripts" ]]; then
        print_error "Invalid template: k8s/scripts/ directory not found in $TEMPLATE_FULL_PATH"
        exit 1
    fi

    # Source common utilities from template
    if [[ -f "$TEMPLATE_FULL_PATH/k8s/scripts/common.sh" ]]; then
        source "$TEMPLATE_FULL_PATH/k8s/scripts/common.sh"
    else
        echo "❌ Template common.sh not found"
        exit 1
    fi

    # Set project name if provided
    if [[ -n "$project_name" ]]; then
        PROJECT_NAME="$project_name"
    fi

    # Set namespace from project name
    NAMESPACE="${NAMESPACE:-${PROJECT_NAME}}"

    # Export configuration for template
    export_project_config
}

# Export project configuration to environment for template consumption
export_project_config() {
    export NAMESPACE
    export PROJECT_NAME
    export TEMPLATE_FULL_PATH

    # Export all non-comment lines from .env
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        export "$line"
    done < "$SCRIPT_DIR/.env"
}

# Parse and validate enabled services
parse_enabled_services() {
    if [[ -z "$ENABLED_SERVICES" ]]; then
        # Default to core services if not specified
        ENABLED_SERVICES=minio,spark,airflow
    fi

    # Convert comma-separated list to array
    IFS=',' read -ra ENABLED_SERVICES_ARRAY <<< "$ENABLED_SERVICES"

    # Validate that service scripts exist
    local missing_services=()
    for service in "${ENABLED_SERVICES_ARRAY[@]}"; do
        # Trim whitespace using bash parameter expansion
        service="${service#"${service%%[![:space:]]*}"}"
        service="${service%"${service##*[![:space:]]}"}"
        if [[ ! -f "$TEMPLATE_FULL_PATH/k8s/scripts/$service.sh" ]]; then
            missing_services+=("$service")
        fi
    done

    if [[ ${#missing_services[@]} -gt 0 ]]; then
        print_error "Missing service scripts: ${missing_services[*]}"
        print_info "Available services:"
        for script in "$TEMPLATE_FULL_PATH/k8s/scripts/"*.sh; do
            if [[ -f "$script" ]]; then
                local basename_script=$(basename "$script" .sh)
                if [[ "$basename_script" != "common" ]]; then
                    echo "  - $basename_script"
                fi
            fi
        done
        exit 1
    fi
}

# Start enabled services
start_enabled_services() {
    parse_enabled_services

    print_info "Starting services: ${ENABLED_SERVICES}"

    # Ensure minikube is running
    ensure_minikube_running || return 1

    # Create namespace if it doesn't exist
    create_namespace "$NAMESPACE" || return 1

    for service in "${ENABLED_SERVICES_ARRAY[@]}"; do
        # Trim whitespace using bash parameter expansion
        service="${service#"${service%%[![:space:]]*}"}"
        service="${service%"${service##*[![:space:]]}"}"
        print_info "Deploying $service..."
        if ! bash "$TEMPLATE_FULL_PATH/k8s/scripts/$service.sh" deploy; then
            print_error "Failed to deploy $service"
            return 1
        fi
    done

    print_success "All services started successfully"
}

# Stop enabled services
stop_enabled_services() {
    parse_enabled_services

    print_info "Stopping services: ${ENABLED_SERVICES}"

    # Stop in reverse order
    for ((i=${#ENABLED_SERVICES_ARRAY[@]}-1; i>=0; i--)); do
        service="${ENABLED_SERVICES_ARRAY[i]}"
        # Trim whitespace using bash parameter expansion
        service="${service#"${service%%[![:space:]]*}"}"
        service="${service%"${service##*[![:space:]]}"}"
        print_info "Removing $service..."
        bash "$TEMPLATE_FULL_PATH/k8s/scripts/$service.sh" remove
    done

    print_success "All services stopped"
}

# Show status of enabled services
show_enabled_services_status() {
    parse_enabled_services

    print_info "Service status for: ${ENABLED_SERVICES}"

    for service in "${ENABLED_SERVICES_ARRAY[@]}"; do
        # Trim whitespace using bash parameter expansion
        service="${service#"${service%%[![:space:]]*}"}"
        service="${service%"${service##*[![:space:]]}"}"
        echo
        print_info "=== $service Status ==="
        bash "$TEMPLATE_FULL_PATH/k8s/scripts/$service.sh" status
    done
}

# Delegate command to template service scripts with proper error handling
delegate_to_template() {
    local command="$1"
    shift

    # Execute service command directly
    case "$command" in
        postgres|minio|spark|airflow|dremio)
            if [[ -f "$TEMPLATE_FULL_PATH/k8s/scripts/$command.sh" ]]; then
                bash "$TEMPLATE_FULL_PATH/k8s/scripts/$command.sh" "$@"
            else
                print_error "Service script not found: $command.sh"
                exit 1
            fi
            ;;
        logs)
            # Handle logs command for specific service
            local service="$1"
            if [[ -n "$service" && -f "$TEMPLATE_FULL_PATH/k8s/scripts/$service.sh" ]]; then
                bash "$TEMPLATE_FULL_PATH/k8s/scripts/$service.sh" logs "${@:2}"
            else
                print_error "Service not specified or script not found: $service"
                return 1
            fi
            ;;
        *)
            print_error "Unknown template command: $command"
            return 1
            ;;
    esac
}

# Standard project status display
show_standard_project_status() {
    local project_title="$1"

    print_header "📊 ${project_title} ENVIRONMENT STATUS"

    # Show Minikube status
    echo
    print_info "Minikube Status:"
    minikube status

    echo
    print_info "Minikube IP: $(get_minikube_ip)"

    # Show enabled services status
    show_enabled_services_status

    echo
    print_color "$BLUE" "🎯 Project Configuration:"
    echo "  Project: ${PROJECT_NAME:-Unknown}"
    echo "  Namespace: ${NAMESPACE:-default}"
    echo "  Template: $TEMPLATE_FULL_PATH"
    echo "  Description: ${PROJECT_DESCRIPTION:-No description}"
    echo "  Enabled Services: ${ENABLED_SERVICES:-minio,spark,airflow}"
}

# Standard usage display with customizable sections
show_standard_usage() {
    local script_name="$1"
    local project_title="$2"

    echo "Usage: $script_name {start|stop|restart|status|logs|minikube} [service]"
    echo
    echo "Environment Commands:"
    echo "  start     - Start Minikube and deploy enabled services"
    echo "  stop      - Remove all enabled services"
    echo "  restart   - Restart all enabled services"
    echo "  status    - Show current status"
    echo "  logs      - Show logs for [service]"
    echo
    echo "Minikube Commands:"
    echo "  minikube start   - Start Minikube cluster"
    echo "  minikube stop    - Stop Minikube cluster"
    echo "  minikube delete  - Delete Minikube cluster"
    echo "  minikube status  - Show Minikube status"
    echo "  minikube ip      - Show Minikube IP"
    echo
    echo "Individual Service Control:"
    echo "  postgres {deploy|remove|status|logs}"
    echo "  minio {deploy|remove|status|logs|console}"
    echo "  spark {deploy|remove|status|logs|scale|ui}"
    echo "  airflow {deploy|remove|status|logs|cli|ui}"
    echo "  dremio {deploy|remove|status|logs|ui}"
    echo
    echo "Configuration:"
    echo "  Template: $TEMPLATE_FULL_PATH"
    echo "  Project: ${PROJECT_NAME:-Unknown}"
    echo "  Namespace: ${NAMESPACE:-default}"
    echo "  Enabled Services: ${ENABLED_SERVICES:-minio,spark,airflow}"
}

# Validate required tools and dependencies
validate_environment() {
    validate_tools
}

# Restart all enabled services
restart_enabled_services() {
    parse_enabled_services

    print_info "Restarting services: ${ENABLED_SERVICES}"

    for service in "${ENABLED_SERVICES_ARRAY[@]}"; do
        # Trim whitespace using bash parameter expansion
        service="${service#"${service%%[![:space:]]*}"}"
        service="${service%"${service##*[![:space:]]}"}"
        print_info "Restarting $service..."
        bash "$TEMPLATE_FULL_PATH/k8s/scripts/$service.sh" restart
    done

    print_success "All services restarted"
}

# Handle Minikube commands
handle_minikube_command() {
    local cmd="$1"

    case "$cmd" in
        start)
            ensure_minikube_running
            ;;
        stop)
            print_info "Stopping Minikube..."
            minikube stop
            ;;
        delete)
            print_warning "This will delete the Minikube cluster and all data!"
            read -p "Are you sure? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                minikube delete
            fi
            ;;
        status)
            minikube status
            ;;
        ip)
            get_minikube_ip
            ;;
        dashboard)
            minikube dashboard
            ;;
        *)
            print_error "Unknown minikube command: $cmd"
            echo "Available: start, stop, delete, status, ip, dashboard"
            return 1
            ;;
    esac
}

# Standard main function that projects can customize
standard_main() {
    local project_title="$1"
    shift
    local script_name="$(basename "${BASH_SOURCE[1]}")"

    print_header "🎯 ${project_title} ENVIRONMENT"

    # Validate environment
    validate_environment

    case "${1:-status}" in
        start|deploy)
            start_enabled_services
            ;;
        stop|remove)
            stop_enabled_services
            ;;
        restart)
            restart_enabled_services
            ;;
        status)
            show_standard_project_status "$project_title"
            ;;
        logs)
            shift
            if [[ -n "$1" ]]; then
                # Show logs for specific service
                delegate_to_template logs "$@"
            else
                # Show logs for all enabled services
                parse_enabled_services
                for service in "${ENABLED_SERVICES_ARRAY[@]}"; do
                    # Trim whitespace using bash parameter expansion
                    service="${service#"${service%%[![:space:]]*}"}"
                    service="${service%"${service##*[![:space:]]}"}"
                    echo
                    print_info "=== $service Logs ==="
                    bash "$TEMPLATE_FULL_PATH/k8s/scripts/$service.sh" logs
                done
            fi
            ;;
        minikube)
            shift
            handle_minikube_command "${1:-status}"
            ;;
        postgres|minio|spark|airflow|dremio)
            # Direct service control - delegate to template
            delegate_to_template "$@"
            ;;
        help|--help|-h)
            show_standard_usage "$script_name" "$project_title"
            ;;
        *)
            print_error "Unknown command: $1"
            show_standard_usage "$script_name" "$project_title"
            exit 1
            ;;
    esac
}

# =============================================================================
# PROJECT TEMPLATE GENERATOR
# =============================================================================

# Generate a new project setup script
generate_project_setup() {
    local project_name="$1"
    local project_description="$2"
    local target_dir="$3"

    if [[ -z "$project_name" || -z "$target_dir" ]]; then
        echo "Usage: generate_project_setup <project_name> <description> <target_dir>"
        return 1
    fi

    # Create target directory
    mkdir -p "$target_dir"

    # Generate .env file
    cat > "$target_dir/.env" << EOF
# =============================================================================
# ${project_name} Environment Configuration
# =============================================================================

# Project Configuration
PROJECT_NAME="${project_name}"
PROJECT_DESCRIPTION="${project_description:-${project_name} Environment}"

# Template Repository Path (adjust as needed)
TEMPLATE_PATH="../setup-minikube-env"

# Kubernetes Configuration
NAMESPACE="\${PROJECT_NAME}"

# Service Selection - Choose what you need
ENABLED_SERVICES="minio,spark,airflow"
# Other combinations:
# ENABLED_SERVICES="minio,spark"          # Storage + processing
# ENABLED_SERVICES="minio,airflow"        # Storage + orchestration
# ENABLED_SERVICES="spark,airflow"        # Processing + orchestration

# =============================================================================
# MINIKUBE CONFIGURATION
# =============================================================================

# Minikube resource allocation
MINIKUBE_CPUS="4"
MINIKUBE_MEMORY="8192"
MINIKUBE_DISK_SIZE="20g"
MINIKUBE_DRIVER="docker"

# =============================================================================
# SERVICE-SPECIFIC CONFIGURATION
# =============================================================================

# MinIO
MINIO_STORAGE_SIZE="5Gi"

# Spark
SPARK_WORKER_REPLICAS="2"
SPARK_WORKER_MEMORY="1G"
SPARK_WORKER_CORES="1"

# Airflow
AIRFLOW_ADMIN_USER="admin"
AIRFLOW_ADMIN_PASSWORD="admin"

# =============================================================================
# DEVELOPMENT FLAGS
# =============================================================================
DEVELOPMENT_MODE="true"
VERBOSE_LOGGING="false"
EOF

    # Generate setup-env.sh script
    cat > "$target_dir/setup-env.sh" << 'EOF'
#!/bin/bash
# PROJECT_NAME Environment Setup
# Leverages setup-minikube-env template with project-specific configuration

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Load template path from .env
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
else
    echo "❌ .env file not found"
    exit 1
fi

# Source the project wrapper framework
TEMPLATE_DIR="$SCRIPT_DIR/$TEMPLATE_PATH"
if [[ -f "$TEMPLATE_DIR/project-wrapper.sh" ]]; then
    source "$TEMPLATE_DIR/project-wrapper.sh"
else
    echo "❌ Project wrapper not found at $TEMPLATE_DIR/project-wrapper.sh"
    echo "💡 Please ensure setup-minikube-env template is available"
    exit 1
fi

# Initialize project wrapper
init_project_wrapper "$SCRIPT_DIR" "PROJECT_NAME"

# Use standard main function with project customizations
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    standard_main "PROJECT_NAME" "$@"
fi
EOF

    # Replace placeholders
    sed -i.bak "s/PROJECT_NAME/${project_name}/g" "$target_dir/setup-env.sh" && rm "$target_dir/setup-env.sh.bak"

    # Make executable
    chmod +x "$target_dir/setup-env.sh"

    print_success "Generated project setup for '$project_name' in $target_dir"
    print_info "Files created:"
    echo "  - $target_dir/.env"
    echo "  - $target_dir/setup-env.sh"
    echo ""
    print_info "Usage:"
    echo "  cd $target_dir"
    echo "  ./setup-env.sh start"
}

# =============================================================================
# HELP FUNCTIONS
# =============================================================================

show_wrapper_usage() {
    echo "Project Wrapper Framework for setup-minikube-env"
    echo
    echo "Usage:"
    echo "  source project-wrapper.sh"
    echo "  init_project_wrapper \"\$SCRIPT_DIR\" \"project-name\""
    echo "  standard_main \"Project Title\" \"\$@\""
    echo
    echo "Generator:"
    echo "  ./project-wrapper.sh generate <name> <description> <target_dir>"
    echo
    echo "Available Functions:"
    echo "  - init_project_wrapper: Initialize project configuration"
    echo "  - delegate_to_template: Execute template commands"
    echo "  - show_standard_project_status: Display project status"
    echo "  - show_standard_usage: Display usage information"
    echo "  - validate_environment: Check required tools"
    echo "  - standard_main: Standard main function"
}

# If called directly, handle generator command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Source common.sh for print functions if available
    if [[ -f "$(dirname "${BASH_SOURCE[0]}")/k8s/scripts/common.sh" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/k8s/scripts/common.sh"
    fi

    case "${1:-help}" in
        generate)
            generate_project_setup "$2" "$3" "$4"
            ;;
        *)
            show_wrapper_usage
            ;;
    esac
fi
