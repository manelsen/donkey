# Deployment Guide
Complete deployment guide for all platforms

## Overview

This guide covers deploying Donkey on various platforms.

## System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 1 core | 2+ cores |
| RAM | 512 MB | 1 GB |
| Disk | 1 GB | 5 GB |
| OS | Linux/macOS/Windows | Linux |

## Build

### Standard Build

```bash
nim c src/donkey
```

### Production Build

```bash
nim c -d:release --mm:orc --warningAsError:on src/donkey
```

### With Database Support

```bash
# SQLite
nim c -d:release --mm:orc -d:withSqlite src/donkey

# PostgreSQL
nim c -d:release --mm:orc -d:withPostgres src/donkey
```

## Directories

Create required directories:

```bash
mkdir -p ~/.donkey/paddocks
mkdir -p ~/.donkey/logs
mkdir -p ~/.config/donkey
```

## Linux

### Systemd Service

Install as a user service:

```bash
bash deploy/install.sh
```

This creates:
- `~/.local/bin/donkey` - Binary
- `~/.config/donkey/donkey.toml` - Config
- `~/.config/systemd/user/donkey.service` - Service

### Start/Stop

```bash
# Start
systemctl --user start donkey

# Stop
systemctl --user stop donkey

# Restart
systemctl --user restart donkey

# Status
systemctl --user status donkey

# Logs
journalctl --user -u donkey -f
```

### Auto-start

```bash
systemctl --user enable donkey
```

## Docker

### Dockerfile

```dockerfile
FROM alpine:latest
RUN apk add --no-cache nim
WORKDIR /app
COPY . .
RUN nim c -d:release --mm:orc src/donkey
CMD ["./donkey", "--config", "/config/donkey.toml"]
```

### Build

```bash
docker build -t donkey .
```

### Run

```bash
docker run -d \
  --name donkey \
  -v ~/.donkey:/root/.donkey \
  -v ~/.config/donkey:/root/.config/donkey \
  --restart unless-stopped \
  donkey
```

### Docker Compose

```yaml
version: '3'
services:
  donkey:
    image: donkey
    volumes:
      - ~/.donkey:/root/.donkey
      - ~/.config/donkey:/root/.config/donkey
    restart: unless-stopped
```

## Reverse Proxy

### Nginx

```nginx
server {
    listen 443 ssl;
    server_name donkey.example.com;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
```

### Caddy

```caddy
donkey.example.com {
    reverse_proxy localhost:8080
}
```

## SSL/TLS

### Let's Encrypt

```bash
# Install certbot
sudo apt install certbot

# Generate certificate
sudo certbot certonly --standalone -d donkey.example.com

# Renew
sudo certbot renew
```

### Certificate Path

```toml
[donkey]
ssl_cert = "/etc/letsencrypt/live/donkey.example.com/fullchain.pem"
ssl_key = "/etc/letsencrypt/live/donkey.example.com/privkey.pem"
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DONKEY_HOME` | Home directory | `~/.donkey` |
| `DONKEY_CONFIG` | Config file path | `~/.config/donkey/donkey.toml` |
| `DONKEY_LOG_LEVEL` | Log level | from config |
| `DONKEY_SECRETS_KEY` | Encryption key | - |

## Secrets Management

### Generate Encryption Key

```bash
openssl rand -hex 32
```

### Set Key

```bash
export DONKEY_SECRETS_KEY="your-32-byte-hex-key"
```

Or in systemd:

```bash
mkdir -p ~/.config/systemd/user/donkey.service.d
```

Create `override.conf`:

```ini
[Service]
Environment=DONKEY_SECRETS_KEY=your-32-byte-hex-key
```

## Monitoring

### Health Check

```bash
# Check if running
systemctl --user is-active donkey

# Check logs
journalctl --user -u donkey -n 100
```

### Metrics

Donkey exposes metrics via IPC:

```bash
# Query status
echo "status" | nc -U ~/.donkey/donkey.sock

# Query logs
echo "logs 100" | nc -U ~/.donkey/donkey.sock
```

## Backup

### Files to Backup

```bash
# Donkey home
~/.donkey

# Configuration
~/.config/donkey

# Paddocks
~/.donkey/paddocks
```

### Backup Script

```bash
#!/bin/bash
BACKUP_DIR="/backup/donkey-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
tar czf "$BACKUP_DIR/donkey-config.tar.gz" ~/.config/donkey
tar czf "$BACKUP_DIR/donkey-data.tar.gz" ~/.donkey/paddocks
```

## Updates

### Manual Update

```bash
# Pull latest
git pull

# Rebuild
nim c -d:release --mm:orc src/donkey

# Restart
systemctl --user restart donkey
```

### Automatic Updates

Add to systemd timer or cron:

```bash
# Daily update check
0 2 * * * cd /path/to/donkey && git pull && nim c -d:release --mm:orc src/donkey
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
journalctl --user -u donkey -e

# Check config
./donkey --config ~/.config/donkey/donkey.toml --dry-run
```

### Permission Issues

```bash
# Fix permissions
chmod 600 ~/.config/donkey/donkey.toml
chmod 700 ~/.donkey
chmod 700 ~/.donkey/paddocks
```

### Memory Issues

```bash
# Check memory
free -h

# Monitor donkey
top -p $(pgrep donkey)
```

## Security

### Firewall

```bash
# UFW
sudo ufw allow 22/tcp    # SSH
sudo ufw enable
```

### Fail2Ban

```bash
sudo apt install fail2ban
```

Create `/etc/fail2ban/jail.local`:

```ini
[donkey]
enabled = true
port = 8080
filter = donkey
maxretry = 5
bantime = 3600
findtime = 600
```

## Related

- [Configuration Reference](../reference/configuration.md)
- [Security](../topics/security.md)
