#!/bin/bash
#
# Bulk Deploy SQLite-Web Containers
# Deploy multiple containers from template in one go
#
# Usage:
#   bash bulk-deploy.sh --count <n> [options]
#
# Options:
#   --count <n>            Number of containers to create (required)
#   --template-id <id>     Source template ID (default: 999)
#   --start-id <id>        Starting container ID (default: 100)
#   --prefix <name>        Hostname prefix (default: sqlite-web)
#   --memory <MB>          Memory per container (default: 512)
#   --cores <n>            CPU cores per container (default: 1)
#   --start-port <port>    Starting port number (default: 8080)
#   --storage <name>       Storage location (default: local-lvm)
#   --parallel <n>         Max parallel deployments (default: 3)
#   --init                 Run first-boot script on all (default: yes)
#   --no-init              Skip first-boot script
#   --help                 Show this help message

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
COUNT=0
TEMPLATE_ID="${TEMPLATE_ID:-999}"
START_ID="${START_ID:-100}"
PREFIX="${PREFIX:-sqlite-web}"
MEMORY="${MEMORY:-512}"
CORES="${CORES:-1}"
START_PORT="${START_PORT:-8080}"
STORAGE="${STORAGE:-local-lvm}"
MAX_PARALLEL="${MAX_PARALLEL:-3}"
RUN_INIT=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Track deployments
declare -a DEPLOYED_IDS=()
declare -a FAILED_IDS=()

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
Bulk Deploy SQLite-Web Containers from Template

Usage: $0 --count <n> [options]

Required:
    --count <n>            Number of containers to create

Options:
    --template-id <id>     Source template ID (default: 999)
    --start-id <id>        Starting container ID (default: 100)
    --prefix <name>        Hostname prefix (default: sqlite-web)
    --memory <MB>          Memory per container (default: 512)
    --cores <n>            CPU cores per container (default: 1)
    --start-port <port>    Starting port number (default: 8080)
    --storage <name>       Storage location (default: local-lvm)
    --parallel <n>         Max parallel deployments (default: 3)
    --init                 Run first-boot script on all (default: yes)
    --no-init              Skip first-boot script
    --help                 Show this help message

Examples:
    # Deploy 5 containers
    $0 --count 5

    # Deploy 10 with custom settings
    $0 --count 10 --start-id 200 --memory 1024 --cores 2

    # Deploy for load balancing
    $0 --count 3 --prefix webapp --start-port 8080

Container Naming:
    Containers will be named: <prefix>-<id>
    Example: sqlite-web-100, sqlite-web-101, ...

Port Assignment:
    Each container gets sequential port:
    Container 100: port 8080
    Container 101: port 8081
    Container 102: port 8082
    ...

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --count)
            COUNT="$2"
            shift 2
            ;;
        --template-id)
            TEMPLATE_ID="$2"
            shift 2
            ;;
        --start-id)
            START_ID="$2"
            shift 2
            ;;
        --prefix)
            PREFIX="$2"
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
        --start-port)
            START_PORT="$2"
            shift 2
            ;;
        --storage)
            STORAGE="$2"
            shift 2
            ;;
        --parallel)
            MAX_PARALLEL="$2"
            shift 2
            ;;
        --init)
            RUN_INIT=1
            shift
            ;;
        --no-init)
            RUN_INIT=0
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
if [ "$COUNT" -le 0 ]; then
    error "Count must be greater than 0. Use --count <n>"
fi

if ! command -v pct &> /dev/null; then
    error "This script must be run on a Proxmox host"
fi

if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
fi

# Check template exists
if ! pct status $TEMPLATE_ID &>/dev/null; then
    error "Template $TEMPLATE_ID not found"
fi

if ! pct config $TEMPLATE_ID | grep -q "template: 1"; then
    error "Container $TEMPLATE_ID is not a template"
fi

# Check for conflicts
info "Checking for existing containers..."
for i in $(seq 0 $((COUNT - 1))); do
    CTID=$((START_ID + i))
    if pct status $CTID &>/dev/null; then
        error "Container $CTID already exists. Choose a different start ID."
    fi
done
info "✓ No conflicts found"

# Print plan
step "Deployment Plan"
info "Template:          $TEMPLATE_ID"
info "Containers:        $COUNT"
info "ID Range:          $START_ID - $((START_ID + COUNT - 1))"
info "Hostname Pattern:  ${PREFIX}-<id>"
info "Memory per VM:     ${MEMORY}MB"
info "CPU per VM:        ${CORES} cores"
info "Port Range:        $START_PORT - $((START_PORT + COUNT - 1))"
info "Storage:           $STORAGE"
info "Max Parallel:      $MAX_PARALLEL"
info "Run Init Script:   $([ $RUN_INIT -eq 1 ] && echo 'Yes' || echo 'No')"
echo ""

# Confirm
read -p "Proceed with deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Deployment cancelled"
    exit 0
fi

# Deploy function
deploy_container() {
    local ctid=$1
    local index=$2
    local hostname="${PREFIX}-${ctid}"
    local port=$((START_PORT + index))

    info "[$ctid] Deploying $hostname..."

    # Clone
    if pct clone $TEMPLATE_ID $ctid \
        --hostname "$hostname" \
        --description "SQLite-Web instance $index (bulk deployment)" \
        --storage "$STORAGE" \
        --full &>/tmp/deploy-${ctid}.log; then

        # Adjust resources
        pct set $ctid --memory $MEMORY --cores $CORES &>>/tmp/deploy-${ctid}.log

        # Start
        if pct start $ctid &>>/tmp/deploy-${ctid}.log; then
            sleep 5

            # Run init if requested
            if [ $RUN_INIT -eq 1 ]; then
                if pct exec $ctid -- /usr/local/bin/sqlite-web-firstboot.sh &>>/tmp/deploy-${ctid}.log; then
                    # Get IP
                    local ip=$(pct exec $ctid -- hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
                    info "[$ctid] ✓ Success - $hostname - IP: $ip - Port: $port"
                    return 0
                else
                    warn "[$ctid] Started but init failed"
                    return 1
                fi
            else
                local ip=$(pct exec $ctid -- hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
                info "[$ctid] ✓ Success - $hostname - IP: $ip"
                return 0
            fi
        else
            warn "[$ctid] Failed to start"
            return 1
        fi
    else
        warn "[$ctid] Failed to clone"
        return 1
    fi
}

# Deploy with parallelism
step "Deploying Containers"

ACTIVE_JOBS=0
declare -a PIDS=()

for i in $(seq 0 $((COUNT - 1))); do
    CTID=$((START_ID + i))

    # Wait if we hit max parallel
    while [ $ACTIVE_JOBS -ge $MAX_PARALLEL ]; do
        # Check for finished jobs
        for pid in "${PIDS[@]}"; do
            if ! kill -0 $pid 2>/dev/null; then
                wait $pid
                ACTIVE_JOBS=$((ACTIVE_JOBS - 1))
            fi
        done
        sleep 1
    done

    # Deploy in background
    deploy_container $CTID $i &
    PIDS+=($!)
    ACTIVE_JOBS=$((ACTIVE_JOBS + 1))

    sleep 2  # Stagger starts
done

# Wait for all to complete
info "Waiting for all deployments to complete..."
wait

# Collect results
step "Verifying Deployments"

SUCCESSFUL=0
FAILED=0

for i in $(seq 0 $((COUNT - 1))); do
    CTID=$((START_ID + i))

    if pct status $CTID &>/dev/null && pct status $CTID | grep -q "running"; then
        if pct exec $CTID -- systemctl is-active --quiet sqlite-web 2>/dev/null; then
            DEPLOYED_IDS+=($CTID)
            SUCCESSFUL=$((SUCCESSFUL + 1))
        else
            FAILED_IDS+=($CTID)
            FAILED=$((FAILED + 1))
            warn "Container $CTID running but service not active"
        fi
    else
        FAILED_IDS+=($CTID)
        FAILED=$((FAILED + 1))
    fi
done

# Summary
step "Deployment Summary"

echo ""
info "=============================================="
info "Bulk Deployment Complete!"
info "=============================================="
echo ""
info "Total Requested:   $COUNT"
info "Successful:        $SUCCESSFUL"
info "Failed:            $FAILED"
echo ""

if [ ${#DEPLOYED_IDS[@]} -gt 0 ]; then
    info "Successfully Deployed Containers:"
    for ctid in "${DEPLOYED_IDS[@]}"; do
        hostname=$(pct exec $ctid -- hostname 2>/dev/null || echo "unknown")
        ip=$(pct exec $ctid -- hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
        echo "    [$ctid] $hostname - http://$ip:8080"
    done
    echo ""
fi

if [ ${#FAILED_IDS[@]} -gt 0 ]; then
    warn "Failed Deployments:"
    for ctid in "${FAILED_IDS[@]}"; do
        echo "    [$ctid] - Check log: /tmp/deploy-${ctid}.log"
    done
    echo ""
fi

# Management examples
if [ $SUCCESSFUL -gt 0 ]; then
    info "Management Commands:"
    echo ""
    echo "  Start all:"
    echo "    for id in ${DEPLOYED_IDS[@]}; do pct start \$id; done"
    echo ""
    echo "  Stop all:"
    echo "    for id in ${DEPLOYED_IDS[@]}; do pct stop \$id; done"
    echo ""
    echo "  Check status:"
    echo "    for id in ${DEPLOYED_IDS[@]}; do pct status \$id; done"
    echo ""
    echo "  View logs:"
    echo "    for id in ${DEPLOYED_IDS[@]}; do echo \"=== \$id ===\";"
    echo "    pct exec \$id -- journalctl -u sqlite-web -n 10; done"
    echo ""
fi

# Cleanup temp logs
info "Cleaning up temporary logs..."
rm -f /tmp/deploy-*.log

echo ""
info "=============================================="
echo ""

exit $([ $FAILED -eq 0 ] && echo 0 || echo 1)
