#!/bin/bash
# =============================================================================
# Minecraft Server Maintenance Script
# Warns players at 4:00 AM, saves/stops at 4:15 AM, updates system, reboots.
# Server auto-restarts on boot via systemd (minecraft.service).
#
# SETUP:
#   1. Set NTFY_TOPIC to your chosen topic string (anything unique, e.g. "mc-myserver-alerts")
#   2. Set SERVER_DIR to wherever your server files live
#   3. Make executable: chmod +x /opt/minecraft/maintenance.sh
#   4. Add to root crontab: 0 12 * * * /opt/minecraft/maintenance.sh
#      (12:00 UTC = 4:00 AM PST / 5:00 AM PDT — adjust if needed)
# =============================================================================

NTFY_TOPIC="mc-myserver-alerts"
SERVER_DIR="/opt/minecraft"
export SCREENDIR=/opt/minecraft/.screen
SCREEN_SESSION="minecraft"
LOG_FILE="/var/log/minecraft-maintenance.log"
LOCK_FILE="/var/run/minecraft-maintenance.lock"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

notify() {
    local title="$1"
    local message="$2"
    local priority="${3:-default}"
    curl -s \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -d "$message" \
        "https://ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
}

server_running() {
    screen -list | grep -q "$SCREEN_SESSION"
}

mc_say() {
    if server_running; then
        screen -S "$SCREEN_SESSION" -X stuff "say $1$(printf '\r')"
        sleep 1
    fi
}

mc_cmd() {
    if server_running; then
        screen -S "$SCREEN_SESSION" -X stuff "$1$(printf '\r')"
        sleep 1
    fi
}

# Prevent concurrent runs (e.g. if cron fires while a previous run is still sleeping)
if [ -f "$LOCK_FILE" ]; then
    log "WARNING: Another maintenance run is already in progress (lock file exists). Exiting."
    exit 0
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# Trap unexpected errors
handle_error() {
    log "ERROR: Unexpected error on line $1"
    notify "MC Server - ERROR" "Maintenance script hit an unexpected error on line $1. Check $LOG_FILE on the server." "urgent"
    exit 1
}
trap 'handle_error $LINENO' ERR

# -----------------------------------------------------------------------------
# 4:00 AM — First warning
# -----------------------------------------------------------------------------

log "=========================================="
log "Maintenance window started"
log "=========================================="
notify "MC Server" "Maintenance starting. Server will shut down at 4:15 AM for updates and reboot."

if server_running; then
    mc_say "[MAINTENANCE] Server will restart for updates in 15 minutes. Please find a safe spot!"
    log "Sent 15-minute warning to players"
else
    log "WARNING: Server was not running at the start of the maintenance window"
    notify "MC Server - Warning" "Server was already offline at the start of the maintenance window (4:00 AM)." "high"
fi

# -----------------------------------------------------------------------------
# 4:10 AM — Second warning
# -----------------------------------------------------------------------------

sleep 600

if server_running; then
    mc_say "[MAINTENANCE] Server restart in 5 minutes. Wrap up what you're doing!"
    log "Sent 5-minute warning to players"
fi

# -----------------------------------------------------------------------------
# 4:14 AM — Final warning
# -----------------------------------------------------------------------------

sleep 240

if server_running; then
    mc_say "[MAINTENANCE] Server restarting in 1 minute. Disconnecting soon!"
    log "Sent 1-minute warning to players"
fi

# -----------------------------------------------------------------------------
# 4:15 AM — Save and stop
# -----------------------------------------------------------------------------

sleep 60
log "Saving world and stopping server..."

if server_running; then
    mc_cmd "save-all"
    sleep 15  # Give the world time to finish saving

    mc_cmd "stop"

    # Wait up to 60 seconds for a clean shutdown
    WAITED=0
    while server_running && [ "$WAITED" -lt 60 ]; do
        sleep 5
        WAITED=$((WAITED + 5))
    done

    if server_running; then
        log "Server did not stop cleanly — force-killing screen session"
        screen -S "$SCREEN_SESSION" -X quit || true  # session may have just died; don't trigger error trap
        notify "MC Server - Warning" "Server did not stop cleanly and was force-killed before updates." "high"
    else
        log "Server stopped cleanly after ${WAITED}s"
    fi
else
    log "Server was already offline at shutdown time — continuing with updates"
fi

# -----------------------------------------------------------------------------
# System updates
# -----------------------------------------------------------------------------

log "Running apt update..."
if ! apt-get update -y >> "$LOG_FILE" 2>&1; then
    log "ERROR: apt update failed"
    notify "MC Server - ERROR" "apt update failed during maintenance. Server has NOT rebooted. Manual fix needed." "urgent"
    exit 1
fi

log "Running apt upgrade..."
if ! apt-get upgrade -y >> "$LOG_FILE" 2>&1; then
    log "ERROR: apt upgrade failed"
    notify "MC Server - ERROR" "apt upgrade failed during maintenance. Server has NOT rebooted. Manual fix needed." "urgent"
    exit 1
fi

log "Running apt autoremove..."
apt-get autoremove -y >> "$LOG_FILE" 2>&1

log "System updates complete. Rebooting..."
notify "MC Server" "Updates complete. Rebooting now — server will be back online in ~2 minutes."

# -----------------------------------------------------------------------------
# Reboot (systemd minecraft.service will start the server on boot)
# -----------------------------------------------------------------------------

reboot
