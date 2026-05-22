#!/bin/bash
# =============================================================================
# Minecraft Server Installer
# Run this on your Ubuntu Server machine AFTER placing your Fabric server
# jar and mods in the same directory as this script.
#
# What this does:
#   - Installs Java 21, screen, curl
#   - Creates a dedicated 'minecraft' user
#   - Copies server files to /opt/minecraft
#   - Installs and enables the systemd service
#   - Sets up the maintenance and monitor cron jobs
#   - Prompts you for your ntfy.sh topic
#
# Usage:
#   chmod +x install.sh
#   sudo ./install.sh
# =============================================================================

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo ./install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="/opt/minecraft"

echo ""
echo "============================================"
echo "  Minecraft Fabric Server Installer"
echo "============================================"
echo ""

# --- Prompt for ntfy topic ---
read -rp "Enter your ntfy.sh topic (e.g. mc-myserver-alerts): " NTFY_TOPIC
if [ -z "$NTFY_TOPIC" ]; then
    echo "ERROR: ntfy topic cannot be empty."
    exit 1
fi

# --- Install dependencies ---
echo ""
echo "[1/7] Installing dependencies (Java 21, screen, curl)..."
apt-get update -y
apt-get install -y openjdk-21-jre-headless screen curl

# --- Create minecraft user ---
echo "[2/7] Creating 'minecraft' system user..."
if ! id -u minecraft > /dev/null 2>&1; then
    useradd -r -m -d "$SERVER_DIR" -s /bin/bash minecraft
    echo "      User 'minecraft' created."
else
    echo "      User 'minecraft' already exists — skipping."
fi

# --- Copy server files ---
echo "[3/7] Copying server files to $SERVER_DIR..."
mkdir -p "$SERVER_DIR"
cp -r "$SCRIPT_DIR"/. "$SERVER_DIR/"
chown -R minecraft:minecraft "$SERVER_DIR"
chmod +x "$SERVER_DIR/start.sh"
chmod +x "$SERVER_DIR/maintenance.sh"
chmod +x "$SERVER_DIR/monitor.sh"

# --- Inject ntfy topic ---
echo "[4/7] Configuring ntfy.sh topic in scripts..."
sed -i "s/your-unique-topic-here/$NTFY_TOPIC/g" "$SERVER_DIR/maintenance.sh"
sed -i "s/your-unique-topic-here/$NTFY_TOPIC/g" "$SERVER_DIR/monitor.sh"

# --- Install systemd service ---
echo "[5/7] Installing systemd service..."
cp "$SERVER_DIR/minecraft.service" /etc/systemd/system/minecraft.service
systemctl daemon-reload
systemctl enable minecraft
echo "      Service enabled — server will start automatically on boot."

# --- Set up cron jobs ---
echo "[6/7] Setting up cron jobs..."

# Maintenance at 12:00 UTC = 4:00 AM PST (adjust if you're in PDT / another timezone)
CRON_MAINTENANCE="0 12 * * * /opt/minecraft/maintenance.sh >> /var/log/minecraft-maintenance.log 2>&1"
# Health monitor every 5 minutes
CRON_MONITOR="*/5 * * * * /opt/minecraft/monitor.sh"

(crontab -l 2>/dev/null | grep -v "maintenance.sh" | grep -v "monitor.sh"; \
 echo "$CRON_MAINTENANCE"; \
 echo "$CRON_MONITOR") | crontab -

echo "      Maintenance cron: daily at 12:00 UTC (4:00 AM PST)"
echo "      Monitor cron: every 5 minutes"

# --- Accept EULA ---
echo "[7/7] Accepting Minecraft EULA..."
echo "eula=true" > "$SERVER_DIR/eula.txt"
chown minecraft:minecraft "$SERVER_DIR/eula.txt"

# --- Done ---
echo ""
echo "============================================"
echo "  Installation complete!"
echo "============================================"
echo ""
echo "  ntfy.sh topic : $NTFY_TOPIC"
echo "  Server dir    : $SERVER_DIR"
echo "  Java          : $(java -version 2>&1 | head -1)"
echo ""
echo "  To start the server now:"
echo "    sudo systemctl start minecraft"
echo ""
echo "  To watch the console:"
echo "    sudo -u minecraft screen -r minecraft"
echo "    (Press Ctrl+A then D to detach)"
echo ""
echo "  IMPORTANT: On your phone, install the ntfy app and"
echo "  subscribe to topic: $NTFY_TOPIC"
echo ""
echo "  Timezone note: The maintenance window is set to 12:00 UTC"
echo "  = 4:00 AM PST / 5:00 AM PDT. If your server clock is not UTC,"
echo "  edit the crontab with: sudo crontab -e"
echo ""
