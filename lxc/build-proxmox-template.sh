#!/bin/bash
#
# Automated SQLite-Web LXC Template Builder for Proxmox
# This script creates a complete, production-ready LXC template
#
# Usage:
#   bash build-proxmox-template.sh [options]
#
# Options:
#   --template-id <id>     Template container ID (default: 999)
#   --distro <name>        Distribution: debian or alpine (default: debian)
#   --version <ver>        Version number for template (default: 1.0)
#   --storage <name>       Storage location (default: local-lvm)
#   --clean                Remove existing template before building
#   --no-backup            Skip backup creation after build
#   --help                 Show this help message

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration defaults
TEMPLATE_ID="${TEMPLATE_ID:-999}"
DISTRO="${DISTRO:-debian}"
VERSION="${VERSION:-1.0}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
BUILD_DATE=$(date +%Y%m%d)
CLEAN_EXISTING=0
CREATE_BACKUP=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
Automated SQLite-Web LXC Template Builder for Proxmox

Usage: $0 [options]

Options:
    --template-id <id>     Template container ID (default: 999)
    --distro <name>        Distribution: debian or alpine (default: debian)
    --version <ver>        Version number for template (default: 1.0)
    --storage <name>       Storage for container rootfs (default: local-lvm)
    --template-storage <n> Storage for templates (default: local)
    --clean                Remove existing template before building
    --no-backup            Skip backup creation after build
    --help                 Show this help message

Examples:
    # Build default Debian template
    $0

    # Build Alpine template with custom ID
    $0 --template-id 9001 --distro alpine --version 2.0

    # Clean rebuild with backup
    $0 --clean

Environment Variables:
    TEMPLATE_ID            Same as --template-id
    DISTRO                 Same as --distro
    VERSION                Same as --version
    STORAGE                Same as --storage

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
        --distro)
            DISTRO="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --storage)
            STORAGE="$2"
            shift 2
            ;;
        --template-storage)
            TEMPLATE_STORAGE="$2"
            shift 2
            ;;
        --clean)
            CLEAN_EXISTING=1
            shift
            ;;
        --no-backup)
            CREATE_BACKUP=0
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

# Validate we're on Proxmox
if ! command -v pct &> /dev/null; then
    error "This script must be run on a Proxmox host (pct command not found)"
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
fi

# Validate distro
if [[ "$DISTRO" != "debian" && "$DISTRO" != "alpine" ]]; then
    error "Invalid distro: $DISTRO (must be 'debian' or 'alpine')"
fi

# Set distro-specific variables
if [[ "$DISTRO" == "debian" ]]; then
    TEMPLATE_NAME="sqlite-web-debian12"
    BASE_TEMPLATE="debian-12-standard"
    DISK_SIZE="4"
elif [[ "$DISTRO" == "alpine" ]]; then
    TEMPLATE_NAME="sqlite-web-alpine"
    BASE_TEMPLATE="alpine-3.18-default"
    DISK_SIZE="2"
fi

HOSTNAME="${TEMPLATE_NAME}-template"
DESCRIPTION="SQLite-Web v${VERSION} Template - ${DISTRO^} - Built ${BUILD_DATE}"

# Print configuration
step "Configuration"
info "Template ID:       $TEMPLATE_ID"
info "Distribution:      $DISTRO"
info "Version:           $VERSION"
info "Hostname:          $HOSTNAME"
info "Storage:           $STORAGE"
info "Base Template:     $BASE_TEMPLATE"
info "Build Date:        $BUILD_DATE"

# Check if template exists
if pct status $TEMPLATE_ID &>/dev/null; then
    if [ $CLEAN_EXISTING -eq 1 ]; then
        warn "Container $TEMPLATE_ID exists. Removing..."
        pct stop $TEMPLATE_ID --force 2>/dev/null || true
        sleep 2
        pct destroy $TEMPLATE_ID --purge
        info "Removed existing container $TEMPLATE_ID"
    else
        error "Container $TEMPLATE_ID already exists. Use --clean to remove it first."
    fi
fi

# Find base template
step "Finding base template"
TEMPLATE_FILE=$(pveam list $TEMPLATE_STORAGE | grep -i "$BASE_TEMPLATE" | head -n1 | awk '{print $1}')

if [ -z "$TEMPLATE_FILE" ]; then
    warn "Base template not found. Downloading..."
    # Try to download
    if [[ "$DISTRO" == "debian" ]]; then
        pveam download $TEMPLATE_STORAGE debian-12-standard_12.2-1_amd64.tar.zst || \
            error "Failed to download Debian template"
        TEMPLATE_FILE="${TEMPLATE_STORAGE}:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"
    else
        pveam download $TEMPLATE_STORAGE alpine-3.18-default_20230607_amd64.tar.xz || \
            error "Failed to download Alpine template"
        TEMPLATE_FILE="${TEMPLATE_STORAGE}:vztmpl/alpine-3.18-default_20230607_amd64.tar.xz"
    fi
fi

info "Using template: $TEMPLATE_FILE"

# Create container
step "Creating container"
pct create $TEMPLATE_ID $TEMPLATE_FILE \
    --hostname $HOSTNAME \
    --description "$DESCRIPTION" \
    --memory 512 \
    --swap 512 \
    --cores 1 \
    --rootfs ${STORAGE}:${DISK_SIZE} \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --unprivileged 1 \
    --features nesting=1 \
    --onboot 0

info "Container $TEMPLATE_ID created"

# Start container
step "Starting container"
pct start $TEMPLATE_ID

# Wait for container to be ready
info "Waiting for container to be ready..."
sleep 10

# Check if container is running
if ! pct status $TEMPLATE_ID | grep -q "running"; then
    error "Container failed to start"
fi

# Install software based on distro
step "Installing software"

if [[ "$DISTRO" == "debian" ]]; then
    info "Installing on Debian..."
    pct exec $TEMPLATE_ID -- bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update

echo "Upgrading existing packages..."
apt-get upgrade -y

echo "Installing system dependencies..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    build-essential \
    sqlite3 \
    libsqlite3-dev \
    curl \
    wget \
    vim \
    nano \
    htop \
    net-tools \
    systemd

echo "Upgrading pip..."
pip3 install --break-system-packages --upgrade pip

echo "Installing Python packages..."
pip3 install --break-system-packages --no-cache-dir \
    flask \
    peewee \
    pygments \
    python-dotenv \
    sqlite-web

echo "Creating directories..."
mkdir -p /data
mkdir -p /etc/sqlite-web
chmod 755 /data

echo "Software installation complete!"
'
else
    info "Installing on Alpine..."
    pct exec $TEMPLATE_ID -- sh -c '
set -e

echo "Updating package lists..."
apk update

echo "Upgrading existing packages..."
apk upgrade

echo "Installing system dependencies..."
apk add --no-cache \
    python3 \
    py3-pip \
    build-base \
    gcc \
    python3-dev \
    musl-dev \
    linux-headers \
    sqlite \
    sqlite-dev \
    curl \
    wget \
    vim \
    nano \
    htop \
    busybox-extras

echo "Upgrading pip..."
pip3 install --upgrade pip

echo "Installing Python packages..."
pip3 install --no-cache-dir \
    flask \
    peewee \
    pygments \
    python-dotenv \
    sqlite-web

echo "Creating directories..."
mkdir -p /data
mkdir -p /etc/sqlite-web
chmod 755 /data

echo "Cleaning up build dependencies..."
apk del build-base gcc python3-dev musl-dev linux-headers

echo "Software installation complete!"
'
fi

# Create systemd service file
step "Installing systemd service"

info "Creating service file..."
cat > /tmp/sqlite-web.service << 'EOF'
[Unit]
Description=SQLite Web Interface
Documentation=https://github.com/coleifer/sqlite-web
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/data

# Load configuration from environment file
EnvironmentFile=-/etc/default/sqlite-web

# Default values if not set in config
Environment="SQLITE_DATABASE=example.db"
Environment="LISTEN_HOST=0.0.0.0"
Environment="LISTEN_PORT=8080"
Environment="EXTRA_OPTIONS="

# Start sqlite-web
ExecStart=/usr/local/bin/sqlite_web \
    -H ${LISTEN_HOST} \
    -p ${LISTEN_PORT} \
    -x ${SQLITE_DATABASE} \
    ${EXTRA_OPTIONS}

# Restart policy
Restart=always
RestartSec=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sqlite-web

[Install]
WantedBy=multi-user.target
EOF

pct push $TEMPLATE_ID /tmp/sqlite-web.service /etc/systemd/system/sqlite-web.service
rm /tmp/sqlite-web.service

# Create default configuration
step "Creating default configuration"

pct exec $TEMPLATE_ID -- bash -c 'cat > /etc/default/sqlite-web << "CONFEOF"
# SQLite-Web Configuration
# Edit this file and restart service: systemctl restart sqlite-web

# Database file to open (relative to /data or absolute path)
SQLITE_DATABASE=example.db

# Listen address (0.0.0.0 for all interfaces, 127.0.0.1 for localhost only)
LISTEN_HOST=0.0.0.0

# Listen port (inside container)
LISTEN_PORT=8080

# Additional sqlite_web options (see: sqlite_web --help)
# Examples:
#   EXTRA_OPTIONS="--read-only"
#   EXTRA_OPTIONS="--password --require-login"
#   EXTRA_OPTIONS="--url-prefix /sqlite"
EXTRA_OPTIONS=""
CONFEOF'

# Enable service (but don't start)
info "Enabling service..."
pct exec $TEMPLATE_ID -- systemctl daemon-reload
pct exec $TEMPLATE_ID -- systemctl enable sqlite-web

# Create first-boot setup script
step "Creating first-boot setup script"

pct exec $TEMPLATE_ID -- bash -c 'cat > /usr/local/bin/sqlite-web-firstboot.sh << "SCRIPTEOF"
#!/bin/bash
# First boot setup script for sqlite-web containers

set -e

echo "=============================================="
echo "SQLite-Web First Boot Setup"
echo "=============================================="
echo ""

# Create example database if it doesn'\''t exist
if [ ! -f /data/example.db ]; then
    echo "Creating example database..."
    sqlite3 /data/example.db << '\''SQLEOF'\''
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    email TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (username, email) VALUES
    ('\''admin'\'', '\''admin@example.com'\''),
    ('\''demo'\'', '\''demo@example.com'\''),
    ('\''user1'\'', '\''user1@example.com'\'');

CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message TEXT NOT NULL,
    level TEXT DEFAULT '\''INFO'\'',
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO logs (message, level) VALUES
    ('\''SQLite-Web container initialized'\'', '\''INFO'\''),
    ('\''Example database created'\'', '\''INFO'\''),
    ('\''Ready for use'\'', '\''INFO'\'');

CREATE TABLE IF NOT EXISTS products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    price REAL,
    stock INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO products (name, price, stock) VALUES
    ('\''Widget A'\'', 19.99, 100),
    ('\''Widget B'\'', 29.99, 50),
    ('\''Widget C'\'', 39.99, 25);

-- Enable WAL mode for better concurrency
PRAGMA journal_mode=WAL;
SQLEOF

    chmod 644 /data/example.db
    echo "✓ Example database created at /data/example.db"
else
    echo "✓ Database already exists: /data/example.db"
fi

# Start service
echo ""
echo "Starting SQLite-Web service..."
systemctl start sqlite-web

# Wait a moment
sleep 3

# Check status
if systemctl is-active --quiet sqlite-web; then
    echo "✓ SQLite-Web is running"
    echo ""
    echo "=============================================="
    echo "Setup Complete!"
    echo "=============================================="
    echo ""
    echo "Access SQLite-Web at:"
    CONTAINER_IP=$(hostname -I | awk '\''{print $1}'\'')
    echo "  http://$CONTAINER_IP:8080"
    echo ""
    echo "Useful commands:"
    echo "  systemctl status sqlite-web    - Check service status"
    echo "  systemctl restart sqlite-web   - Restart service"
    echo "  journalctl -fu sqlite-web      - View logs"
    echo "  vim /etc/default/sqlite-web    - Edit configuration"
    echo "  ls -lh /data/                  - List databases"
    echo ""
    echo "Documentation: /root/README.txt"
    echo ""
else
    echo "✗ SQLite-Web failed to start"
    echo ""
    echo "Check logs with:"
    echo "  journalctl -u sqlite-web -n 50"
    echo ""
    exit 1
fi
SCRIPTEOF

chmod +x /usr/local/bin/sqlite-web-firstboot.sh'

# Create README
step "Creating documentation"

pct exec $TEMPLATE_ID -- bash -c 'cat > /root/README.txt << "READMEEOF"
==========================================
SQLite-Web LXC Container Template
==========================================

Version: '"$VERSION"'
Distribution: '"${DISTRO^}"'
Built: '"$BUILD_DATE"'

This container comes pre-installed with:
- SQLite 3 (latest)
- Python 3
- sqlite-web package
- Systemd service for sqlite-web

QUICK START:
------------

Run the first boot setup script:

    /usr/local/bin/sqlite-web-firstboot.sh

This will:
- Create an example database
- Start the SQLite-Web service
- Display the access URL

MANUAL START:
-------------

If you skip the first boot script:

    systemctl start sqlite-web

Access at: http://YOUR-CONTAINER-IP:8080

CONFIGURATION:
--------------

Edit configuration:
    vim /etc/default/sqlite-web

Available options:
    SQLITE_DATABASE   - Database file (relative to /data or absolute)
    LISTEN_HOST       - Listen address (0.0.0.0 or 127.0.0.1)
    LISTEN_PORT       - Listen port (default: 8080)
    EXTRA_OPTIONS     - Additional sqlite_web options

After editing, restart service:
    systemctl restart sqlite-web

UPLOAD YOUR DATABASE:
---------------------

From Proxmox host:
    pct push <CTID> /path/to/mydb.db /data/mydb.db

Or copy into container:
    scp mydb.db root@container-ip:/data/

Then update configuration:
    vim /etc/default/sqlite-web
    # Change: SQLITE_DATABASE=mydb.db
    systemctl restart sqlite-web

SECURITY OPTIONS:
-----------------

Read-only mode:
    EXTRA_OPTIONS="--read-only"

Password protection:
    EXTRA_OPTIONS="--password --require-login"

Custom URL prefix (for reverse proxy):
    EXTRA_OPTIONS="--url-prefix /sqlite"

USEFUL COMMANDS:
----------------

Service management:
    systemctl status sqlite-web     - Check status
    systemctl start sqlite-web      - Start service
    systemctl stop sqlite-web       - Stop service
    systemctl restart sqlite-web    - Restart service
    journalctl -fu sqlite-web       - View live logs
    journalctl -u sqlite-web -n 50  - Last 50 log lines

Database management:
    ls -lh /data/                   - List databases
    sqlite3 /data/mydb.db           - Open database
    sqlite3 /data/mydb.db .schema   - Show schema
    sqlite3 /data/mydb.db .dump > backup.sql  - Backup

Container management (from Proxmox host):
    pct start <CTID>                - Start container
    pct stop <CTID>                 - Stop container
    pct enter <CTID>                - Enter container
    pct exec <CTID> -- <command>    - Run command

TROUBLESHOOTING:
----------------

Service won'\''t start:
    journalctl -u sqlite-web -n 100
    # Check database file exists and is readable

Can'\''t connect:
    systemctl status sqlite-web
    netstat -tlnp | grep 8080
    # Check firewall settings

Database locked:
    sqlite3 /data/mydb.db "PRAGMA journal_mode=WAL;"
    # Enables Write-Ahead Logging for better concurrency

DOCUMENTATION:
--------------

SQLite-Web:  https://github.com/coleifer/sqlite-web
Proxmox LXC: https://pve.proxmox.com/wiki/Linux_Container

SUPPORT:
--------

For issues specific to this template, check the logs:
    journalctl -u sqlite-web

For SQLite-Web issues:
    https://github.com/coleifer/sqlite-web/issues

==========================================
READMEEOF'

# Create MOTD
step "Creating MOTD"

pct exec $TEMPLATE_ID -- bash -c 'cat > /etc/motd << "MOTDEOF"

  ___  ___  _    _ _         __        __   _
 / __|/ _ \| |  (_) |_ ___   \ \      / /__| |__
 \__ \ (_) | |__| | __/ _ \   \ \ /\ / / _ \ '\''_ \
 |___/\___/|____|_|\__\___/    \_V  V /  __/ |_) |
                                       \___|_.__/

 SQLite-Web Container (Template v'"$VERSION"')
 Distribution: '"${DISTRO^}"'

 Quick Start: /usr/local/bin/sqlite-web-firstboot.sh
 Documentation: /root/README.txt

 Service: systemctl status sqlite-web
 Logs:    journalctl -fu sqlite-web
 Config:  vim /etc/default/sqlite-web

MOTDEOF'

# Cleanup
step "Cleaning up container"

info "Removing temporary files and logs..."
pct exec $TEMPLATE_ID -- bash -c '
# Stop service (if running)
systemctl stop sqlite-web 2>/dev/null || true

# Clean package manager cache
if command -v apt-get &> /dev/null; then
    apt-get autoremove -y
    apt-get clean
    rm -rf /var/lib/apt/lists/*
elif command -v apk &> /dev/null; then
    rm -rf /var/cache/apk/*
fi

# Clean logs
journalctl --rotate 2>/dev/null || true
journalctl --vacuum-time=1s 2>/dev/null || true
rm -f /var/log/*.log
rm -f /var/log/*.old
rm -f /var/log/*.gz
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true

# Clean bash history
history -c 2>/dev/null || true
rm -f /root/.bash_history
rm -f /home/*/.bash_history 2>/dev/null || true

# Clean temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*
find /var/tmp -type f -delete 2>/dev/null || true

# Clean SSH host keys (will be regenerated on first boot)
rm -f /etc/ssh/ssh_host_*

# Clean machine-id (will be regenerated)
truncate -s 0 /etc/machine-id 2>/dev/null || true
rm -f /var/lib/dbus/machine-id 2>/dev/null || true

# Clean network persistent rules
rm -f /etc/udev/rules.d/70-persistent-net.rules 2>/dev/null || true

# Clean Python cache
find /usr -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find /usr -type f -name "*.pyc" -delete 2>/dev/null || true

# Empty /data (example database will be created on first boot)
rm -rf /data/* 2>/dev/null || true

echo "Cleanup complete!"
'

info "Cleanup complete"

# Stop container
step "Stopping container"
pct stop $TEMPLATE_ID

# Wait for clean shutdown
info "Waiting for clean shutdown..."
sleep 5

# Verify stopped
if pct status $TEMPLATE_ID | grep -q "running"; then
    warn "Container still running, forcing stop..."
    pct stop $TEMPLATE_ID --force
    sleep 3
fi

# Convert to template
step "Converting to template"
pct template $TEMPLATE_ID

info "Container $TEMPLATE_ID converted to template"

# Verify template
if pct config $TEMPLATE_ID | grep -q "template: 1"; then
    info "✓ Template verification passed"
else
    error "Template verification failed"
fi

# Create backup
if [ $CREATE_BACKUP -eq 1 ]; then
    step "Creating backup"
    BACKUP_DIR="/var/lib/vz/dump"
    mkdir -p $BACKUP_DIR

    info "Creating backup (this may take a moment)..."
    vzdump $TEMPLATE_ID \
        --mode stop \
        --compress zstd \
        --dumpdir $BACKUP_DIR

    # Find the backup file
    BACKUP_FILE=$(ls -t $BACKUP_DIR/vzdump-lxc-${TEMPLATE_ID}-*.tar.zst 2>/dev/null | head -n1)

    if [ -n "$BACKUP_FILE" ]; then
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        info "✓ Backup created: $BACKUP_FILE ($BACKUP_SIZE)"
    else
        warn "Backup file not found (may have failed)"
    fi
fi

# Summary
step "Build Complete!"

echo ""
info "=============================================="
info "SQLite-Web Template Successfully Created!"
info "=============================================="
echo ""
info "Template Details:"
info "  ID:           $TEMPLATE_ID"
info "  Name:         $HOSTNAME"
info "  Distribution: ${DISTRO^}"
info "  Version:      $VERSION"
info "  Build Date:   $BUILD_DATE"
echo ""
info "To create a new container from this template:"
echo ""
echo "  Via CLI:"
echo "    pct clone $TEMPLATE_ID 100 --hostname sqlite-web-prod"
echo "    pct start 100"
echo "    pct exec 100 -- /usr/local/bin/sqlite-web-firstboot.sh"
echo ""
echo "  Via Proxmox UI:"
echo "    1. Right-click template $TEMPLATE_ID"
echo "    2. Select 'Clone'"
echo "    3. Choose Full Clone"
echo "    4. Set new ID and hostname"
echo "    5. Start the container"
echo "    6. Run first-boot script"
echo ""

if [ $CREATE_BACKUP -eq 1 ] && [ -n "$BACKUP_FILE" ]; then
    info "Backup Location:"
    echo "    $BACKUP_FILE"
    echo ""
fi

info "Template is ready to use!"
info "=============================================="
echo ""
