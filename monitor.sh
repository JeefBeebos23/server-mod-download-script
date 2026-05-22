#!/bin/bash
# =============================================================================
# Minecraft Server Health Monitor
# Run every 5 minutes via cron to detect unexpected downtime.
# Sends one ntfy.sh alert when the server goes down, and a recovery notice
# when it comes back up. Stays silent during the maintenance window (4–5 AM).
#
# SETUP:
#   1. Set NTFY_TOPIC to match the value in maintenance.sh
#   2. Add to root crontab: */5 * * * * /opt/minecraft/monitor.sh
# =============================================================================

NTFY_TOPIC="your-unique-topic-here"   # <-- CHANGE THIS (must match maintenance.sh)
SCREEN_SESSION="minecraft"
FLAG_FILE="/tmp/mc_server_down_flag"

# Silence alerts during the nightly maintenance window (4:00–5:00 AM)
HOUR=$(date +%H)
if [ "$HOUR" -eq "04" ]; then
    exit 0
fi

notify() {
    local title="$1"
    local priority="$2"
    local message="$3"
    curl -s \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -d "$message" \
        "https://ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
}

if ! screen -list | grep -q "$SCREEN_SESSION"; then
    # Server is down
    if [ ! -f "$FLAG_FILE" ]; then
        # First time we've noticed it — alert once and set the flag
        touch "$FLAG_FILE"
        notify \
            "MC Server is DOWN" \
            "urgent" \
            "The Minecraft server stopped unexpectedly at $(date '+%I:%M %p'). SSH in to investigate or restart manually."
    fi
else
    # Server is running — clear the flag if it was set
    if [ -f "$FLAG_FILE" ]; then
        rm -f "$FLAG_FILE"
        notify \
            "MC Server Recovered" \
            "default" \
            "The Minecraft server is back online as of $(date '+%I:%M %p')."
    fi
fi
