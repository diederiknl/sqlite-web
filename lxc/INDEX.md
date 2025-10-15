# LXC Directory - File Index

Complete overzicht van alle bestanden voor SQLite-Web LXC/Proxmox deployment.

## 📋 Overzicht

```
lxc/
├── 📘 Documentatie (4 files, ~60KB)
│   ├── README.md                          - Hoofd README (LXC/LXD standalone)
│   ├── SCRIPTS-README.md                  - Complete Proxmox scripts guide ⭐
│   ├── PROXMOX-DEPLOYMENT.md              - Handmatige Proxmox deployment
│   ├── PROXMOX-TEMPLATE-CREATION.md       - Template creation details
│   └── INDEX.md                           - Dit bestand
│
├── 🤖 Automation Scripts (5 files, ~60KB)
│   ├── build-proxmox-template.sh          - Bouw LXC template ⭐
│   ├── deploy-from-template.sh            - Deploy enkele container ⭐
│   ├── bulk-deploy.sh                     - Bulk deployment ⭐
│   ├── manage-containers.sh               - Container management tool ⭐
│   └── setup-lxc.sh                       - Standalone LXC setup
│
└── ⚙️  Configuration Files (2 files, ~2KB)
    ├── sqlite-web.service                 - Systemd service file
    └── config.example                     - Configuration example
```

## 📘 Documentatie

### [README.md](README.md) (9.7KB)
**Standalone LXC/LXD Setup**

Voor wie LXC/LXD gebruikt zonder Proxmox. Bevat:
- LXC voordelen vs Docker
- LXD installatie
- Handmatige container setup
- Service configuratie
- Database management
- Troubleshooting

**Gebruik**: Standalone LXC servers (Ubuntu, Debian met LXD)

---

### [SCRIPTS-README.md](SCRIPTS-README.md) (15KB) ⭐
**Complete Proxmox Automation Guide**

**START HIER voor Proxmox gebruikers!** Complete guide voor alle scripts:
- Quick start workflows
- Gedetailleerde script documentatie
- Deployment scenarios
- Best practices
- Troubleshooting
- Management voorbeelden

**Gebruik**: Primaire documentatie voor Proxmox deployments

---

### [PROXMOX-DEPLOYMENT.md](PROXMOX-DEPLOYMENT.md) (17KB)
**Handmatige Proxmox Deployment**

Voor wie stap-voor-stap handmatig wil deployen:
- Container aanmaken via UI
- Handmatige software installatie
- Database management
- Backup procedures
- Security hardening
- Reverse proxy setup

**Gebruik**: Leren hoe het werkt, custom deployments

---

### [PROXMOX-TEMPLATE-CREATION.md](PROXMOX-TEMPLATE-CREATION.md) (19KB)
**Template Creation Deep Dive**

Uitgebreide guide over LXC templates:
- Wat zijn templates?
- 3 methodes voor template creation
- Cleanup procedures
- Template management
- Best practices
- Troubleshooting

**Gebruik**: Template experts, custom requirements

---

## 🤖 Automation Scripts

### [build-proxmox-template.sh](build-proxmox-template.sh) (21KB) ⭐
**Automated Template Builder**

**Doel**: Volledig geautomatiseerd een production-ready LXC template bouwen.

**Features:**
- Debian of Alpine support
- Complete software installation
- Systemd service setup
- First-boot script creation
- Automatic cleanup
- Template conversion
- Backup creation

**Gebruik:**
```bash
# Standaard Debian template
bash build-proxmox-template.sh

# Alpine template
bash build-proxmox-template.sh --distro alpine

# Custom versie
bash build-proxmox-template.sh --version 2.0 --template-id 998

# Rebuild existing
bash build-proxmox-template.sh --clean
```

**Output:**
- Template container (default ID: 999)
- Backup in `/var/lib/vz/dump/`
- ~5-10 minuten build tijd

**Requirements:**
- Proxmox host
- Root access
- 4-8GB free storage

---

### [deploy-from-template.sh](deploy-from-template.sh) (10KB) ⭐
**Single Container Deployment**

**Doel**: Deploy een enkele container van een template.

**Features:**
- Full of linked clone
- Resource configuration
- Database upload
- Automatic initialization
- Service verification

**Gebruik:**
```bash
# Simpel
bash deploy-from-template.sh --container-id 100

# Custom resources
bash deploy-from-template.sh \
    --container-id 101 \
    --hostname prod-db \
    --memory 1024 \
    --cores 2

# Met database
bash deploy-from-template.sh \
    --container-id 102 \
    --database /path/to/mydata.db
```

**Output:**
- Nieuwe container met opgegeven ID
- Running service
- Access URL
- ~30-60 seconden deployment

**Requirements:**
- Template moet bestaan (default: 999)
- Unieke container ID
- Voldoende storage

---

### [bulk-deploy.sh](bulk-deploy.sh) (10KB) ⭐
**Bulk Container Deployment**

**Doel**: Deploy meerdere containers tegelijk met parallel processing.

**Features:**
- Parallel deployment (verstelbaar)
- Sequential IDs en hostnames
- Progress tracking
- Failure handling
- Management commands

**Gebruik:**
```bash
# Deploy 5 containers
bash bulk-deploy.sh --count 5

# Custom settings
bash bulk-deploy.sh \
    --count 10 \
    --start-id 200 \
    --memory 1024 \
    --cores 2 \
    --parallel 5

# Development cluster
bash bulk-deploy.sh \
    --count 3 \
    --prefix dev-sqlite \
    --start-id 300
```

**Output:**
- Meerdere containers (ID range)
- Success/failure summary
- Management commands
- ~2-8 minuten (afhankelijk van count en parallel)

**Requirements:**
- Template moet bestaan
- Voldoende IDs beschikbaar
- Voldoende resources

---

### [manage-containers.sh](manage-containers.sh) (12KB) ⭐
**Container Management Tool**

**Doel**: Centralized management voor alle SQLite-Web containers.

**Features:**
- List all containers
- Detailed status
- Start/stop/restart
- Log viewing
- Bulk updates
- Backups
- Real-time monitoring
- Cleanup utilities

**Gebruik:**
```bash
# List containers
bash manage-containers.sh list

# Detailed status
bash manage-containers.sh status

# Start containers
bash manage-containers.sh start all
bash manage-containers.sh start 100-105
bash manage-containers.sh start 100,101,102

# View logs
bash manage-containers.sh logs 100

# Update sqlite-web
bash manage-containers.sh update all

# Backup
bash manage-containers.sh backup 100-105

# Monitor (real-time dashboard)
bash manage-containers.sh monitor

# Cleanup stopped
bash manage-containers.sh cleanup
```

**Output:**
- Formatted tables
- Color-coded status
- Real-time updates
- Action confirmations

**Requirements:**
- Proxmox host
- Existing containers

---

### [setup-lxc.sh](setup-lxc.sh) (6.6KB)
**Standalone LXC Setup**

**Doel**: Direct LXC setup voor standalone LXD/LXC (niet Proxmox).

**Features:**
- Alpine of Debian container
- Complete installation
- Service setup
- Port forwarding
- Example database

**Gebruik:**
```bash
# Standaard
sudo bash setup-lxc.sh

# Custom
sudo CONTAINER_NAME=myapp \
     DISTRO=alpine \
     PORT=8080 \
     bash setup-lxc.sh
```

**Output:**
- LXC container (via lxc command)
- Running service
- Port forwarding configured

**Requirements:**
- LXD/LXC installed
- Not for Proxmox (use other scripts)

---

## ⚙️ Configuration Files

### [sqlite-web.service](sqlite-web.service) (811B)
**Systemd Service Definition**

Systemd unit file voor sqlite-web service:
- Service definition
- Environment file loading
- Restart policy
- Security hardening
- Logging configuration

**Locatie in container:** `/etc/systemd/system/sqlite-web.service`

**Management:**
```bash
systemctl status sqlite-web
systemctl restart sqlite-web
journalctl -fu sqlite-web
```

---

### [config.example](config.example) (1.1KB)
**Configuration Example**

Voorbeeld configuratie bestand met alle opties:
- Database settings
- Network configuration
- Extra options
- Comments en examples

**Locatie in container:** `/etc/default/sqlite-web`

**Edit:**
```bash
vim /etc/default/sqlite-web
systemctl restart sqlite-web
```

---

## 🚀 Getting Started

### Voor Proxmox Gebruikers (Aanbevolen)

1. **Lees eerst**: [SCRIPTS-README.md](SCRIPTS-README.md)
2. **Upload scripts**: `scp lxc/*.sh root@proxmox:/root/`
3. **Bouw template**: `bash build-proxmox-template.sh`
4. **Deploy containers**: `bash deploy-from-template.sh --container-id 100`
5. **Beheer**: `bash manage-containers.sh list`

### Voor LXD/LXC Gebruikers

1. **Lees eerst**: [README.md](README.md)
2. **Run setup**: `sudo bash setup-lxc.sh`
3. **Access**: `http://localhost:8080`

### Voor Handmatige Setup

1. **Lees eerst**: [PROXMOX-DEPLOYMENT.md](PROXMOX-DEPLOYMENT.md)
2. **Volg stappen**: Stap-voor-stap in documentatie

---

## 📊 Workflow Diagram

```
┌─────────────────────────────────────────────────┐
│         Proxmox Deployment Workflow             │
└─────────────────────────────────────────────────┘

1. Template Creation (Eenmalig)
   ↓
   build-proxmox-template.sh
   ↓
   Template ID 999 (ready to use)

2. Deployment (Per project)
   ↓
   ┌─────────────────┬──────────────────┐
   │                 │                  │
   Single            Bulk               Manual
   ↓                 ↓                  ↓
   deploy-from-      bulk-deploy.sh     PROXMOX-DEPLOYMENT.md
   template.sh       ↓                  ↓
   ↓                 Multiple           Container via UI
   Container 100     Containers 100-N   ↓
   │                 │                  Manual setup
   └─────────────────┴──────────────────┘
   ↓
3. Management (Ongoing)
   ↓
   manage-containers.sh
   ↓
   list | status | start | stop | update | backup | monitor

```

## 🎯 Use Cases

### Development Environment
```bash
# Snelle dev container
bash deploy-from-template.sh --container-id 300 --hostname dev-db --memory 256
```

### Production Deployment
```bash
# Bouw template
bash build-proxmox-template.sh --version 1.0

# Deploy met database
bash deploy-from-template.sh \
    --container-id 100 \
    --hostname prod-sqlite \
    --memory 2048 \
    --cores 4 \
    --database /backups/production.db
```

### Testing Cluster
```bash
# Deploy 5 test containers
bash bulk-deploy.sh --count 5 --start-id 200 --prefix test

# Later cleanup
bash manage-containers.sh cleanup
```

### Load Balanced Setup
```bash
# Deploy 3 containers
bash bulk-deploy.sh --count 3 --start-id 100 --memory 1024

# Monitor all
bash manage-containers.sh monitor
```

---

## 🆘 Troubleshooting

### Script niet executable?
```bash
chmod +x lxc/*.sh
```

### Template build faalt?
```bash
# Check logs
cat /tmp/deploy-*.log

# Rebuild
bash build-proxmox-template.sh --clean
```

### Deployment faalt?
```bash
# Verify template
pct config 999 | grep template

# Check storage
df -h

# Manual test
bash deploy-from-template.sh --container-id 9999 --no-init
```

### Service niet running?
```bash
# Check service
pct exec 100 -- systemctl status sqlite-web

# View logs
pct exec 100 -- journalctl -u sqlite-web -n 100

# Manual test
pct exec 100 -- sqlite_web -H 0.0.0.0 -x /data/example.db
```

---

## 📚 Additional Resources

- **SQLite-Web GitHub**: https://github.com/coleifer/sqlite-web
- **Proxmox LXC Docs**: https://pve.proxmox.com/wiki/Linux_Container
- **LXD Documentation**: https://linuxcontainers.org/lxd/docs/

---

## ✅ Checklist

### Before You Start
- [ ] Proxmox host ready
- [ ] Root/SSH access
- [ ] Storage available (10GB+ recommended)
- [ ] Scripts uploaded to Proxmox

### Template Creation
- [ ] Run `build-proxmox-template.sh`
- [ ] Verify template exists: `pct config 999`
- [ ] Backup created in `/var/lib/vz/dump/`

### Deployment
- [ ] Deploy test container
- [ ] Verify service running
- [ ] Access web interface
- [ ] Upload/test database

### Production
- [ ] Security hardening
- [ ] Backup strategy
- [ ] Monitoring setup
- [ ] Documentation

---

**Last Updated**: 2024-10-15
**Version**: 1.0
**Maintained by**: VrieD
