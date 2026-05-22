# =============================================================================
#  sync-mods.ps1 — Minecraft Mod Sync Script
#  Syncs your local .minecraft\mods folder to the server over SSH.
#
#  Usage:  Right-click → "Run with PowerShell"
#          Or from a terminal: powershell -ExecutionPolicy Bypass -File sync-mods.ps1
#
#  SETUP:
#    1. Make sure SSH key auth is set up OR be ready to type your password a few times
#    2. Adjust $SERVER_USER if your Linux username isn't "user"
# =============================================================================

# --- Config ------------------------------------------------------------------
$SERVER_IP   = "192.168.0.76"
$SERVER_USER = "user"
$LOCAL_MODS  = "C:\Users\wbgui\AppData\Roaming\.minecraft\mods"
$REMOTE_MODS = "/opt/minecraft/mods"
# -----------------------------------------------------------------------------

# Colors
function Write-Ok    { param($msg) Write-Host "  [OK] $msg"   -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!!] $msg"   -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "  [XX] $msg"   -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host "  [..] $msg"   -ForegroundColor Cyan }
function Write-Header{ param($msg) Write-Host "`n--- $msg ---" -ForegroundColor Blue }

Clear-Host
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Blue
Write-Host "   Minecraft Mod Sync — Local -> Server           " -ForegroundColor Blue
Write-Host "  ================================================" -ForegroundColor Blue
Write-Host ""

# --- Check local mods folder exists ------------------------------------------
Write-Header "Checking local mods"

if (-not (Test-Path $LOCAL_MODS)) {
    Write-Err "Local mods folder not found: $LOCAL_MODS"
    Write-Err "Check the path and update the script if needed."
    Read-Host "`nPress Enter to exit"
    exit 1
}

$localMods = Get-ChildItem -Path $LOCAL_MODS -Filter "*.jar"
if ($localMods.Count -eq 0) {
    Write-Warn "No .jar files found in $LOCAL_MODS"
    Read-Host "`nPress Enter to exit"
    exit 1
}

Write-Ok "Found $($localMods.Count) mod(s) in local folder:"
foreach ($mod in $localMods) {
    Write-Host "       $($mod.Name)" -ForegroundColor Gray
}

# --- Check SSH connection ----------------------------------------------------
Write-Header "Connecting to server"

Write-Info "Testing SSH connection to $SERVER_USER@$SERVER_IP ..."
$sshTest = ssh -o ConnectTimeout=5 -o BatchMode=yes "$SERVER_USER@$SERVER_IP" "echo ok" 2>&1
if ($sshTest -ne "ok") {
    Write-Warn "Password prompt may appear — that's normal if SSH keys aren't set up yet."
}

# --- Check if server is running ----------------------------------------------
Write-Header "Checking server status"

$serverStatus = ssh "$SERVER_USER@$SERVER_IP" "systemctl is-active minecraft" 2>&1
$serverWasRunning = $serverStatus.Trim() -eq "active"

if ($serverWasRunning) {
    Write-Warn "The Minecraft server is currently RUNNING."
    Write-Warn "It must be stopped to safely swap mods."
    Write-Host ""
    $confirm = Read-Host "  Stop the server, sync mods, then restart it? [Y/n]"
    if ($confirm -eq "" -or $confirm -match "^[Yy]$") {
        Write-Header "Stopping server"
        Write-Info "Sending stop command..."
        ssh "$SERVER_USER@$SERVER_IP" "sudo systemctl stop minecraft"
        Start-Sleep -Seconds 5

        # Confirm it stopped
        $statusAfterStop = ssh "$SERVER_USER@$SERVER_IP" "systemctl is-active minecraft" 2>&1
        if ($statusAfterStop.Trim() -eq "active") {
            Write-Err "Server did not stop cleanly. Aborting to avoid corrupting mods."
            Read-Host "`nPress Enter to exit"
            exit 1
        }
        Write-Ok "Server stopped"
    } else {
        Write-Warn "Sync cancelled — server left running."
        Read-Host "`nPress Enter to exit"
        exit 0
    }
} else {
    Write-Ok "Server is not running — safe to sync"
}

# --- Sync mods ---------------------------------------------------------------
Write-Header "Syncing mods"

# Clear existing mods on server
Write-Info "Clearing old mods from server..."
ssh "$SERVER_USER@$SERVER_IP" "sudo rm -f $REMOTE_MODS/*.jar && sudo chown minecraft:minecraft $REMOTE_MODS"

# Copy new mods over
Write-Info "Uploading $($localMods.Count) mod(s)..."
foreach ($mod in $localMods) {
    Write-Host "       Uploading: $($mod.Name)" -ForegroundColor Gray
    scp "$($mod.FullName)" "${SERVER_USER}@${SERVER_IP}:${REMOTE_MODS}/"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to upload $($mod.Name)"
        if ($serverWasRunning) {
            Write-Warn "Attempting to restart server anyway..."
            ssh "$SERVER_USER@$SERVER_IP" "sudo systemctl start minecraft"
        }
        Read-Host "`nPress Enter to exit"
        exit 1
    }
}

# Fix permissions on uploaded files
ssh "$SERVER_USER@$SERVER_IP" "sudo chown -R minecraft:minecraft $REMOTE_MODS"

Write-Ok "All mods uploaded successfully"

# --- Verify remote mod count -------------------------------------------------
Write-Header "Verifying"

$remoteCount = ssh "$SERVER_USER@$SERVER_IP" "ls $REMOTE_MODS/*.jar 2>/dev/null | wc -l"
Write-Ok "Local mods : $($localMods.Count)"
Write-Ok "Server mods: $($remoteCount.Trim())"

if ($localMods.Count -ne [int]$remoteCount.Trim()) {
    Write-Warn "Mod counts don't match — double check the server's mods folder."
}

# --- Restart server if it was running ----------------------------------------
if ($serverWasRunning) {
    Write-Header "Restarting server"
    Write-Info "Starting Minecraft server..."
    ssh "$SERVER_USER@$SERVER_IP" "sudo systemctl start minecraft"
    Start-Sleep -Seconds 5

    $finalStatus = ssh "$SERVER_USER@$SERVER_IP" "systemctl is-active minecraft" 2>&1
    if ($finalStatus.Trim() -eq "active") {
        Write-Ok "Server is back online!"
    } else {
        Write-Err "Server didn't start — check the logs with: journalctl -u minecraft -n 50"
    }
} else {
    Write-Host ""
    Write-Warn "Server was not running before sync — start it manually when ready:"
    Write-Host "       sudo systemctl start minecraft" -ForegroundColor Gray
}

# --- Done --------------------------------------------------------------------
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "   Sync complete!                                 " -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  NOTE: Make sure your mods are server-compatible." -ForegroundColor Yellow
Write-Host "  Client-only mods (Sodium, Iris, etc.) will cause" -ForegroundColor Yellow
Write-Host "  the server to crash if left in the mods folder. " -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to exit"
