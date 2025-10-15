#!/bin/bash
#
# Deploy SQLite-Web Container from Template
# Quick deployment script for creating containers from the template
#
# Usage:
#   bash deploy-from-template.sh [options]
#
# Options:
#   --template-id <id>     Source template ID (default: 999)
#   --container-id <id>    New container ID (required)
#   --hostname <name>      Container hostname (default: sqlite-web-<id>)
#   --database <file>      Database file to upload (optional)
#   --storage <name>       Storage location (default: local-lvm)
#   --memory <MB>          Memory in MB (default: 512)
#   --cores <n>            CPU cores (default: 1)
#   --port <port>          Host port for access (default: 8080)
#   --full-clone           Use full clone instead of linked (default: full)
#   --start                Start container after creation (default: yes)
#   --init                 Run first-boot script automatically (default: yes)
#   --help                 Show this help message

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
TEMPLATE_ID="${TEMPLATE_ID:-999}"
CONTAINER_ID=""
HOSTNAME=""
DATABASE_FILE=""
STORAGE="${STORAGE:-local-lvm}"
MEMORY="${MEMORY:-512}"
CORES="${CORES:-1}"
PORT="${PORT:-8080}"
FULL_CLONE=1
START_CONTAINER=1
RUN_INIT=1

# Functions
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

step() {
    echo -e "\n${BLUE}==>${NC} ${BLUE}$1${NC}\n"
}

usage() {
    cat << EOF
Deploy SQLite-Web Container from Template

Usage: $0 --container-id <id> [options]

Required:
    --container-id <id>    New container ID

Options:
    --template-id <id>     Source template ID (default: 999)
    --hostname <name>      Container hostname (default: sqlite-web-<id>)
    --database <file>      Database file to upload (optional)
    --storage <name>       Storage location (default: local-lvm)
    --memory <MB>          Memory in MB (default: 512)
    --cores <n>            CPU cores (default: 1)
    --port <port>          Host port for access (default: 8080)
    --full-clone           Use full clone (default, independent)
    --linked-clone         Use linked clone (faster, depends on template)
    --no-start             Don't start container after creation
    --no-init              Don't run first-boot script
    --help                 Show this help message

Examples:
    # Simple deployment
    $0 --container-id 100

    # Custom hostname and resources
    $0 --container-id 101 --hostname prod-db --memory 1024 --cores 2

    # Deploy with existing database
    $0 --container-id 102 --database /path/to/mydata.db

    # Deploy multiple (in a loop)
    for i in {100..105}; do
        $0 --container-id \$i --hostname sqlite-web-\$i --port \$((8080+i-100))
    done

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --template-id)
            TEMPLATE_ID="$2"
            shift 2
            ;;
        --container-id)
            CONTAINER_ID="$2"
            shift 2
            ;;
        --hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        --database)
            DATABASE_FILE="$2"
            shift 2
            ;;
        --storage)
            STORAGE="$2"
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --cores)
            CORES="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --full-clone)
            FULL_CLONE=1
            shift
            ;;
        --linked-clone)
            FULL_CLONE=0
            shift
            ;;
        --no-start)
            START_CONTAINER=0
            shift
            ;;
        --no-init)
            RUN_INIT=0
            shift
            ;;
        --start)
            START_CONTAINER=1
            shift
            ;;
        --init)
            RUN_INIT=1
            shift
            ;;
        --help)
            usage
            ;;
        *)
            error "Unknown option: $1\nUse --help for usage information"
            ;;
    esac
done

# Validate
if [ -z "$CONTAINER_ID" ]; then
    error "Container ID is required. Use --container-id <id>"
fi

if ! command -v pct &> /dev/null; then
    error "This script must be run on a Proxmox host"
fi

if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
fi

# Set default hostname if not provided
if [ -z "$HOSTNAME" ]; then
    HOSTNAME="sqlite-web-${CONTAINER_ID}"
fi

# Check if template exists
if ! pct status $TEMPLATE_ID &>/dev/null; then
    error "Template $TEMPLATE_ID not found. Create it first with build-proxmox-template.sh"
fi

# Verify it's actually a template
if ! pct config $TEMPLATE_ID | grep -q "template: 1"; then
    error "Container $TEMPLATE_ID is not a template"
fi

# Check if target container ID exists
if pct status $CONTAINER_ID &>/dev/null; then
    error "Container $CONTAINER_ID already exists"
fi

# Check database file if provided
if [ -n "$DATABASE_FILE" ] && [ ! -f "$DATABASE_FILE" ]; then
    error "Database file not found: $DATABASE_FILE"
fi

# Print configuration
step "Deployment Configuration"
info "Template ID:       $TEMPLATE_ID"
info "Container ID:      $CONTAINER_ID"
info "Hostname:          $HOSTNAME"
info "Storage:           $STORAGE"
info "Memory:            ${MEMORY}MB"
info "CPU Cores:         $CORES"
info "Port:              $PORT"
info "Clone Type:        $([ $FULL_CLONE -eq 1 ] && echo 'Full' || echo 'Linked')"
info "Auto Start:        $([ $START_CONTAINER -eq 1 ] && echo 'Yes' || echo 'No')"
info "Run Init Script:   $([ $RUN_INIT -eq 1 ] && echo 'Yes' || echo 'No')"
[ -n "$DATABASE_FILE" ] && info "Database Upload:   $DATABASE_FILE"

# Clone container
step "Cloning container from template"

CLONE_ARGS="--hostname $HOSTNAME --description 'SQLite-Web instance cloned from template $TEMPLATE_ID' --storage $STORAGE"

if [ $FULL_CLONE -eq 1 ]; then
    CLONE_ARGS="$CLONE_ARGS --full"
fi

info "Creating container $CONTAINER_ID..."
pct clone $TEMPLATE_ID $CONTAINER_ID $CLONE_ARGS

# Wait a moment
sleep 2

# Adjust resources if different from defaults
if [ "$MEMORY" != "512" ] || [ "$CORES" != "1" ]; then
    step "Adjusting resources"
    pct set $CONTAINER_ID --memory $MEMORY --cores $CORES
    info "Resources updated: ${MEMORY}MB RAM, ${CORES} CPU cores"
fi

# Configure port forwarding (optional, commented by default)
# Uncomment if you want automatic port forwarding from host to container
# step "Configuring port forwarding"
# pct set $CONTAINER_ID -net0 name=eth0,bridge=vmbr0,firewall=1,ip=dhcp

# Start container if requested
if [ $START_CONTAINER -eq 1 ]; then
    step "Starting container"
    pct start $CONTAINER_ID

    info "Waiting for container to be ready..."
    sleep 10

    # Verify running
    if ! pct status $CONTAINER_ID | grep -q "running"; then
        error "Container failed to start"
    fi

    info "✓ Container is running"

    # Get container IP
    CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I 2>/dev/null | awk '{print $1}' || echo "")

    if [ -n "$CONTAINER_IP" ]; then
        info "Container IP: $CONTAINER_IP"
    fi
fi

# Upload database if provided
if [ -n "$DATABASE_FILE" ]; then
    step "Uploading database"

    DB_BASENAME=$(basename "$DATABASE_FILE")
    info "Uploading $DB_BASENAME to container..."

    pct push $CONTAINER_ID "$DATABASE_FILE" "/data/$DB_BASENAME"

    # Update configuration to use this database
    info "Updating configuration to use $DB_BASENAME..."
    pct exec $CONTAINER_ID -- sed -i "s/^SQLITE_DATABASE=.*/SQLITE_DATABASE=$DB_BASENAME/" /etc/default/sqlite-web

    info "✓ Database uploaded and configured"
fi

# Run init script if requested
if [ $RUN_INIT -eq 1 ] && [ $START_CONTAINER -eq 1 ]; then
    step "Running first-boot initialization"

    info "Executing first-boot script..."
    pct exec $CONTAINER_ID -- /usr/local/bin/sqlite-web-firstboot.sh

    info "✓ Initialization complete"
fi

# Final status check
if [ $START_CONTAINER -eq 1 ]; then
    step "Verifying deployment"

    sleep 3

    # Check if service is running
    if pct exec $CONTAINER_ID -- systemctl is-active --quiet sqlite-web; then
        info "✓ SQLite-Web service is running"
    else
        warn "Service may not be running. Check with:"
        echo "    pct exec $CONTAINER_ID -- systemctl status sqlite-web"
    fi

    # Get IP again (in case it changed)
    CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I 2>/dev/null | awk '{print $1}' || echo "")
fi

# Summary
step "Deployment Complete!"

echo ""
info "=============================================="
info "Container Successfully Deployed!"
info "=============================================="
echo ""
info "Container Details:"
info "  ID:         $CONTAINER_ID"
info "  Hostname:   $HOSTNAME"
info "  Memory:     ${MEMORY}MB"
info "  CPU Cores:  $CORES"

if [ -n "$CONTAINER_IP" ]; then
    info "  IP Address: $CONTAINER_IP"
fi

if [ $START_CONTAINER -eq 1 ]; then
    echo ""
    info "Access SQLite-Web:"
    if [ -n "$CONTAINER_IP" ]; then
        echo "    http://$CONTAINER_IP:8080"
    fi
    echo ""
    info "Useful Commands:"
    echo "    pct enter $CONTAINER_ID                              - Enter container"
    echo "    pct exec $CONTAINER_ID -- systemctl status sqlite-web - Check status"
    echo "    pct exec $CONTAINER_ID -- journalctl -fu sqlite-web   - View logs"
    echo "    pct stop $CONTAINER_ID                                - Stop container"
    echo "    pct start $CONTAINER_ID                               - Start container"
else
    echo ""
    info "Container created but not started. Start with:"
    echo "    pct start $CONTAINER_ID"
    echo "    pct exec $CONTAINER_ID -- /usr/local/bin/sqlite-web-firstboot.sh"
fi

echo ""
info "Configuration:"
echo "    Edit: pct exec $CONTAINER_ID -- vim /etc/default/sqlite-web"
echo "    Restart: pct exec $CONTAINER_ID -- systemctl restart sqlite-web"

if [ -n "$DATABASE_FILE" ]; then
    echo ""
    info "Database: /data/$(basename "$DATABASE_FILE")"
fi

echo ""
info "=============================================="
echo ""
