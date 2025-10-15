#!/bin/bash
#
# SQLite-Web LXC Container Setup Script
# This script automates the complete setup of sqlite-web in an LXC container
#

set -e

# Configuration
CONTAINER_NAME="${CONTAINER_NAME:-sqlite-web}"
DISTRO="${DISTRO:-alpine}"
VERSION="${VERSION:-3.18}"
PORT="${PORT:-8080}"
DATA_PATH="${DATA_PATH:-/var/lib/sqlite-web}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
fi

# Check if LXC is installed
if ! command -v lxc &> /dev/null; then
    error "LXC is not installed. Please install lxd first: sudo snap install lxd"
fi

info "Starting sqlite-web LXC setup..."
info "Container name: $CONTAINER_NAME"
info "Distribution: $DISTRO/$VERSION"
info "Port: $PORT"

# Check if container already exists
if lxc info "$CONTAINER_NAME" &> /dev/null; then
    warn "Container '$CONTAINER_NAME' already exists"
    read -p "Do you want to delete and recreate it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Stopping and deleting existing container..."
        lxc stop "$CONTAINER_NAME" --force 2>/dev/null || true
        lxc delete "$CONTAINER_NAME"
    else
        error "Aborted. Please use a different container name."
    fi
fi

# Create container
info "Creating LXC container..."
lxc launch "images:$DISTRO/$VERSION" "$CONTAINER_NAME"

# Wait for container to be ready
info "Waiting for container to be ready..."
sleep 5
lxc exec "$CONTAINER_NAME" -- sh -c "while [ ! -f /var/lib/cloud/instance/boot-finished ] 2>/dev/null; do sleep 1; done" || sleep 5

# Detect if Alpine or Debian-based
if [[ "$DISTRO" == "alpine" ]]; then
    info "Setting up Alpine-based container..."

    lxc exec "$CONTAINER_NAME" -- sh -c '
        set -e

        echo "Updating package index..."
        apk update

        echo "Installing system dependencies..."
        apk add --no-cache python3 py3-pip build-base gcc python3-dev \
                musl-dev linux-headers wget tar tcl-dev sqlite sqlite-dev

        echo "Upgrading pip..."
        pip3 install --upgrade pip

        echo "Installing Python packages..."
        pip3 install --no-cache-dir flask peewee pygments python-dotenv sqlite-web

        echo "Creating data directory..."
        mkdir -p /data
        chmod 755 /data

        echo "Cleaning up build dependencies..."
        apk del build-base gcc python3-dev musl-dev linux-headers tcl-dev
    '

else
    info "Setting up Debian-based container..."

    lxc exec "$CONTAINER_NAME" -- bash -c '
        set -e

        echo "Updating package index..."
        apt-get update

        echo "Installing system dependencies..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            python3 python3-pip python3-dev build-essential \
            wget libsqlite3-dev sqlite3

        echo "Upgrading pip..."
        pip3 install --upgrade pip

        echo "Installing Python packages..."
        pip3 install --no-cache-dir flask peewee pygments python-dotenv sqlite-web

        echo "Creating data directory..."
        mkdir -p /data
        chmod 755 /data

        echo "Cleaning up..."
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    '
fi

# Copy systemd service file
info "Installing systemd service..."
lxc file push "$(dirname "$0")/sqlite-web.service" "$CONTAINER_NAME/etc/systemd/system/sqlite-web.service"

# Create default config
info "Creating default configuration..."
lxc exec "$CONTAINER_NAME" -- sh -c "cat > /etc/default/sqlite-web << 'EOF'
# SQLite-Web Configuration
# Database file to open (relative to /data or absolute path)
SQLITE_DATABASE=example.db

# Listen address (0.0.0.0 for all interfaces)
LISTEN_HOST=0.0.0.0

# Listen port
LISTEN_PORT=8080

# Additional options (see sqlite_web --help)
# Example: EXTRA_OPTIONS=\"--read-only --no-browser\"
EXTRA_OPTIONS=\"\"
EOF"

# Enable and start service
info "Enabling sqlite-web service..."
lxc exec "$CONTAINER_NAME" -- systemctl daemon-reload
lxc exec "$CONTAINER_NAME" -- systemctl enable sqlite-web

# Setup port forwarding
info "Setting up port forwarding..."
if lxc config device show "$CONTAINER_NAME" | grep -q "web-port"; then
    lxc config device remove "$CONTAINER_NAME" web-port
fi
lxc config device add "$CONTAINER_NAME" web-port proxy \
    listen=tcp:0.0.0.0:$PORT \
    connect=tcp:127.0.0.1:8080

# Setup data volume (if path provided)
if [ -d "$DATA_PATH" ]; then
    info "Mounting data directory: $DATA_PATH"
    if lxc config device show "$CONTAINER_NAME" | grep -q "data-volume"; then
        lxc config device remove "$CONTAINER_NAME" data-volume
    fi
    lxc config device add "$CONTAINER_NAME" data-volume disk \
        source="$DATA_PATH" \
        path=/data
fi

# Create example database
info "Creating example database..."
lxc exec "$CONTAINER_NAME" -- sqlite3 /data/example.db "
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (username, email) VALUES
    ('admin', 'admin@example.com'),
    ('demo', 'demo@example.com');
"

# Start service
info "Starting sqlite-web service..."
lxc exec "$CONTAINER_NAME" -- systemctl start sqlite-web

# Wait a bit for service to start
sleep 3

# Check service status
if lxc exec "$CONTAINER_NAME" -- systemctl is-active --quiet sqlite-web; then
    info "✓ Service is running"
else
    warn "Service may not be running properly. Check logs with:"
    echo "  lxc exec $CONTAINER_NAME -- journalctl -u sqlite-web -n 50"
fi

# Get container IP
CONTAINER_IP=$(lxc list "$CONTAINER_NAME" -c 4 | grep eth0 | awk '{print $1}')

echo ""
info "=========================================="
info "SQLite-Web LXC Setup Complete!"
info "=========================================="
echo ""
info "Container: $CONTAINER_NAME"
info "Access URL: http://localhost:$PORT"
if [ -n "$CONTAINER_IP" ]; then
    info "Container IP: http://$CONTAINER_IP:8080"
fi
echo ""
info "Useful commands:"
echo "  Start:   lxc start $CONTAINER_NAME"
echo "  Stop:    lxc stop $CONTAINER_NAME"
echo "  Shell:   lxc exec $CONTAINER_NAME -- sh"
echo "  Logs:    lxc exec $CONTAINER_NAME -- journalctl -fu sqlite-web"
echo "  Restart: lxc exec $CONTAINER_NAME -- systemctl restart sqlite-web"
echo ""
info "Configuration file: /etc/default/sqlite-web (in container)"
info "Data directory: /data (in container)"
echo ""
info "To upload a database:"
echo "  lxc file push mydb.db $CONTAINER_NAME/data/"
echo ""
