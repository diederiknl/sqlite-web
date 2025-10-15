# SQLite-Web Deployment op Proxmox

Deze guide beschrijft hoe je sqlite-web deployed op een Proxmox server met LXC containers.

## Overzicht

Proxmox gebruikt LXC containers via PVE (Proxmox Virtual Environment), wat betekent dat je een aangepaste aanpak nodig hebt vergeleken met standalone LXD/LXC. Deze guide geeft twee methoden:

1. **Methode A**: Direct installeren in een nieuwe Proxmox LXC container (AANBEVOLEN)
2. **Methode B**: Bestaande LXC setup-script aanpassen voor Proxmox

## Vereisten

- Toegang tot Proxmox web UI of SSH toegang
- Root/sudo rechten op de Proxmox host
- Basis kennis van Proxmox containers

## Methode A: Direct installeren in Proxmox LXC Container

### Stap 1: Container aanmaken via Proxmox UI

1. Log in op Proxmox web interface (https://jouw-proxmox-server:8006)
2. Klik op **Create CT** (rechts bovenin)
3. Configureer de container:

**General:**
- CT ID: (automatisch of zelf kiezen, bijv. 100)
- Hostname: `sqlite-web`
- Password: Kies een root password
- SSH public key: (optioneel maar aanbevolen)

**Template:**
- Storage: local
- Template: Kies een van:
  - `debian-12-standard` (Debian Bookworm - aanbevolen voor stabiliteit)
  - `alpine-3.18-default` (Alpine - minimaal, ~150MB)

**Root Disk:**
- Storage: local-lvm (of jouw storage)
- Disk size: 4 GB (voldoende voor sqlite-web en enkele databases)

**CPU:**
- Cores: 1-2

**Memory:**
- Memory: 512 MB
- Swap: 512 MB

**Network:**
- Name: eth0
- Bridge: vmbr0
- IPv4: DHCP (of statisch IP naar keuze)
- IPv6: DHCP (of leeglaten)

**DNS:**
- Use host settings

**Options:**
- Start at boot: ✓ (aan)
- Unprivileged container: ✓ (aan - veiliger)

4. Klik **Finish** om de container aan te maken

### Stap 2: Container starten en SSH/Console openen

Via Proxmox UI:
1. Selecteer de container in de linkerbalk
2. Klik op **Start**
3. Klik op **Console** om een terminal te openen

Of via SSH vanuit je lokale machine:
```bash
# SSH naar de Proxmox host
ssh root@jouw-proxmox-ip

# Open container console
pct enter 100  # vervang 100 met je CT ID
```

### Stap 3: Installatie in de container

**Voor Debian container:**

```bash
# Update packages
apt update && apt upgrade -y

# Installeer dependencies
apt install -y python3 python3-pip python3-dev \
    build-essential sqlite3 libsqlite3-dev wget curl

# Upgrade pip
pip3 install --upgrade pip

# Installeer sqlite-web en dependencies
pip3 install --no-cache-dir flask peewee pygments python-dotenv sqlite-web

# Maak data directory
mkdir -p /data
chmod 755 /data
```

**Voor Alpine container:**

```bash
# Update packages
apk update && apk upgrade

# Installeer dependencies
apk add --no-cache python3 py3-pip build-base gcc \
    python3-dev musl-dev linux-headers sqlite sqlite-dev

# Upgrade pip
pip3 install --upgrade pip

# Installeer sqlite-web en dependencies
pip3 install --no-cache-dir flask peewee pygments python-dotenv sqlite-web

# Maak data directory
mkdir -p /data
chmod 755 /data

# Cleanup build dependencies (optioneel, scheelt ~100MB)
apk del build-base gcc python3-dev musl-dev linux-headers
```

### Stap 4: Systemd service installeren

Upload de service file vanuit je lokale machine:

```bash
# Vanuit je lokale machine (in de sqlite-web directory)
scp lxc/sqlite-web.service root@jouw-proxmox-ip:/tmp/

# Op de Proxmox host
pct push 100 /tmp/sqlite-web.service /etc/systemd/system/sqlite-web.service

# Of direct kopiëren als je in de container console bent
```

Of maak het bestand handmatig aan in de container:

```bash
cat > /etc/systemd/system/sqlite-web.service << 'EOF'
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
```

### Stap 5: Configuratie aanmaken

```bash
cat > /etc/default/sqlite-web << 'EOF'
# SQLite-Web Configuration
SQLITE_DATABASE=example.db
LISTEN_HOST=0.0.0.0
LISTEN_PORT=8080
EXTRA_OPTIONS=""
EOF
```

### Stap 6: Voorbeeld database aanmaken (optioneel)

```bash
sqlite3 /data/example.db << 'EOF'
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (username, email) VALUES
    ('admin', 'admin@example.com'),
    ('demo', 'demo@example.com');
EOF
```

### Stap 7: Service activeren en starten

```bash
# Reload systemd
systemctl daemon-reload

# Enable service (start at boot)
systemctl enable sqlite-web

# Start service
systemctl start sqlite-web

# Check status
systemctl status sqlite-web
```

### Stap 8: Firewall configureren (op container)

```bash
# Voor Debian (als ufw beschikbaar is)
apt install ufw
ufw allow 8080/tcp
ufw enable

# Voor Alpine (iptables)
apk add iptables
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
rc-update add iptables
/etc/init.d/iptables save
```

### Stap 9: Toegang configureren

Nu moet je de applicatie toegankelijk maken vanaf buiten de container.

**Optie 1: Via Proxmox firewall en NAT (eenvoudigst)**

1. Ga naar Proxmox UI
2. Selecteer je container
3. Ga naar **Firewall** → **Options**
4. Enable firewall
5. Ga naar **Firewall** → **Rules**
6. Klik **Add** en voeg toe:
   - Direction: in
   - Action: ACCEPT
   - Protocol: tcp
   - Dest. port: 8080

**Optie 2: Port forwarding op Proxmox host**

Op de Proxmox host:

```bash
# Verkrijg het IP van de container
pct exec 100 -- ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
# Bijvoorbeeld: 192.168.1.100

# Setup iptables port forward op Proxmox host
CONTAINER_IP="192.168.1.100"  # Vervang met je container IP
HOST_PORT="8080"
CONTAINER_PORT="8080"

iptables -t nat -A PREROUTING -p tcp --dport $HOST_PORT -j DNAT --to-destination $CONTAINER_IP:$CONTAINER_PORT
iptables -A FORWARD -p tcp -d $CONTAINER_IP --dport $CONTAINER_PORT -j ACCEPT

# Save iptables rules (Debian/Ubuntu)
apt install iptables-persistent
netfilter-persistent save

# Of voor andere systemen
iptables-save > /etc/iptables/rules.v4
```

**Optie 3: Reverse proxy met Nginx/Apache**

Zie de sectie "Reverse Proxy Setup" onderaan.

### Stap 10: Testen

Verkrijg het IP adres:

```bash
# In de container
ip addr show eth0 | grep "inet "

# Of vanuit Proxmox host
pct exec 100 -- hostname -I
```

Open in je browser:
- `http://container-ip:8080` (direct naar container)
- `http://proxmox-ip:8080` (als je port forwarding hebt ingesteld)

## Methode B: Setup Script Aanpassen voor Proxmox

De bestaande `setup-lxc.sh` werkt niet direct op Proxmox omdat Proxmox `pct` gebruikt in plaats van `lxc` commando's. Hier is een aangepaste versie:

```bash
# Download vanaf je lokale machine
scp -r lxc root@jouw-proxmox-ip:/root/sqlite-web-lxc/

# SSH naar Proxmox
ssh root@jouw-proxmox-ip

# Maak eerst handmatig een container aan via Proxmox UI (zie Methode A, Stap 1)
# Noteer het CT ID (bijvoorbeeld 100)

# Gebruik dan de container zoals in Methode A vanaf Stap 2
```

## Database Management

### Database uploaden naar container

**Vanuit je lokale machine:**

```bash
# Upload via Proxmox host
scp mydata.db root@proxmox-ip:/tmp/
ssh root@proxmox-ip "pct push 100 /tmp/mydata.db /data/mydata.db"

# Of direct als je SSH hebt in de container
scp mydata.db root@container-ip:/data/
```

**Vanuit Proxmox host:**

```bash
# Kopieer bestand naar container
pct push 100 /path/to/mydata.db /data/mydata.db

# Update configuratie
pct exec 100 -- sh -c 'sed -i "s/SQLITE_DATABASE=.*/SQLITE_DATABASE=mydata.db/" /etc/default/sqlite-web'
pct exec 100 -- systemctl restart sqlite-web
```

### Host directory mounten (persistent storage)

Dit is handig als je databases buiten de container wilt bewaren:

```bash
# Op Proxmox host: maak directory
mkdir -p /var/lib/sqlite-web-data

# Stop de container
pct stop 100

# Voeg mount point toe aan container config
pct set 100 -mp0 /var/lib/sqlite-web-data,mp=/data

# Start container
pct start 100

# Check of mount werkt
pct exec 100 -- df -h | grep /data
```

Nu is `/var/lib/sqlite-web-data` op de Proxmox host gemount als `/data` in de container.

## Container Beheer

### Via Proxmox CLI (op host)

```bash
# Start container
pct start 100

# Stop container
pct stop 100

# Restart container
pct restart 100

# Console openen
pct enter 100

# Command uitvoeren
pct exec 100 -- systemctl status sqlite-web

# Lijst alle containers
pct list

# Container info
pct config 100

# Resource gebruik
pct exec 100 -- free -h
pct exec 100 -- df -h
```

### Service beheer in container

```bash
# Via Proxmox host
pct exec 100 -- systemctl status sqlite-web
pct exec 100 -- systemctl restart sqlite-web
pct exec 100 -- journalctl -u sqlite-web -n 50

# Of in container console
systemctl status sqlite-web
systemctl restart sqlite-web
journalctl -fu sqlite-web
```

## Backup en Restore

### Container backup via Proxmox

**Via Proxmox UI:**
1. Selecteer container
2. Ga naar **Backup**
3. Klik **Backup now**
4. Kies storage en compressie type

**Via CLI:**

```bash
# Manual backup
vzdump 100 --mode snapshot --compress zstd --storage local

# Automated backups via Proxmox
# Ga naar Datacenter → Backup → Add voor schema's

# Restore backup
pct restore 100 /var/lib/vz/dump/vzdump-lxc-100-*.tar.zst
```

### Database backup

```bash
# Database van container naar host
pct pull 100 /data/mydb.db /root/backups/mydb-$(date +%Y%m%d).db

# Dump maken
pct exec 100 -- sqlite3 /data/mydb.db .dump > /root/backups/mydb-$(date +%Y%m%d).sql

# Backup naar remote location
scp /root/backups/mydb-*.db user@backup-server:/backups/
```

## Security Best Practices

### 1. Dedicated user (aanbevolen voor productie)

```bash
pct exec 100 -- sh -c '
# Voor Debian
useradd -r -d /data -s /bin/bash sqliteweb

# Voor Alpine
adduser -D -h /data -s /bin/sh sqliteweb

# Permissions
chown -R sqliteweb:sqliteweb /data
'

# Update service file
pct exec 100 -- sed -i 's/User=root/User=sqliteweb/' /etc/systemd/system/sqlite-web.service
pct exec 100 -- systemctl daemon-reload
pct exec 100 -- systemctl restart sqlite-web
```

### 2. Read-only mode

```bash
pct exec 100 -- sh -c 'echo "EXTRA_OPTIONS=\"--read-only\"" >> /etc/default/sqlite-web'
pct exec 100 -- systemctl restart sqlite-web
```

### 3. Password protection

```bash
pct exec 100 -- sh -c 'echo "EXTRA_OPTIONS=\"--password --require-login\"" >> /etc/default/sqlite-web'
pct exec 100 -- systemctl restart sqlite-web
```

### 4. Firewall op Proxmox host

```bash
# Alleen toegang vanaf specifiek netwerk
iptables -A FORWARD -d CONTAINER_IP -p tcp --dport 8080 -s 192.168.1.0/24 -j ACCEPT
iptables -A FORWARD -d CONTAINER_IP -p tcp --dport 8080 -j DROP
```

### 5. Unprivileged container (standaard in Proxmox)

Zorg dat je container unprivileged is (dit is standaard bij nieuwe containers).

## Reverse Proxy Setup

Voor productie gebruik is het aanbevolen om een reverse proxy te gebruiken.

### Nginx Reverse Proxy (op Proxmox host of aparte VM)

```bash
# Installeer nginx op Proxmox host of aparte container
apt install nginx certbot python3-certbot-nginx

# Configuratie aanmaken
cat > /etc/nginx/sites-available/sqlite-web << 'EOF'
server {
    listen 80;
    server_name jouw-domein.nl;

    location / {
        proxy_pass http://CONTAINER_IP:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (indien nodig)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# Enable site
ln -s /etc/nginx/sites-available/sqlite-web /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# SSL via Let's Encrypt
certbot --nginx -d jouw-domein.nl
```

### Traefik (voor meerdere services)

Als je meerdere containers hebt, overweeg dan Traefik:

```bash
# Maak een aparte Traefik container aan in Proxmox
# Dit vereert een aparte setup - zie Traefik documentatie
```

## Monitoring

### Resource monitoring

```bash
# CPU en Memory gebruik
pct exec 100 -- top -bn1 | head -20

# Disk gebruik
pct exec 100 -- df -h

# Service logs
pct exec 100 -- journalctl -u sqlite-web --since "1 hour ago"

# Network connections
pct exec 100 -- netstat -tlnp | grep 8080
```

### Prometheus monitoring (optioneel)

Voor advanced monitoring kun je Prometheus + Grafana gebruiken.

## Troubleshooting

### Service start niet

```bash
# Check service status
pct exec 100 -- systemctl status sqlite-web

# Check logs
pct exec 100 -- journalctl -u sqlite-web -n 100 --no-pager

# Test handmatig
pct exec 100 -- sh
cd /data
sqlite_web -H 0.0.0.0 -x example.db
```

### Kan niet verbinden

```bash
# Check of service draait
pct exec 100 -- systemctl is-active sqlite-web

# Check of poort luistert
pct exec 100 -- netstat -tlnp | grep 8080

# Check container IP
pct exec 100 -- ip addr

# Test connectie vanuit Proxmox host
curl http://CONTAINER_IP:8080

# Check firewall
pct exec 100 -- iptables -L -n
```

### Database locked errors

```bash
# Zet WAL mode aan
pct exec 100 -- sqlite3 /data/mydb.db "PRAGMA journal_mode=WAL;"

# Check permissions
pct exec 100 -- ls -la /data/
```

### Container start niet na reboot

```bash
# Check of onboot is ingesteld
pct config 100 | grep onboot

# Zet onboot aan
pct set 100 -onboot 1

# Check boot logs
pct exec 100 -- journalctl -b
```

## Performance Tuning

### Container resources aanpassen

Via Proxmox UI:
1. Stop de container
2. Ga naar **Resources**
3. Pas CPU, Memory, Disk aan

Via CLI:

```bash
# CPU cores
pct set 100 -cores 2

# Memory
pct set 100 -memory 1024

# Swap
pct set 100 -swap 1024

# Disk grootte vergroten
pct resize 100 rootfs +2G
```

### SQLite optimalisaties

```bash
# WAL mode voor betere concurrency
pct exec 100 -- sqlite3 /data/mydb.db "PRAGMA journal_mode=WAL;"

# Cache size vergroten (in KB)
pct exec 100 -- sqlite3 /data/mydb.db "PRAGMA cache_size=-64000;"  # 64MB

# Custom compile met optimalisaties (advanced)
# Zie docker/Dockerfile voor CFLAGS
```

## Updates

```bash
# Update system packages
pct exec 100 -- apt update && apt upgrade -y  # Debian
pct exec 100 -- apk upgrade  # Alpine

# Update sqlite-web
pct exec 100 -- pip3 install --upgrade sqlite-web

# Restart service
pct exec 100 -- systemctl restart sqlite-web
```

## Template maken (voor hergebruik)

Als je deze setup vaker wilt gebruiken:

```bash
# Maak een template van de container
pct stop 100
vzdump 100 --mode stop --compress zstd
# Template staat nu in /var/lib/vz/dump/

# Of converteer naar template (kan niet meer gestart worden!)
pct template 100

# Nieuwe container van template
pct clone 100 101 --hostname sqlite-web-2
```

## Automatische deployment script voor Proxmox

Wil je dit geautomatiseerd? Maak dit script op de Proxmox host:

```bash
#!/bin/bash
# proxmox-deploy-sqlite-web.sh

CTID=100
HOSTNAME="sqlite-web"
TEMPLATE="local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"
STORAGE="local-lvm"
MEMORY=512
CORES=1

# Create container
pct create $CTID $TEMPLATE \
    --hostname $HOSTNAME \
    --memory $MEMORY \
    --cores $CORES \
    --rootfs $STORAGE:4 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --onboot 1 \
    --unprivileged 1

# Start container
pct start $CTID

# Wait for container to be ready
sleep 5

# Install dependencies
pct exec $CTID -- bash -c '
    apt update
    apt install -y python3-pip sqlite3
    pip3 install flask peewee pygments python-dotenv sqlite-web
    mkdir -p /data
'

# Copy service file (assumes you have it locally)
pct push $CTID ./sqlite-web.service /etc/systemd/system/sqlite-web.service

# Create config
pct exec $CTID -- bash -c 'cat > /etc/default/sqlite-web << EOF
SQLITE_DATABASE=example.db
LISTEN_HOST=0.0.0.0
LISTEN_PORT=8080
EXTRA_OPTIONS=""
EOF'

# Enable and start service
pct exec $CTID -- systemctl daemon-reload
pct exec $CTID -- systemctl enable sqlite-web
pct exec $CTID -- systemctl start sqlite-web

echo "Deployment complete!"
echo "Container ID: $CTID"
echo "Access at: http://$(pct exec $CTID -- hostname -I | awk '{print $1}'):8080"
```

## Handige Links

- Proxmox LXC documentatie: https://pve.proxmox.com/wiki/Linux_Container
- SQLite-Web: https://github.com/coleifer/sqlite-web
- Proxmox Forum: https://forum.proxmox.com/

## Samenvatting

Voor een snelle deployment op Proxmox:

1. Maak LXC container aan via Proxmox UI (Debian of Alpine)
2. Start container en open console
3. Installeer Python, pip, en sqlite-web
4. Kopieer systemd service file
5. Maak configuratie aan
6. Start service
7. Configureer firewall/port forwarding
8. Test toegang via browser

De applicatie draait nu in een geïsoleerde, lichtgewicht container met volledige systemd integratie en eenvoudig beheer via Proxmox!
