# LXC Template Aanmaken in Proxmox

Een LXC template maken in Proxmox stelt je in staat om een pre-geconfigureerde container te hergebruiken voor snelle deployments. Deze guide laat zien hoe je een SQLite-Web template maakt.

## Inhoudsopgave

1. [Wat is een LXC Template?](#wat-is-een-lxc-template)
2. [Methode A: Container naar Template Converteren](#methode-a-container-naar-template-converteren)
3. [Methode B: Custom Template Bouwen](#methode-b-custom-template-bouwen)
4. [Methode C: Turnkey Template Gebruiken](#methode-c-turnkey-template-gebruiken)
5. [Template Gebruiken](#template-gebruiken)
6. [Best Practices](#best-practices)

## Wat is een LXC Template?

Een LXC template in Proxmox is een basis image waaruit je nieuwe containers kunt maken. Er zijn twee soorten:

1. **Basis templates** - Standaard OS images (Debian, Ubuntu, Alpine, etc.)
2. **Custom templates** - Zelf gemaakte templates met pre-geïnstalleerde software

### Voordelen van Custom Templates:

- **Snelle deployment**: Container is binnen seconden operationeel
- **Consistentie**: Alle containers zijn identiek geconfigureerd
- **Automatisering**: Ideaal voor CI/CD en testing
- **Backup**: Template dient als golden image

## Methode A: Container naar Template Converteren

Dit is de makkelijkste methode: bouw een perfecte container en converteer deze.

### Stap 1: Maak en configureer een container

Start met een schone container:

```bash
# Op Proxmox host
CTID=999  # Gebruik een hoog ID voor templates
pct create $CTID local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
    --hostname sqlite-web-template \
    --memory 512 \
    --cores 1 \
    --rootfs local-lvm:4 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --unprivileged 1

pct start $CTID
```

### Stap 2: Installeer en configureer alles

```bash
pct exec $CTID -- bash << 'EOF'
# Update systeem
apt update && apt upgrade -y

# Installeer dependencies
apt install -y \
    python3 \
    python3-pip \
    python3-dev \
    build-essential \
    sqlite3 \
    libsqlite3-dev \
    curl \
    wget \
    vim \
    systemctl

# Upgrade pip
pip3 install --upgrade pip

# Installeer sqlite-web en dependencies
pip3 install --no-cache-dir \
    flask \
    peewee \
    pygments \
    python-dotenv \
    sqlite-web

# Maak directories
mkdir -p /data
mkdir -p /etc/sqlite-web

# Cleanup
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /root/.cache
EOF
```

### Stap 3: Installeer systemd service

```bash
# Upload service file
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

pct push $CTID /tmp/sqlite-web.service /etc/systemd/system/sqlite-web.service
```

### Stap 4: Maak default configuratie

```bash
pct exec $CTID -- bash << 'EOF'
cat > /etc/default/sqlite-web << 'CONFEOF'
# SQLite-Web Configuration
# Edit this file and restart service: systemctl restart sqlite-web

SQLITE_DATABASE=example.db
LISTEN_HOST=0.0.0.0
LISTEN_PORT=8080
EXTRA_OPTIONS=""
CONFEOF

# Enable service (maar start niet!)
systemctl daemon-reload
systemctl enable sqlite-web
EOF
```

### Stap 5: Maak setup script voor eerste boot

Dit script wordt uitgevoerd wanneer een nieuwe container van de template wordt gemaakt:

```bash
pct exec $CTID -- bash << 'EOF'
cat > /usr/local/bin/sqlite-web-firstboot.sh << 'SCRIPTEOF'
#!/bin/bash
# First boot setup script for sqlite-web containers

set -e

echo "Running SQLite-Web first boot setup..."

# Maak example database als die niet bestaat
if [ ! -f /data/example.db ]; then
    echo "Creating example database..."
    sqlite3 /data/example.db << 'SQLEOF'
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (username, email) VALUES
    ('admin', 'admin@example.com'),
    ('demo', 'demo@example.com');

CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message TEXT,
    level TEXT DEFAULT 'INFO',
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO logs (message, level) VALUES
    ('SQLite-Web container started', 'INFO'),
    ('Example database initialized', 'INFO');
SQLEOF
    echo "Example database created at /data/example.db"
fi

# Start service
systemctl start sqlite-web

# Check status
sleep 2
if systemctl is-active --quiet sqlite-web; then
    echo "✓ SQLite-Web is running"
    echo "Access at: http://$(hostname -I | awk '{print $1}'):8080"
else
    echo "✗ SQLite-Web failed to start. Check logs:"
    echo "  journalctl -u sqlite-web -n 50"
fi

echo "First boot setup complete!"
SCRIPTEOF

chmod +x /usr/local/bin/sqlite-web-firstboot.sh
EOF
```

### Stap 6: Maak README in de container

```bash
pct exec $CTID -- bash << 'EOF'
cat > /root/README.txt << 'READMEEOF'
==========================================
SQLite-Web LXC Container Template
==========================================

This container comes pre-installed with:
- SQLite 3
- Python 3
- sqlite-web package
- Systemd service for sqlite-web

QUICK START:
------------

1. Run first boot setup:
   /usr/local/bin/sqlite-web-firstboot.sh

2. Or manually start service:
   systemctl start sqlite-web

3. Access the web interface:
   http://YOUR-CONTAINER-IP:8080

CONFIGURATION:
--------------

Edit: /etc/default/sqlite-web
Then: systemctl restart sqlite-web

UPLOAD DATABASE:
----------------

1. Copy your database to /data/
2. Update SQLITE_DATABASE in /etc/default/sqlite-web
3. Restart: systemctl restart sqlite-web

USEFUL COMMANDS:
----------------

Service status:    systemctl status sqlite-web
View logs:         journalctl -fu sqlite-web
Restart service:   systemctl restart sqlite-web
Check databases:   ls -lh /data/

DOCUMENTATION:
--------------

SQLite-Web: https://github.com/coleifer/sqlite-web
Support: https://github.com/your-repo/sqlite-web

==========================================
READMEEOF
EOF
```

### Stap 7: Cleanup en voorbereiden voor template

**Belangrijk**: Verwijder alle host-specifieke data!

```bash
pct exec $CTID -- bash << 'EOF'
# Stop alle services
systemctl stop sqlite-web || true

# Cleanup logs
journalctl --rotate
journalctl --vacuum-time=1s
rm -rf /var/log/*.log
rm -rf /var/log/*/*.log
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.old" -delete

# Cleanup bash history
history -c
rm -f /root/.bash_history
rm -f /home/*/.bash_history

# Cleanup temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Cleanup SSH keys (worden regenerated bij eerste boot)
rm -f /etc/ssh/ssh_host_*

# Cleanup machine-id (wordt regenerated)
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Cleanup network config (voor DHCP)
rm -f /etc/udev/rules.d/70-persistent-net.rules

# Cleanup APT cache
apt clean
rm -rf /var/lib/apt/lists/*

# Cleanup Python cache
find /usr -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find /usr -type f -name "*.pyc" -delete 2>/dev/null || true

# Leeg /data directory (wordt gevuld bij eerste boot)
rm -f /data/*

echo "Cleanup complete - container ready for template conversion"
EOF
```

### Stap 8: Stop container en converteer naar template

```bash
# Stop de container
pct stop $CTID

# Wacht tot volledig gestopt
sleep 5

# Converteer naar template
pct template $CTID
```

**Let op**: Na conversie kun je deze container NIET meer starten. Het is nu een read-only template.

### Stap 9: Verifieer de template

```bash
# Check template status
pct status $CTID
# Output: "status: stopped" + "template: 1"

# Bekijk configuratie
pct config $CTID | grep template
# Output: "template: 1"
```

## Methode B: Custom Template Bouwen

Deze methode is voor gevorderde gebruikers die volledige controle willen.

### Stap 1: Download basis template

```bash
# Login op Proxmox host

# Kies je basis OS
# Alpine (kleinst, ~50MB)
pveam download local alpine-3.18-default_20230607_amd64.tar.xz

# Debian (aanbevolen, ~120MB)
pveam download local debian-12-standard_12.2-1_amd64.tar.zst

# Ubuntu
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst
```

### Stap 2: Maak custom template directory

```bash
# Maak workspace
mkdir -p /tmp/sqlite-web-template
cd /tmp/sqlite-web-template

# Extract basis template
TEMPLATE="/var/lib/vz/template/cache/debian-12-standard_12.2-1_amd64.tar.zst"
mkdir rootfs
cd rootfs
tar -xf $TEMPLATE
```

### Stap 3: Chroot en installeer software

```bash
# Mount benodigde directories
mount -t proc proc proc/
mount -t sysfs sys sys/
mount --bind /dev dev/
mount --bind /dev/pts dev/pts/

# Chroot
chroot . /bin/bash

# Nu ben je in de container
apt update
apt install -y python3-pip sqlite3
pip3 install sqlite-web flask peewee pygments python-dotenv

# Configureer zoals in Methode A

# Exit chroot
exit

# Unmount
umount dev/pts
umount dev
umount sys
umount proc
```

### Stap 4: Maak tarball

```bash
cd /tmp/sqlite-web-template
tar -czf /var/lib/vz/template/cache/sqlite-web-custom_1.0_amd64.tar.gz -C rootfs .

# Cleanup
rm -rf /tmp/sqlite-web-template
```

Deze methode is complexer maar geeft volledige controle over de template.

## Methode C: Turnkey Template Gebruiken

Turnkey heeft pre-built templates, maar niet voor sqlite-web. Je zou kunnen starten met hun basis template:

```bash
# Download Turnkey Core
pveam download local turnkeylinux-core-18.0-bookworm-amd64.tar.gz

# Maak container
pct create 100 local:vztmpl/turnkeylinux-core-18.0-bookworm-amd64.tar.gz \
    --hostname sqlite-web

# Configureer zoals gewoonlijk
```

## Template Gebruiken

### Nieuwe container van template maken

**Via Proxmox UI:**

1. Rechtermuisklik op de template (CTID 999)
2. Klik **Clone**
3. Configureer:
   - Target Node: (zelfde of andere node)
   - VM ID: (nieuw ID, bijv. 100)
   - Hostname: sqlite-web-prod
   - Mode: **Full Clone** (aanbevolen) of Linked Clone
4. Klik **Clone**

**Via CLI:**

```bash
# Full clone (onafhankelijke kopie)
pct clone 999 100 \
    --hostname sqlite-web-prod \
    --description "Production SQLite-Web instance"

# Linked clone (sneller, maar afhankelijk van template)
pct clone 999 100 \
    --hostname sqlite-web-prod \
    --snapname __base__

# Start de nieuwe container
pct start 100

# Run first boot setup (indien je dat script hebt gemaakt)
pct exec 100 -- /usr/local/bin/sqlite-web-firstboot.sh
```

### Bulk deployment

Maak meerdere containers tegelijk:

```bash
#!/bin/bash
# bulk-deploy.sh

TEMPLATE_ID=999
BASE_ID=100

for i in {1..5}; do
    CTID=$((BASE_ID + i))
    echo "Creating container $CTID..."

    pct clone $TEMPLATE_ID $CTID \
        --hostname sqlite-web-$i \
        --description "SQLite-Web instance $i"

    pct start $CTID

    echo "Container $CTID created and started"
done

echo "Deployed 5 containers!"
```

### Container customizen na deployment

```bash
# Unieke configuratie per container
CTID=100
DATABASE_NAME="production.db"

pct exec $CTID -- bash << EOF
# Update database configuratie
sed -i "s/SQLITE_DATABASE=.*/SQLITE_DATABASE=$DATABASE_NAME/" /etc/default/sqlite-web

# Restart service
systemctl restart sqlite-web
EOF

# Upload database
pct push $CTID /path/to/production.db /data/production.db
```

## Best Practices

### 1. Template Naming Convention

Gebruik duidelijke namen:

```bash
# Format: <app>-<version>-<os>-<date>
CTID=999  # of 9999 voor templates
Hostname: sqlite-web-template-1.0-debian12-20241015

# In Proxmox UI: voeg description toe
pct set 999 --description "SQLite-Web v1.0 - Debian 12 - Built $(date +%Y-%m-%d)"
```

### 2. Template Versioning

Houd meerdere versies:

```bash
# Template v1.0
CTID: 9001
Hostname: sqlite-web-template-1.0

# Template v2.0 (met updates)
CTID: 9002
Hostname: sqlite-web-template-2.0

# Test nieuwe versie voordat je oude verwijdert
```

### 3. Security Hardening

Voor productie templates:

```bash
pct exec $CTID -- bash << 'EOF'
# Disable root login via SSH
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Automatic security updates
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# Firewall
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 8080/tcp
# ufw enable  # Activeer na eerste boot, niet in template!

# Fail2ban (optioneel)
apt install -y fail2ban
EOF
```

### 4. Gebruik Cloud-Init (optioneel)

Voor advanced automation:

```bash
# Installeer cloud-init in template
pct exec $CTID -- apt install -y cloud-init

# Bij deployment gebruik je dan:
pct set 100 --ciuser admin --cipassword strongpassword
```

### 5. Template Testing

Test altijd je template voordat je in productie gebruikt:

```bash
#!/bin/bash
# test-template.sh

TEMPLATE_ID=999
TEST_ID=9999

echo "Testing template $TEMPLATE_ID..."

# Clone voor test
pct clone $TEMPLATE_ID $TEST_ID --hostname test-sqlite-web

# Start
pct start $TEST_ID
sleep 10

# Test service
if pct exec $TEST_ID -- systemctl is-active sqlite-web; then
    echo "✓ Service test PASSED"
else
    echo "✗ Service test FAILED"
fi

# Test web endpoint
CONTAINER_IP=$(pct exec $TEST_ID -- hostname -I | awk '{print $1}')
if curl -s http://$CONTAINER_IP:8080 > /dev/null; then
    echo "✓ Web endpoint test PASSED"
else
    echo "✗ Web endpoint test FAILED"
fi

# Cleanup
pct stop $TEST_ID
pct destroy $TEST_ID

echo "Template test complete!"
```

### 6. Documentatie in Template

Voeg altijd documentatie toe:

```bash
pct exec $CTID -- bash << 'EOF'
cat > /etc/motd << 'MOTD'
  ___  ___  _    _ _         __        __   _
 / __|/ _ \| |  (_) |_ ___   \ \      / /__| |__
 \__ \ (_) | |__| | __/ _ \   \ \ /\ / / _ \ '_ \
 |___/\___/|____|_|\__\___/    \_V  V /  __/ |_) |
                                       \___|_.__/

SQLite-Web Container (from template)

Quick commands:
  systemctl status sqlite-web    - Check service status
  journalctl -fu sqlite-web      - View logs
  vim /etc/default/sqlite-web    - Edit config
  ls /data/                      - List databases

Documentation: /root/README.txt
MOTD
EOF
```

## Template Beheer

### Template info bekijken

```bash
# Alle templates
pct list | grep -E "template.*1"

# Specifieke template info
pct config 999

# Disk usage
du -sh /var/lib/vz/images/999
```

### Template updaten

Je kunt een template niet direct updaten. In plaats daarvan:

```bash
# Methode 1: Maak nieuwe versie
# 1. Clone de oude template
pct clone 999 998 --hostname sqlite-web-template-update
# 2. Start en update
pct start 998
pct exec 998 -- apt update && apt upgrade -y
pct exec 998 -- pip3 install --upgrade sqlite-web
# 3. Cleanup en converteer
pct stop 998
pct template 998
# 4. Hernoem: 998 wordt nieuwe template, 999 is backup

# Methode 2: Rebuild vanaf scratch
# Volg Methode A opnieuw met updates
```

### Template exporteren

Voor backup of om te delen:

```bash
# Backup template
vzdump 999 --mode stop --compress zstd --dumpdir /var/lib/vz/dump

# Output: /var/lib/vz/dump/vzdump-lxc-999-<timestamp>.tar.zst

# Kopieer naar andere host
scp /var/lib/vz/dump/vzdump-lxc-999-*.tar.zst user@other-proxmox:/var/lib/vz/dump/

# Restore op andere host
pct restore 999 /var/lib/vz/dump/vzdump-lxc-999-*.tar.zst
```

### Template delen via HTTP

```bash
# Setup web server (op Proxmox host)
apt install -y nginx

# Symlink templates directory
ln -s /var/lib/vz/template/cache /var/www/html/templates

# Nu kunnen anderen downloaden:
# wget http://your-proxmox-ip/templates/sqlite-web-template.tar.gz
```

### Template verwijderen

```bash
# Verwijder template container (PERMANENT!)
pct destroy 999

# Of via UI: Rechtermuisklik → Remove
```

## Automated Template Building

Voor CI/CD integration:

```bash
#!/bin/bash
# build-template.sh - Automated template builder

set -e

TEMPLATE_ID=999
TEMPLATE_NAME="sqlite-web-template"
VERSION="1.0"
BUILD_DATE=$(date +%Y%m%d)

echo "Building SQLite-Web template v$VERSION..."

# Check if template exists
if pct status $TEMPLATE_ID &>/dev/null; then
    echo "Removing old template..."
    pct destroy $TEMPLATE_ID --purge
fi

# Create new container
echo "Creating container..."
pct create $TEMPLATE_ID local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
    --hostname $TEMPLATE_NAME \
    --memory 512 \
    --cores 1 \
    --rootfs local-lvm:4 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --unprivileged 1 \
    --description "SQLite-Web v$VERSION - Built $BUILD_DATE"

# Start container
pct start $TEMPLATE_ID
sleep 10

# Install software
echo "Installing software..."
pct exec $TEMPLATE_ID -- bash << 'EOF'
export DEBIAN_FRONTEND=noninteractive
apt update
apt upgrade -y
apt install -y python3-pip sqlite3 vim curl wget
pip3 install --upgrade pip
pip3 install sqlite-web flask peewee pygments python-dotenv
mkdir -p /data
apt autoremove -y
apt clean
EOF

# Configure (voeg hier je configuratie toe zoals in Methode A)
echo "Configuring..."
# ... add configuration steps ...

# Cleanup
echo "Cleaning up..."
pct exec $TEMPLATE_ID -- bash << 'EOF'
rm -rf /tmp/* /var/tmp/*
history -c
journalctl --vacuum-time=1s
EOF

# Stop and convert
echo "Converting to template..."
pct stop $TEMPLATE_ID
sleep 5
pct template $TEMPLATE_ID

# Backup
echo "Creating backup..."
vzdump $TEMPLATE_ID --mode stop --compress zstd \
    --dumpdir /var/lib/vz/dump

echo "Template build complete!"
echo "Template ID: $TEMPLATE_ID"
echo "Backup: /var/lib/vz/dump/vzdump-lxc-$TEMPLATE_ID-*.tar.zst"
```

## Troubleshooting

### Template conversie faalt

```bash
# Check of container volledig gestopt is
pct status $CTID

# Forceer stop
pct stop $CTID --force

# Check locks
ls -la /var/lock/pve-manager/

# Remove lock if needed (voorzichtig!)
rm /var/lock/pve-manager/pve-lock-$CTID
```

### Clone faalt

```bash
# Check disk space
df -h

# Check template status
pct config $TEMPLATE_ID | grep template

# Probeer met different storage
pct clone 999 100 --storage local-lvm
```

### Container van template start niet

```bash
# Check logs
journalctl -u pve-container@100.service

# Check container config
pct config 100

# Regenerate machine-id
pct start 100
pct exec 100 -- systemd-machine-id-setup
pct restart 100
```

## Samenvatting

**Snelste methode voor productie:**

1. Maak schone container → Installeer alles → Configureer
2. Cleanup (logs, history, temp files)
3. Stop container → `pct template <CTID>`
4. Test door te clonen
5. Backup template met `vzdump`

**Wanneer gebruiken:**

- ✅ Herhaalde deployments
- ✅ Testing environments
- ✅ Development instances
- ✅ Disaster recovery
- ✅ Scaling out

**Best practices:**

- Versiebeheer voor templates
- Goede documentatie in template
- Regular updates
- Test voor productie gebruik
- Backup templates regelmatig

Nu kun je in enkele seconden nieuwe SQLite-Web containers uitrollen!
