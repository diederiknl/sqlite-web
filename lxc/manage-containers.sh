#!/bin/bash
#
# SQLite-Web Container Management Script
# Centralized management for all SQLite-Web containers
#
# Usage:
#   bash manage-containers.sh <command> [options]
#
# Commands:
#   list              List all SQLite-Web containers
#   status            Show detailed status of containers
#   start <ids>       Start containers (all or specific IDs)
#   stop <ids>        Stop containers (all or specific IDs)
#   restart <ids>     Restart containers (all or specific IDs)
#   logs <id>         View logs for specific container
#   update <ids>      Update sqlite-web in containers
#   backup <ids>      Backup containers
#   cleanup           Remove stopped containers
#   monitor           Real-time monitoring dashboard
#   help              Show this help message

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

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

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

# Check if on Proxmox
if ! command -v pct &> /dev/null; then
    error "This script must be run on a Proxmox host"
fi

# Get all SQLite-Web containers (by hostname pattern)
get_sqlite_containers() {
    pct list | tail -n +2 | while read -r line; do
        ctid=$(echo "$line" | awk '{print $1}')
        hostname=$(pct exec $ctid -- hostname 2>/dev/null || echo "")
        if [[ "$hostname" == *"sqlite-web"* ]] || [[ "$hostname" == *"sqlite"* ]]; then
            echo "$ctid"
        fi
    done
}

# Parse container IDs
parse_ids() {
    local input="$1"

    if [[ "$input" == "all" ]]; then
        get_sqlite_containers
    elif [[ "$input" == *"-"* ]]; then
        # Range: 100-105
        local start=$(echo "$input" | cut -d'-' -f1)
        local end=$(echo "$input" | cut -d'-' -f2)
        seq "$start" "$end"
    elif [[ "$input" == *","* ]]; then
        # List: 100,101,102
        echo "$input" | tr ',' '\n'
    else
        # Single ID
        echo "$input"
    fi
}

# List command
cmd_list() {
    echo ""
    echo -e "${BLUE}SQLite-Web Containers${NC}"
    echo "================================================================"
    printf "%-6s %-20s %-15s %-10s %-20s\n" "ID" "Hostname" "IP" "Status" "Service"
    echo "================================================================"

    local containers=$(get_sqlite_containers)

    if [ -z "$containers" ]; then
        echo "No SQLite-Web containers found"
        return
    fi

    for ctid in $containers; do
        local hostname=$(pct exec $ctid -- hostname 2>/dev/null || echo "unknown")
        local ip=$(pct exec $ctid -- hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")
        local status=$(pct status $ctid | awk '{print $2}')

        local service_status="N/A"
        if [[ "$status" == "running" ]]; then
            if pct exec $ctid -- systemctl is-active --quiet sqlite-web 2>/dev/null; then
                service_status="${GREEN}active${NC}"
            else
                service_status="${RED}inactive${NC}"
            fi
        else
            service_status="${YELLOW}stopped${NC}"
        fi

        printf "%-6s %-20s %-15s %-10s %-20b\n" "$ctid" "$hostname" "$ip" "$status" "$service_status"
    done

    echo "================================================================"
    echo ""
}

# Status command
cmd_status() {
    local containers=$(get_sqlite_containers)

    if [ -z "$containers" ]; then
        warn "No SQLite-Web containers found"
        return
    fi

    for ctid in $containers; do
        echo ""
        echo -e "${BLUE}=== Container $ctid ===${NC}"

        local hostname=$(pct exec $ctid -- hostname 2>/dev/null || echo "unknown")
        local ip=$(pct exec $ctid -- hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")
        local status=$(pct status $ctid | awk '{print $2}')
        local config=$(pct config $ctid)
        local memory=$(echo "$config" | grep "^memory:" | awk '{print $2}')
        local cores=$(echo "$config" | grep "^cores:" | awk '{print $2}')

        echo "Hostname:      $hostname"
        echo "IP Address:    $ip"
        echo "Status:        $status"
        echo "Memory:        ${memory}MB"
        echo "CPU Cores:     $cores"

        if [[ "$status" == "running" ]]; then
            echo -n "Service:       "
            if pct exec $ctid -- systemctl is-active --quiet sqlite-web 2>/dev/null; then
                echo -e "${GREEN}active${NC}"
                echo "URL:           http://$ip:8080"

                # Database info
                local db=$(pct exec $ctid -- grep "^SQLITE_DATABASE=" /etc/default/sqlite-web 2>/dev/null | cut -d'=' -f2 || echo "unknown")
                echo "Database:      $db"

                # Uptime
                local uptime=$(pct exec $ctid -- systemctl show sqlite-web -p ActiveEnterTimestamp --value 2>/dev/null)
                if [ -n "$uptime" ]; then
                    echo "Service Since: $uptime"
                fi
            else
                echo -e "${RED}inactive${NC}"
            fi

            # Resource usage
            echo -n "CPU Usage:     "
            pct exec $ctid -- top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}'

            echo -n "Memory Usage:  "
            pct exec $ctid -- free -m | awk 'NR==2{printf "%.1f%%\n", $3*100/$2 }'

            echo -n "Disk Usage:    "
            pct exec $ctid -- df -h / | awk 'NR==2{print $5}'
        fi
    done
    echo ""
}

# Start command
cmd_start() {
    local ids=$(parse_ids "$1")

    echo ""
    info "Starting containers..."

    for ctid in $ids; do
        if pct status $ctid &>/dev/null; then
            if pct status $ctid | grep -q "running"; then
                warn "Container $ctid already running"
            else
                echo -n "Starting $ctid... "
                pct start $ctid
                sleep 3
                success "Container $ctid started"
            fi
        else
            warn "Container $ctid not found"
        fi
    done
    echo ""
}

# Stop command
cmd_stop() {
    local ids=$(parse_ids "$1")

    echo ""
    info "Stopping containers..."

    for ctid in $ids; do
        if pct status $ctid &>/dev/null; then
            if pct status $ctid | grep -q "stopped"; then
                warn "Container $ctid already stopped"
            else
                echo -n "Stopping $ctid... "
                pct stop $ctid
                success "Container $ctid stopped"
            fi
        else
            warn "Container $ctid not found"
        fi
    done
    echo ""
}

# Restart command
cmd_restart() {
    local ids=$(parse_ids "$1")

    echo ""
    info "Restarting containers..."

    for ctid in $ids; do
        if pct status $ctid &>/dev/null; then
            echo -n "Restarting $ctid... "
            pct stop $ctid 2>/dev/null || true
            sleep 2
            pct start $ctid
            sleep 3
            success "Container $ctid restarted"
        else
            warn "Container $ctid not found"
        fi
    done
    echo ""
}

# Logs command
cmd_logs() {
    local ctid="$1"

    if [ -z "$ctid" ]; then
        error "Container ID required. Usage: $0 logs <id>"
    fi

    if ! pct status $ctid &>/dev/null; then
        error "Container $ctid not found"
    fi

    echo ""
    info "Showing logs for container $ctid (Ctrl+C to exit)..."
    echo ""
    pct exec $ctid -- journalctl -fu sqlite-web
}

# Update command
cmd_update() {
    local ids=$(parse_ids "$1")

    echo ""
    info "Updating sqlite-web in containers..."

    for ctid in $ids; do
        if ! pct status $ctid &>/dev/null; then
            warn "Container $ctid not found"
            continue
        fi

        if ! pct status $ctid | grep -q "running"; then
            warn "Container $ctid not running, skipping"
            continue
        fi

        echo ""
        info "Updating container $ctid..."

        pct exec $ctid -- bash << 'EOF'
echo "Current version:"
pip3 show sqlite-web | grep Version

echo "Updating..."
pip3 install --upgrade sqlite-web

echo "New version:"
pip3 show sqlite-web | grep Version

echo "Restarting service..."
systemctl restart sqlite-web

echo "Checking service..."
systemctl is-active sqlite-web && echo "✓ Service is running" || echo "✗ Service failed"
EOF

        success "Container $ctid updated"
    done
    echo ""
}

# Backup command
cmd_backup() {
    local ids=$(parse_ids "$1")
    local backup_dir="/var/lib/vz/dump"

    echo ""
    info "Backing up containers to $backup_dir..."

    for ctid in $ids; do
        if ! pct status $ctid &>/dev/null; then
            warn "Container $ctid not found"
            continue
        fi

        echo ""
        info "Backing up container $ctid..."

        vzdump $ctid --mode snapshot --compress zstd --dumpdir "$backup_dir"

        local backup_file=$(ls -t $backup_dir/vzdump-lxc-${ctid}-*.tar.zst 2>/dev/null | head -n1)
        if [ -n "$backup_file" ]; then
            local size=$(du -h "$backup_file" | cut -f1)
            success "Backup created: $backup_file ($size)"
        else
            warn "Backup failed for container $ctid"
        fi
    done
    echo ""
}

# Cleanup command
cmd_cleanup() {
    echo ""
    info "Finding stopped SQLite-Web containers..."

    local containers=$(get_sqlite_containers)
    local stopped=()

    for ctid in $containers; do
        if pct status $ctid | grep -q "stopped"; then
            stopped+=($ctid)
        fi
    done

    if [ ${#stopped[@]} -eq 0 ]; then
        info "No stopped containers found"
        return
    fi

    echo ""
    warn "Found ${#stopped[@]} stopped containers: ${stopped[*]}"
    echo ""
    read -p "Remove these containers? (y/N) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled"
        return
    fi

    for ctid in "${stopped[@]}"; do
        echo -n "Removing container $ctid... "
        pct destroy $ctid
        success "Container $ctid removed"
    done
    echo ""
}

# Monitor command
cmd_monitor() {
    while true; do
        clear
        echo -e "${BLUE}SQLite-Web Containers Monitor${NC}"
        echo -e "${CYAN}Updated: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
        echo ""

        cmd_list

        echo ""
        echo "Press Ctrl+C to exit, refreshing in 5 seconds..."
        sleep 5
    done
}

# Help command
cmd_help() {
    cat << EOF

SQLite-Web Container Management Script

Usage: $0 <command> [options]

Commands:
    list                  List all SQLite-Web containers
    status                Show detailed status of containers
    start <ids>           Start containers (all, single, range, or list)
    stop <ids>            Stop containers
    restart <ids>         Restart containers
    logs <id>             View logs for specific container
    update <ids>          Update sqlite-web package in containers
    backup <ids>          Backup containers
    cleanup               Remove stopped containers
    monitor               Real-time monitoring dashboard
    help                  Show this help message

Container ID Formats:
    all                   All SQLite-Web containers
    100                   Single container
    100-105               Range of containers
    100,101,102           Comma-separated list

Examples:
    # List all containers
    $0 list

    # Show detailed status
    $0 status

    # Start all containers
    $0 start all

    # Start specific containers
    $0 start 100-105
    $0 start 100,101,102

    # Stop container
    $0 stop 100

    # View logs
    $0 logs 100

    # Update all containers
    $0 update all

    # Backup specific containers
    $0 backup 100-105

    # Monitor in real-time
    $0 monitor

    # Cleanup stopped containers
    $0 cleanup

EOF
}

# Main
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
    list)
        cmd_list
        ;;
    status)
        cmd_status
        ;;
    start)
        cmd_start "${1:-all}"
        ;;
    stop)
        cmd_stop "${1:-all}"
        ;;
    restart)
        cmd_restart "${1:-all}"
        ;;
    logs)
        cmd_logs "$1"
        ;;
    update)
        cmd_update "${1:-all}"
        ;;
    backup)
        cmd_backup "${1:-all}"
        ;;
    cleanup)
        cmd_cleanup
        ;;
    monitor)
        cmd_monitor
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        error "Unknown command: $COMMAND\nUse '$0 help' for usage information"
        ;;
esac
