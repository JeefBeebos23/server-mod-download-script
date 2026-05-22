#!/bin/bash
# =============================================================================
# Minecraft Server Start Script
# Called by minecraft.service on boot and after reboots.
#
# Adjust -Xmx to change max RAM allocation (4G on 8GB system).
# Adjust the jar filename if yours differs from fabric-server-launch.jar.
# =============================================================================

SERVER_DIR="/opt/minecraft"
JAR="fabric-server-launch.jar"
MAX_RAM="4G"
MIN_RAM="2G"
SCREEN_SESSION="minecraft"

cd "$SERVER_DIR" || exit 1

# SCREENDIR must be consistent so backup.sh and maintenance.sh can find the session
export SCREENDIR=/opt/minecraft/.screen
mkdir -p "$SCREENDIR"

# Launch server inside a named screen session so you can attach to it anytime:
#   screen -r minecraft
screen -dmS "$SCREEN_SESSION" \
    java \
        -Xmx$MAX_RAM \
        -Xms$MIN_RAM \
        -XX:+UseG1GC \
        -XX:+ParallelRefProcEnabled \
        -XX:MaxGCPauseMillis=200 \
        -jar "$JAR" nogui

echo "Minecraft server started in screen session '$SCREEN_SESSION'"
echo "Attach with: screen -r $SCREEN_SESSION"
