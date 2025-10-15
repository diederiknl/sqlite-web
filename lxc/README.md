# SQLite-Web LXC Container Setup

Deze directory bevat scripts en configuratie voor het draaien van sqlite-web in een LXC container.

## Voordelen van LXC vs Docker

- **Betere performance**: Native system calls zonder container overhead
- **Persistente configuratie**: Geen volumes nodig, direct filesystem access
- **Systemd integratie**: Native service management en logging
- **Lichtgewicht**: Minder resource overhead dan Docker
- **Snapshot support**: Eenvoudige backups via `lxc snapshot`

## Vereisten

- LXD/LXC geïnstalleerd en geconfigureerd
- Root/sudo toegang
- Linux host systeem

### LXD installeren (indien nog niet geïnstalleerd)

```bash
# Ubuntu/Debian
sudo snap install lxd
sudo lxd init --auto

# Of via apt
sudo apt install lxd
sudo lxd init --auto

# Voeg gebruiker toe aan lxd groep
sudo usermod -aG lxd $USER
newgrp lxd
```

## Snelle Start

### Automatische Setup

Het makkelijkste is het gebruik van het geautomatiseerde setup script:

```bash
cd lxc
sudo bash setup-lxc.sh
```

Dit script zal:
1. Een nieuwe LXC container aanmaken
2. Alle dependencies installeren
3. sqlite-web en Python packages installeren
4. Systemd service configureren en starten
5. Port forwarding instellen
6. Een voorbeeld database aanmaken

### Custom configuratie

Je kunt de setup aanpassen via environment variabelen:

```bash
# Alpine container (standaard, kleinste footprint)
sudo CONTAINER_NAME=sqlite-web \
     DISTRO=alpine \
     VERSION=3.18 \
     PORT=8080 \
     bash setup-lxc.sh

# Of Debian container (meer compatibiliteit)
sudo CONTAINER_NAME=sqlite-web \
     DISTRO=debian \
     VERSION=bookworm \
     PORT=8080 \
     bash setup-lxc.sh

# Met data directory mount
sudo DATA_PATH=/path/to/your/databases \
     bash setup-lxc.sh
```

## Handmatige Setup

Als je meer controle wilt, kun je de container handmatig opzetten:

### 1. Container aanmaken

```bash
# Alpine (lichtgewicht, ~150MB)
lxc launch images:alpine/3.18 sqlite-web

# Of Debian (meer features, ~300MB)
lxc launch images:debian/bookworm sqlite-web
```

### 2. Dependencies installeren

**Voor Alpine:**
```bash
lxc exec sqlite-web -- sh -c '
  apk update
  apk add --no-cache python3 py3-pip sqlite
  pip3 install --upgrade pip
  pip3 install flask peewee pygments python-dotenv sqlite-web
  mkdir -p /data
'
```

**Voor Debian/Ubuntu:**
```bash
lxc exec sqlite-web -- bash -c '
  apt update
  apt install -y python3 python3-pip sqlite3
  pip3 install --upgrade pip
  pip3 install flask peewee pygments python-dotenv sqlite-web
  mkdir -p /data
'
```

### 3. Systemd service installeren

```bash
lxc file push sqlite-web.service sqlite-web/etc/systemd/system/
lxc exec sqlite-web -- systemctl daemon-reload
lxc exec sqlite-web -- systemctl enable sqlite-web
```

### 4. Configuratie aanmaken

```bash
lxc exec sqlite-web -- sh -c 'cat > /etc/default/sqlite-web << EOF
SQLITE_DATABASE=your-database.db
LISTEN_HOST=0.0.0.0
LISTEN_PORT=8080
EXTRA_OPTIONS=""
EOF'
```

### 5. Port forwarding instellen

```bash
lxc config device add sqlite-web web-port proxy \
    listen=tcp:0.0.0.0:8080 \
    connect=tcp:127.0.0.1:8080
```

### 6. Service starten

```bash
lxc exec sqlite-web -- systemctl start sqlite-web
```

## Gebruik

### Database uploaden

```bash
# Upload een database naar de container
lxc file push mydata.db sqlite-web/data/

# Update configuratie om deze database te gebruiken
lxc exec sqlite-web -- sh -c 'echo "SQLITE_DATABASE=mydata.db" >> /etc/default/sqlite-web'
lxc exec sqlite-web -- systemctl restart sqlite-web
```

### Host directory mounten

Voor permanente data storage:

```bash
# Maak directory op host
mkdir -p /var/lib/sqlite-web

# Mount in container
lxc config device add sqlite-web data-volume disk \
    source=/var/lib/sqlite-web \
    path=/data
```

### Logs bekijken

```bash
# Live logs volgen
lxc exec sqlite-web -- journalctl -fu sqlite-web

# Laatste 50 regels
lxc exec sqlite-web -- journalctl -u sqlite-web -n 50

# Logs met tijdstempel
lxc exec sqlite-web -- journalctl -u sqlite-web --since "1 hour ago"
```

### Service beheren

```bash
# Status checken
lxc exec sqlite-web -- systemctl status sqlite-web

# Herstarten
lxc exec sqlite-web -- systemctl restart sqlite-web

# Stoppen
lxc exec sqlite-web -- systemctl stop sqlite-web

# Logs bekijken
lxc exec sqlite-web -- journalctl -u sqlite-web -f
```

### Container beheren

```bash
# Starten
lxc start sqlite-web

# Stoppen
lxc stop sqlite-web

# Herstarten
lxc restart sqlite-web

# Shell openen
lxc exec sqlite-web -- sh

# Informatie bekijken
lxc info sqlite-web

# Resource gebruik
lxc info sqlite-web --show-log
```

## Configuratie

De configuratie wordt beheerd via `/etc/default/sqlite-web` in de container:

```bash
# Bewerk configuratie
lxc exec sqlite-web -- vi /etc/default/sqlite-web

# Of push een nieuwe config
cat > sqlite-web.conf << EOF
SQLITE_DATABASE=mydb.db
LISTEN_HOST=0.0.0.0
LISTEN_PORT=8080
EXTRA_OPTIONS="--read-only"
EOF
lxc file push sqlite-web.conf sqlite-web/etc/default/sqlite-web

# Herstart service om wijzigingen toe te passen
lxc exec sqlite-web -- systemctl restart sqlite-web
```

### Beschikbare opties

- `SQLITE_DATABASE`: Database bestand (relatief aan /data of absoluut pad)
- `LISTEN_HOST`: Listen address (standaard 0.0.0.0)
- `LISTEN_PORT`: Listen port in container (standaard 8080)
- `EXTRA_OPTIONS`: Extra commandline opties voor sqlite_web

Voor alle beschikbare opties:
```bash
lxc exec sqlite-web -- sqlite_web --help
```

## Backup en Restore

### Snapshot maken

```bash
# Snapshot van hele container
lxc snapshot sqlite-web snapshot-$(date +%Y%m%d)

# Lijst van snapshots
lxc info sqlite-web

# Restore snapshot
lxc restore sqlite-web snapshot-20241015
```

### Database backup

```bash
# Database naar host kopiëren
lxc file pull sqlite-web/data/mydb.db ./mydb-backup.db

# Of via sqlite3 dump
lxc exec sqlite-web -- sqlite3 /data/mydb.db .dump > mydb-backup.sql
```

## Security

### Dedicated user aanmaken (aanbevolen)

Voor productie gebruik is het beter om een dedicated user te gebruiken:

```bash
lxc exec sqlite-web -- sh -c '
  adduser -D -h /data -s /bin/sh sqliteweb
  chown -R sqliteweb:sqliteweb /data
'

# Update service file
lxc exec sqlite-web -- sed -i "s/User=root/User=sqliteweb/" /etc/systemd/system/sqlite-web.service
lxc exec sqlite-web -- systemctl daemon-reload
lxc exec sqlite-web -- systemctl restart sqlite-web
```

### Read-only mode

Voor veilige toegang zonder schrijfrechten:

```bash
lxc exec sqlite-web -- sh -c 'echo "EXTRA_OPTIONS=\"--read-only\"" >> /etc/default/sqlite-web'
lxc exec sqlite-web -- systemctl restart sqlite-web
```

### Firewall

Beperk toegang tot specifieke IP's:

```bash
# Alleen localhost
lxc config device remove sqlite-web web-port
lxc config device add sqlite-web web-port proxy \
    listen=tcp:127.0.0.1:8080 \
    connect=tcp:127.0.0.1:8080

# Of gebruik host firewall (iptables/ufw)
sudo ufw allow from 192.168.1.0/24 to any port 8080
```

## Troubleshooting

### Service start niet

```bash
# Check service status
lxc exec sqlite-web -- systemctl status sqlite-web

# Check logs
lxc exec sqlite-web -- journalctl -u sqlite-web -n 100

# Test handmatig
lxc exec sqlite-web -- sh
cd /data
sqlite_web -H 0.0.0.0 -x example.db
```

### Kan niet verbinden

```bash
# Check of service draait
lxc exec sqlite-web -- systemctl is-active sqlite-web

# Check port forwarding
lxc config device show sqlite-web

# Check of poort bereikbaar is
curl http://localhost:8080
```

### Database locked errors

```bash
# Check WAL mode
lxc exec sqlite-web -- sqlite3 /data/mydb.db "PRAGMA journal_mode=WAL;"

# Check permissions
lxc exec sqlite-web -- ls -la /data/
```

## Performance Tuning

### Container resource limits

```bash
# CPU limit (2 cores)
lxc config set sqlite-web limits.cpu 2

# Memory limit (1GB)
lxc config set sqlite-web limits.memory 1GB

# Disk I/O priority
lxc config set sqlite-web limits.disk.priority 5
```

### SQLite optimalisaties

Voor grotere databases, kopieer de CFLAGS uit [docker/Dockerfile](../docker/Dockerfile) en compileer een custom SQLite binary met FTS5, JSON1 en andere features.

## Updates

```bash
# Update sqlite-web package
lxc exec sqlite-web -- pip3 install --upgrade sqlite-web

# Herstart service
lxc exec sqlite-web -- systemctl restart sqlite-web

# Update systeem packages
lxc exec sqlite-web -- apk upgrade  # Alpine
lxc exec sqlite-web -- apt update && apt upgrade  # Debian
```

## Verwijderen

```bash
# Stop en verwijder container
lxc stop sqlite-web
lxc delete sqlite-web

# Verwijder data (optioneel)
sudo rm -rf /var/lib/sqlite-web
```

## Extra Tips

- Gebruik `lxc console sqlite-web` voor serial console toegang
- Monitor resource gebruik: `lxc info sqlite-web --resources`
- Exporteer container: `lxc export sqlite-web backup.tar.gz`
- Importeer container: `lxc import backup.tar.gz`

## Support

Voor vragen over sqlite-web zelf: https://github.com/coleifer/sqlite-web
Voor LXC documentatie: https://linuxcontainers.org/lxd/docs/latest/
