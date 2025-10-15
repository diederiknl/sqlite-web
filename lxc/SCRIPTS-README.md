# Proxmox LXC Scripts voor SQLite-Web

Deze directory bevat complete automation scripts voor het deployen van SQLite-Web op Proxmox met LXC containers.

## Overzicht Scripts

| Script | Doel | Gebruik |
|--------|------|---------|
| `build-proxmox-template.sh` | Bouw een LXC template | Eenmalig |
| `deploy-from-template.sh` | Deploy enkele container | Per container |
| `bulk-deploy.sh` | Deploy meerdere containers | Bulk deployment |
| `setup-lxc.sh` | Direct setup (standalone LXC) | Zonder Proxmox |

## Quick Start

### 1. Template Bouwen (Eenmalig)

```bash
# Upload scripts naar Proxmox
scp lxc/*.sh root@proxmox-ip:/root/

# SSH naar Proxmox
ssh root@proxmox-ip

# Maak template
cd /root
bash build-proxmox-template.sh

# Output: Template met ID 999 is aangemaakt
```

**Dit duurt ~5-10 minuten** en hoeft maar één keer.

### 2. Containers Deployen

#### Enkele Container

```bash
# Deploy container met ID 100
bash deploy-from-template.sh --container-id 100

# Access: http://container-ip:8080
```

#### Meerdere Containers

```bash
# Deploy 5 containers (ID 100-104)
bash bulk-deploy.sh --count 5

# Deploy 10 containers met custom settings
bash bulk-deploy.sh --count 10 --start-id 200 --memory 1024 --cores 2
```

## Gedetailleerde Handleiding

### build-proxmox-template.sh

**Doel**: Bouwt een production-ready LXC template met alles voorgeïnstalleerd.

**Wat het doet:**
- Maakt een nieuwe LXC container
- Installeert Python, SQLite, sqlite-web
- Configureert systemd service
- Maakt first-boot script
- Ruimt op (logs, temp files, etc.)
- Converteert naar read-only template
- Maakt backup

**Opties:**

```bash
bash build-proxmox-template.sh [options]

--template-id <id>        Template ID (default: 999)
--distro <name>           debian of alpine (default: debian)
--version <ver>           Template versie (default: 1.0)
--storage <name>          Storage naam (default: local-lvm)
--template-storage <name> Template storage (default: local)
--clean                   Verwijder bestaande template eerst
--no-backup               Skip backup na bouwen
--help                    Toon help
```

**Voorbeelden:**

```bash
# Standaard Debian template
bash build-proxmox-template.sh

# Alpine template (kleiner, ~150MB vs ~300MB)
bash build-proxmox-template.sh --distro alpine --template-id 998

# Custom versie met cleanup
bash build-proxmox-template.sh --version 2.0 --clean

# Verschillende storage
bash build-proxmox-template.sh --storage local-zfs
```

**Output:**
- Template container met ID (default: 999)
- Backup in `/var/lib/vz/dump/`
- Volledig geconfigureerd en klaar voor gebruik

**Timing:**
- Debian: ~5-7 minuten
- Alpine: ~3-5 minuten

### deploy-from-template.sh

**Doel**: Deploy een enkele container van de template.

**Wat het doet:**
- Cloned de template
- Past resources aan (CPU/RAM)
- Start de container
- Upload optioneel een database
- Runt first-boot script
- Toont access URL

**Opties:**

```bash
bash deploy-from-template.sh --container-id <id> [options]

Required:
--container-id <id>       Nieuwe container ID

Options:
--template-id <id>        Bron template (default: 999)
--hostname <name>         Container hostname (default: sqlite-web-<id>)
--database <file>         Database om te uploaden
--storage <name>          Storage (default: local-lvm)
--memory <MB>             RAM in MB (default: 512)
--cores <n>               CPU cores (default: 1)
--port <port>             Host poort (default: 8080)
--full-clone              Volledige clone (default)
--linked-clone            Linked clone (sneller, afhankelijk)
--no-start                Niet automatisch starten
--no-init                 Skip first-boot script
--help                    Toon help
```

**Voorbeelden:**

```bash
# Simpel
bash deploy-from-template.sh --container-id 100

# Custom hostname en resources
bash deploy-from-template.sh \
    --container-id 101 \
    --hostname prod-sqlite \
    --memory 1024 \
    --cores 2

# Met bestaande database
bash deploy-from-template.sh \
    --container-id 102 \
    --database /path/to/production.db

# Alleen aanmaken, niet starten
bash deploy-from-template.sh \
    --container-id 103 \
    --no-start \
    --no-init

# Linked clone (experimenteel, sneller)
bash deploy-from-template.sh \
    --container-id 104 \
    --linked-clone
```

**Output:**
- Nieuwe container met opgegeven ID
- Service draait automatisch
- Access URL wordt getoond

**Timing:**
- Full clone: ~30-60 seconden
- Linked clone: ~10-20 seconden

### bulk-deploy.sh

**Doel**: Deploy meerdere containers in één keer met parallel processing.

**Wat het doet:**
- Maakt meerdere containers van template
- Parallel deployment (verstelbaar)
- Sequentiële nummering
- Unieke hostnamen
- Sequential port assignment
- Progress tracking
- Failure recovery

**Opties:**

```bash
bash bulk-deploy.sh --count <n> [options]

Required:
--count <n>               Aantal containers

Options:
--template-id <id>        Bron template (default: 999)
--start-id <id>           Start container ID (default: 100)
--prefix <name>           Hostname prefix (default: sqlite-web)
--memory <MB>             RAM per container (default: 512)
--cores <n>               CPU per container (default: 1)
--start-port <port>       Start poort (default: 8080)
--storage <name>          Storage (default: local-lvm)
--parallel <n>            Max parallelle deployments (default: 3)
--init                    Run first-boot scripts (default: yes)
--no-init                 Skip first-boot scripts
--help                    Toon help
```

**Voorbeelden:**

```bash
# Deploy 5 containers (ID 100-104)
bash bulk-deploy.sh --count 5

# Deploy 10 met meer resources
bash bulk-deploy.sh \
    --count 10 \
    --start-id 200 \
    --memory 1024 \
    --cores 2

# Deploy voor load balancing
bash bulk-deploy.sh \
    --count 3 \
    --prefix webapp \
    --start-port 8080

# Snellere deployment (meer parallel)
bash bulk-deploy.sh \
    --count 20 \
    --parallel 5

# Test deployment zonder init
bash bulk-deploy.sh \
    --count 3 \
    --prefix test \
    --start-id 900 \
    --no-init
```

**Naming Pattern:**
```
Container ID: 100, 101, 102, ...
Hostname:     sqlite-web-100, sqlite-web-101, sqlite-web-102, ...
Port:         8080, 8081, 8082, ... (logisch, maar vereist extra config)
```

**Output:**
- Meerdere containers
- Summary met success/failure
- Management commands
- Access URLs voor alle containers

**Timing:**
- Per container: ~30-60 seconden
- 5 containers (3 parallel): ~2-3 minuten
- 10 containers (3 parallel): ~4-5 minuten
- 20 containers (5 parallel): ~6-8 minuten

## Workflow Voorbeelden

### Scenario 1: Development Environment

```bash
# Stap 1: Bouw template (eenmalig)
bash build-proxmox-template.sh --distro alpine --version 1.0

# Stap 2: Deploy development container
bash deploy-from-template.sh \
    --container-id 100 \
    --hostname dev-sqlite \
    --memory 256 \
    --cores 1

# Stap 3: Upload je development database
pct push 100 ~/my-dev-db.db /data/my-dev-db.db

# Stap 4: Update config
pct exec 100 -- sed -i 's/SQLITE_DATABASE=.*/SQLITE_DATABASE=my-dev-db.db/' /etc/default/sqlite-web
pct exec 100 -- systemctl restart sqlite-web
```

### Scenario 2: Production Deployment

```bash
# Stap 1: Bouw production template
bash build-proxmox-template.sh \
    --distro debian \
    --version 1.0 \
    --template-id 999

# Stap 2: Deploy production container
bash deploy-from-template.sh \
    --container-id 100 \
    --hostname prod-sqlite-web \
    --memory 2048 \
    --cores 4 \
    --database /backups/production.db

# Stap 3: Configure voor productie
pct exec 100 -- bash << 'EOF'
# Read-only mode
echo 'EXTRA_OPTIONS="--read-only --password"' >> /etc/default/sqlite-web

# Restart
systemctl restart sqlite-web
EOF

# Stap 4: Setup firewall
pct exec 100 -- bash << 'EOF'
apt install -y ufw
ufw allow from 192.168.1.0/24 to any port 8080
ufw enable
EOF
```

### Scenario 3: Testing Cluster

```bash
# Deploy 5 test containers
bash bulk-deploy.sh \
    --count 5 \
    --start-id 200 \
    --prefix test-sqlite \
    --memory 512 \
    --cores 1

# Later: Cleanup alle test containers
for id in {200..204}; do
    pct stop $id
    pct destroy $id
done
```

### Scenario 4: Load Balanced Setup

```bash
# Deploy 3 containers voor load balancing
bash bulk-deploy.sh \
    --count 3 \
    --start-id 100 \
    --prefix sqlite-lb \
    --memory 1024 \
    --cores 2

# Setup Nginx load balancer (op aparte container of host)
# Zie PROXMOX-DEPLOYMENT.md voor reverse proxy setup
```

## Container Management

### Basis Commands

```bash
# Start container
pct start 100

# Stop container
pct stop 100

# Restart container
pct restart 100

# Enter container
pct enter 100

# Run command
pct exec 100 -- systemctl status sqlite-web

# View logs
pct exec 100 -- journalctl -fu sqlite-web

# Container info
pct config 100
pct status 100
```

### Bulk Management

```bash
# Start alle containers (100-104)
for id in {100..104}; do pct start $id; done

# Stop alle containers
for id in {100..104}; do pct stop $id; done

# Check status van alle
for id in {100..104}; do
    echo "=== Container $id ==="
    pct status $id
    pct exec $id -- systemctl is-active sqlite-web
done

# Restart services op alle
for id in {100..104}; do
    pct exec $id -- systemctl restart sqlite-web
done
```

### Database Management

```bash
# Upload database naar container
pct push 100 /path/to/database.db /data/database.db

# Download database van container
pct pull 100 /data/database.db /backup/database.db

# Backup alle databases
for id in {100..104}; do
    pct pull $id /data/*.db /backups/container-$id/
done
```

### Resource Adjustment

```bash
# Verhoog memory
pct set 100 --memory 1024

# Verhoog CPU
pct set 100 --cores 2

# Beide
pct set 100 --memory 2048 --cores 4

# Vergroot disk
pct resize 100 rootfs +2G
```

## Template Management

### Updates

```bash
# Methode 1: Rebuild template
bash build-proxmox-template.sh --clean --version 2.0

# Methode 2: Update bestaande en converteer
pct clone 999 998 --hostname sqlite-web-update
pct start 998
pct exec 998 -- apt update && apt upgrade -y
pct exec 998 -- pip3 install --upgrade sqlite-web
pct stop 998
# Cleanup (zie build script)
pct template 998
```

### Backup en Restore

```bash
# Backup template
vzdump 999 --mode stop --compress zstd --dumpdir /var/lib/vz/dump

# Restore op andere host
scp /var/lib/vz/dump/vzdump-lxc-999-*.tar.zst root@other-proxmox:/tmp/
ssh root@other-proxmox
pct restore 999 /tmp/vzdump-lxc-999-*.tar.zst --storage local-lvm
```

### Versioning

```bash
# Houd meerdere template versies
# Template v1.0
CTID: 999
Hostname: sqlite-web-template-1.0

# Template v2.0 (nieuwe versie)
CTID: 998
Hostname: sqlite-web-template-2.0

# Test nieuwe versie
bash deploy-from-template.sh --template-id 998 --container-id 900

# Als goed: wissel
# Oude v1.0 backup maken en v2.0 naar 999 promoten
```

## Troubleshooting

### Script Fails

```bash
# Check laatste log
cat /tmp/deploy-*.log

# Test template
pct clone 999 9999 --hostname test
pct start 9999
pct exec 9999 -- systemctl status sqlite-web
pct destroy 9999
```

### Container Won't Start

```bash
# Check logs
pct exec 100 -- journalctl -xe

# Check service
pct exec 100 -- systemctl status sqlite-web

# Manual test
pct exec 100 -- bash
cd /data
sqlite_web -H 0.0.0.0 -x example.db
```

### Service Not Running

```bash
# Check if service exists
pct exec 100 -- systemctl list-unit-files | grep sqlite-web

# Check service file
pct exec 100 -- cat /etc/systemd/system/sqlite-web.service

# Check config
pct exec 100 -- cat /etc/default/sqlite-web

# Check binary
pct exec 100 -- which sqlite_web
pct exec 100 -- sqlite_web --version
```

### Template Issues

```bash
# Verify template
pct config 999 | grep template

# Check disk space
df -h

# Check template storage
pveam list local
ls -lh /var/lib/vz/template/cache/

# Rebuild if needed
bash build-proxmox-template.sh --clean
```

## Best Practices

### 1. Template Versioning

```bash
# Gebruik duidelijke versies
v1.0 - Initial release
v1.1 - Bug fixes
v2.0 - Major update

# Houd oude versies
CTID 999  - v1.0 (stable)
CTID 998  - v2.0 (latest)
CTID 997  - v2.1 (beta)
```

### 2. Naming Conventions

```bash
# Container IDs
100-199  - Production
200-299  - Development
300-399  - Testing
900-999  - Templates

# Hostnames
prod-sqlite-web-*
dev-sqlite-web-*
test-sqlite-web-*
```

### 3. Resource Planning

```bash
# Development: 256-512MB RAM, 1 core
# Production:  1024-2048MB RAM, 2-4 cores
# Heavy load:  4096+MB RAM, 4+ cores

# Disk per container: 4-8GB (afhankelijk van database grootte)
```

### 4. Backup Strategy

```bash
# Weekly template backup
0 2 * * 0 vzdump 999 --mode stop --compress zstd

# Daily container backup
0 3 * * * for id in {100..104}; do vzdump $id --mode snapshot; done

# Database backup before changes
pct pull 100 /data/prod.db /backups/$(date +%Y%m%d)-prod.db
```

### 5. Security

```bash
# Voor productie containers:
# 1. Dedicated user (niet root)
# 2. Read-only mode indien mogelijk
# 3. Password protection
# 4. Firewall rules
# 5. Regular updates

# Voorbeeld hardening script
pct exec 100 -- bash << 'EOF'
# Create dedicated user
useradd -r -d /data -s /bin/bash sqliteweb
chown -R sqliteweb:sqliteweb /data

# Update service
sed -i 's/User=root/User=sqliteweb/' /etc/systemd/system/sqlite-web.service

# Read-only + password
echo 'EXTRA_OPTIONS="--read-only --password"' >> /etc/default/sqlite-web

# Firewall
apt install -y ufw
ufw allow from 192.168.1.0/24 to any port 8080
ufw enable

# Restart
systemctl daemon-reload
systemctl restart sqlite-web
EOF
```

## Performance Tips

### 1. Parallel Deployment

```bash
# Voor bulk deployments, verhoog parallel count
bash bulk-deploy.sh --count 20 --parallel 5

# Let op: te veel parallel kan host overbelasten
# Aanbevolen: 3-5 parallel afhankelijk van host specs
```

### 2. Linked Clones

```bash
# Sneller maar afhankelijk van template
bash deploy-from-template.sh --container-id 100 --linked-clone

# Let op: template kan niet verwijderd worden
# Gebruik alleen voor test/dev
```

### 3. Storage Optimization

```bash
# ZFS = betere performance voor databases
bash build-proxmox-template.sh --storage local-zfs

# LVM = standaard, goed genoeg voor meeste use cases
bash build-proxmox-template.sh --storage local-lvm
```

## Onderhoud

### Weekly Tasks

```bash
# Update packages in template (maak nieuwe versie)
# Backup containers
# Check disk space
# Review logs
```

### Monthly Tasks

```bash
# Update sqlite-web in alle containers
for id in {100..104}; do
    pct exec $id -- pip3 install --upgrade sqlite-web
    pct exec $id -- systemctl restart sqlite-web
done

# Check for unused containers
pct list | grep stopped

# Cleanup old backups
find /var/lib/vz/dump -name "*.zst" -mtime +30 -delete
```

## Support

Voor problemen met:
- **Scripts zelf**: Check deze README en PROXMOX-TEMPLATE-CREATION.md
- **SQLite-Web**: https://github.com/coleifer/sqlite-web
- **Proxmox LXC**: https://pve.proxmox.com/wiki/Linux_Container

## Changelog

- **v1.0** (2024-10-15)
  - Initial release
  - Build, deploy, en bulk deployment scripts
  - Debian en Alpine support
  - Complete automation

---

**Made for easy SQLite-Web deployment on Proxmox!**
