# =============================================================================
#  download-mods.ps1 — Minecraft Mod Downloader
#  Reads modlist.txt and downloads all mods into your local mods folder.
#
#  Usage:  .\download-mods.ps1
#  Needs:  A free CurseForge API key → https://console.curseforge.com/
# =============================================================================

# --- Config ------------------------------------------------------------------
$MC_VERSION = "26.1.2"
$MODS_DIR   = "C:\Users\wbgui\AppData\Roaming\.minecraft\mods"
$MODLIST    = Join-Path $PSScriptRoot "modlist.txt"
# -----------------------------------------------------------------------------

function Write-Ok     { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Err    { param($m) Write-Host "  [XX] $m" -ForegroundColor Red }
function Write-Info   { param($m) Write-Host "  [..] $m" -ForegroundColor Cyan }
function Write-Header { param($m) Write-Host "`n--- $m ---" -ForegroundColor Blue }

Clear-Host
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Blue
Write-Host "   Minecraft Mod Downloader — MC $MC_VERSION Fabric" -ForegroundColor Blue
Write-Host "  ================================================" -ForegroundColor Blue
Write-Host ""

# --- Get API key -------------------------------------------------------------
Write-Host "  Get a free API key at: https://console.curseforge.com/" -ForegroundColor DarkGray
Write-Host ""
$CF_API_KEY = Read-Host "  Paste your CurseForge API key"
$CF_API_KEY = $CF_API_KEY.Trim()
if (-not $CF_API_KEY) {
    Write-Err "No API key entered. Exiting."
    Read-Host "`nPress Enter to exit"
    exit 1
}

if (-not (Test-Path $MODLIST)) {
    Write-Err "modlist.txt not found at: $MODLIST"
    Read-Host "`nPress Enter to exit"
    exit 1
}

# --- Prepare mods folder -----------------------------------------------------
Write-Header "Preparing mods folder"

if (-not (Test-Path $MODS_DIR)) {
    New-Item -ItemType Directory -Path $MODS_DIR | Out-Null
    Write-Ok "Created: $MODS_DIR"
} else {
    $existing = Get-ChildItem $MODS_DIR -Filter "*.jar"
    if ($existing.Count -gt 0) {
        Write-Warn "Found $($existing.Count) existing .jar(s) in mods folder."
        $confirm = Read-Host "  Clear them before downloading fresh copies? [Y/n]"
        if ($confirm -eq "" -or $confirm -match "^[Yy]$") {
            $existing | Remove-Item -Force
            Write-Ok "Cleared old mods"
        }
    }
}

# --- Read modlist ------------------------------------------------------------
$lines = Get-Content $MODLIST |
    Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' } |
    ForEach-Object { $_.Trim() }

Write-Header "Downloading $($lines.Count) mods"

$cfHeaders = @{ "x-api-key" = $CF_API_KEY }
$success   = 0
$failed    = [System.Collections.Generic.List[string]]::new()

foreach ($url in $lines) {

    # --- CurseForge ----------------------------------------------------------
    if ($url -match "curseforge\.com/minecraft/mc-mods/([^/?#]+)") {
        $slug = $Matches[1]
        Write-Info "CF: $slug"

        try {
            # 1. Resolve slug → mod ID
            $search = Invoke-RestMethod `
                -Uri "https://api.curseforge.com/v1/mods/search?gameId=432&slug=$slug&classId=6" `
                -Headers $cfHeaders -ErrorAction Stop

            if ($search.data.Count -eq 0) {
                Write-Warn "  Mod not found on CurseForge: $slug"
                $failed.Add($slug); continue
            }
            $modId = $search.data[0].id

            # 2. Get files — Fabric + exact MC version
            $files = Invoke-RestMethod `
                -Uri "https://api.curseforge.com/v1/mods/$modId/files?gameVersion=$MC_VERSION&modLoaderType=4&pageSize=20" `
                -Headers $cfHeaders -ErrorAction Stop

            # Fallback: any loader for this MC version
            if ($files.data.Count -eq 0) {
                $files = Invoke-RestMethod `
                    -Uri "https://api.curseforge.com/v1/mods/$modId/files?gameVersion=$MC_VERSION&pageSize=20" `
                    -Headers $cfHeaders -ErrorAction Stop
            }

            if ($files.data.Count -eq 0) {
                Write-Warn "  No files for $MC_VERSION : $slug"
                $failed.Add($slug); continue
            }

            # 3. Pick latest
            $file     = $files.data | Sort-Object { [datetime]$_.fileDate } -Descending | Select-Object -First 1
            $fileName = $file.fileName
            $dlUrl    = $file.downloadUrl

            # Some authors disable API downloads — fall back to CDN URL
            if (-not $dlUrl) {
                $id    = [int]$file.id
                $dlUrl = "https://mediafilez.forgecdn.net/files/$([int]($id / 1000))/$($id % 1000)/$fileName"
            }

            # 4. Download
            $outPath = Join-Path $MODS_DIR $fileName
            Invoke-WebRequest -Uri $dlUrl -OutFile $outPath -ErrorAction Stop
            Write-Ok "  $fileName"
            $success++

        } catch {
            Write-Err "  $slug — $($_.Exception.Message)"
            $failed.Add($slug)
        }

    # --- GitHub releases -----------------------------------------------------
    } elseif ($url -match "github\.com") {
        $fileName = $url.Split("/")[-1]
        Write-Info "GitHub: $fileName"

        try {
            $outPath = Join-Path $MODS_DIR $fileName
            Invoke-WebRequest -Uri $url -OutFile $outPath -ErrorAction Stop
            Write-Ok "  $fileName"
            $success++
        } catch {
            Write-Err "  $url — $($_.Exception.Message)"
            $failed.Add($url)
        }

    } else {
        Write-Warn "Skipping unrecognised URL: $url"
    }
}

# --- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "  ================================================" -ForegroundColor $(if ($failed.Count -eq 0) { "Green" } else { "Yellow" })
Write-Host "   Done — $success downloaded, $($failed.Count) failed" -ForegroundColor $(if ($failed.Count -eq 0) { "Green" } else { "Yellow" })
Write-Host "  ================================================"
Write-Host ""

if ($failed.Count -gt 0) {
    Write-Host "  Failed mods:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host ""
}

Write-Host "  Mods saved to: $MODS_DIR" -ForegroundColor Cyan
Write-Host "  Run sync-mods.ps1 when ready to push to the server." -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to exit"
