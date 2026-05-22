#!/bin/bash
# backup.sh - Hourly Minecraft world backup
# Rotation: 5 hourly, 1 yesterday, 1 two-days-ago
# Warns if total backup directory exceeds MAX_GB

MINECRAFT_DIR="/opt/minecraft"
BACKUP_DIR="$MINECRAFT_DIR/backups"
WORLD_DIR="$MINECRAFT_DIR/world"
MAX_GB=5

mkdir -p "$BACKUP_DIR/hourly" "$BACKUP_DIR/daily"

# Flush world to disk before backing up
screen -S minecraft -p 0 -X stuff "save-off$(printf '\r')" 2>/dev/null
sleep 3
screen -S minecraft -p 0 -X stuff "save-all$(printf '\r')" 2>/dev/null
sleep 5

# Create compressed backup
TIMESTAMP=$(date '+%Y%m%d-%H%M')
OUTFILE="$BACKUP_DIR/hourly/world-$TIMESTAMP.tar.gz"
tar -czf "$OUTFILE" -C "$MINECRAFT_DIR" world 2>/dev/null

# Re-enable autosave
screen -S minecraft -p 0 -X stuff "save-on$(printf '\r')" 2>/dev/null

# Rotate hourlies: keep newest 5
ls -1t "$BACKUP_DIR/hourly"/world-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f

# Midnight: promote latest hourly to daily slot, rotate out oldest daily
if [ "$(date '+%H')" = "00" ]; then
    rm -f "$BACKUP_DIR/daily/daily-2.tar.gz"
    [ -f "$BACKUP_DIR/daily/daily-1.tar.gz" ] && \
        mv "$BACKUP_DIR/daily/daily-1.tar.gz" "$BACKUP_DIR/daily/daily-2.tar.gz"
    cp "$OUTFILE" "$BACKUP_DIR/daily/daily-1.tar.gz"
fi

# Warn if total backup size exceeds limit
TOTAL_MB=$(du -sm "$BACKUP_DIR" 2>/dev/null | cut -f1)
if [ "$TOTAL_MB" -gt $(( MAX_GB * 1024 )) ]; then
    echo "WARNING: Backup dir is ${TOTAL_MB}MB, over ${MAX_GB}GB limit" >&2
fi

SIZE=$(du -sh "$OUTFILE" 2>/dev/null | cut -f1)
echo "[$(date '+%Y-%m-%d %H:%M')] Backup done: $(basename "$OUTFILE") ($SIZE) | Total: ${TOTAL_MB}MB"
