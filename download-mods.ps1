# =============================================================================
#  download-mods.ps1 - Minecraft Mod Downloader
#  Reads modlist.txt and downloads all mods into your local mods folder.
#
#  Usage:  .\download-mods.ps1           (downloads to .minecraft\mods)
#          .\download-mods.ps1 -Test     (downloads to .\test-output\ instead)
#  Needs:  A free CurseForge API key -> https://console.curseforge.com/
# =============================================================================
param([switch]$Test)

# --- Config ------------------------------------------------------------------
$MC_VERSION = "26.1.2"
$MODS_DIR   = if ($Test) { Join-Path $PSScriptRoot "test-output" } else { "C:\Users\wbgui\AppData\Roaming\.minecraft\mods" }
$MODLIST    = Join-Path $PSScriptRoot "modlist.txt"
# -----------------------------------------------------------------------------

function Write-Ok     { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Err    { param($m) Write-Host "  [XX] $m" -ForegroundColor Red }
function Write-Info   { param($m) Write-Host "  [..] $m" -ForegroundColor Cyan }
function Write-Header { param($m) Write-Host "`n--- $m ---" -ForegroundColor Blue }

function Download-FromModrinth {
    param($slug, $outDir)
    $mrUri = "https://api.modrinth.com/v2/project/$slug/version" + "?game_versions=%5B%22$MC_VERSION%22%5D&loaders=%5B%22fabric%22%5D"
    $versions = Invoke-RestMethod -Uri $mrUri -ErrorAction Stop
    if (-not $versions -or $versions.Count -eq 0) { return $null }
    $latest = $versions | Sort-Object { [datetime]$_.date_published } -Descending | Select-Object -First 1
    $file = $latest.files | Where-Object { $_.primary } | Select-Object -First 1
    if (-not $file) { $file = $latest.files | Select-Object -First 1 }
    $outPath = Join-Path $outDir $file.filename
    Invoke-WebRequest -Uri $file.url -OutFile $outPath -ErrorAction Stop
    return $file.filename
}

Clear-Host
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Blue
Write-Host "   Minecraft Mod Downloader - MC $MC_VERSION Fabric" -ForegroundColor Blue
Write-Host "  ================================================" -ForegroundColor Blue
Write-Host ""

# --- Get API key -------------------------------------------------------------
Write-Host "  Get a free API key at: https://console.curseforge.com/" -ForegroundColor DarkGray
Write-Host ""
$CF_API_KEY = Read-Host "  Paste your CurseForge API key"
$CF_API_KEY = $CF_API_KEY.Trim()
if (-not $CF_API_KEY) {
    Write-Err "No API key entered. Exiting."
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Path $MODLIST)) {
    Write-Err "modlist.txt not found at: $MODLIST"
    Read-Host "Press Enter to exit"
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
        if ($confirm -eq "" -or $confirm -match '^[Yy]$') {
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
$failed    = New-Object System.Collections.Generic.List[string]

foreach ($url in $lines) {

    # --- CurseForge ----------------------------------------------------------
    if ($url -match 'curseforge\.com/minecraft/mc-mods/([^/]+)') {
        $slug = $Matches[1]
        Write-Info "CF: $slug"

        try {
            # 1. Resolve slug to mod ID
            $searchUri = "https://api.curseforge.com/v1/mods/search?gameId=432" + "&slug=$slug" + "&classId=6"
            $search = Invoke-RestMethod -Uri $searchUri -Headers $cfHeaders -ErrorAction Stop

            if ($search.data.Count -eq 0) {
                Write-Warn "  Not found on CurseForge, trying Modrinth: $slug"
                try {
                    $mrFile = Download-FromModrinth -slug $slug -outDir $MODS_DIR
                    if ($mrFile) { Write-Ok "  $mrFile (Modrinth)"; $success++ }
                    else { Write-Warn "  Not found anywhere: $slug"; $failed.Add($slug) }
                } catch { Write-Err "  $slug - Modrinth: $($_.Exception.Message)"; $failed.Add($slug) }
                continue
            }
            $modId = $search.data[0].id

            # 2. Get files - Fabric + exact MC version
            $filesUri = "https://api.curseforge.com/v1/mods/$modId/files?gameVersion=$MC_VERSION" + "&modLoaderType=4&pageSize=20"
            $files = Invoke-RestMethod -Uri $filesUri -Headers $cfHeaders -ErrorAction Stop

            # Fallback: any loader for this MC version
            if ($files.data.Count -eq 0) {
                $filesUri = "https://api.curseforge.com/v1/mods/$modId/files?gameVersion=$MC_VERSION" + "&pageSize=20"
                $files = Invoke-RestMethod -Uri $filesUri -Headers $cfHeaders -ErrorAction Stop
            }

            if ($files.data.Count -eq 0) {
                Write-Warn "  No CF files for $MC_VERSION, trying Modrinth: $slug"
                try {
                    $mrFile = Download-FromModrinth -slug $slug -outDir $MODS_DIR
                    if ($mrFile) { Write-Ok "  $mrFile (Modrinth)"; $success++ }
                    else { Write-Warn "  Not found anywhere: $slug"; $failed.Add($slug) }
                } catch { Write-Err "  $slug - Modrinth: $($_.Exception.Message)"; $failed.Add($slug) }
                continue
            }

            # 3. Pick latest
            $file     = $files.data | Sort-Object { [datetime]$_.fileDate } -Descending | Select-Object -First 1
            $fileName = $file.fileName
            $dlUrl    = $file.downloadUrl

            # Some authors disable API downloads - fall back to CDN URL
            if (-not $dlUrl) {
                $id    = [int]$file.id
                $dlUrl = "https://mediafilez.forgecdn.net/files/" + [int]($id / 1000) + "/" + ($id % 1000) + "/$fileName"
            }

            # 4. Download - fall back to Modrinth on 403
            $outPath = Join-Path $MODS_DIR $fileName
            try {
                Invoke-WebRequest -Uri $dlUrl -OutFile $outPath -ErrorAction Stop
                Write-Ok "  $fileName"
                $success++
            } catch {
                if ($_.Exception.Message -match '403') {
                    Write-Warn "  CF blocked (403), trying Modrinth: $slug"
                    try {
                        $mrFile = Download-FromModrinth -slug $slug -outDir $MODS_DIR
                        if ($mrFile) { Write-Ok "  $mrFile (Modrinth)"; $success++ }
                        else { Write-Warn "  Not on Modrinth either: $slug"; $failed.Add($slug) }
                    } catch { Write-Err "  $slug - Modrinth: $($_.Exception.Message)"; $failed.Add($slug) }
                } else {
                    Write-Err "  $slug - $($_.Exception.Message)"
                    $failed.Add($slug)
                }
            }

        } catch {
            Write-Err "  $slug - $($_.Exception.Message)"
            $failed.Add($slug)
        }

    # --- Modrinth ------------------------------------------------------------
    } elseif ($url -match 'modrinth\.com/mod/([^/]+)') {
        $slug = $Matches[1]
        Write-Info "MR: $slug"
        try {
            $mrFile = Download-FromModrinth -slug $slug -outDir $MODS_DIR
            if ($mrFile) { Write-Ok "  $mrFile"; $success++ }
            else { Write-Warn "  No $MC_VERSION Fabric file: $slug"; $failed.Add($slug) }
        } catch {
            Write-Err "  $slug - $($_.Exception.Message)"
            $failed.Add($slug)
        }

    # --- GitHub releases -----------------------------------------------------
    } elseif ($url -match 'github\.com') {
        $fileName = $url.Split('/')[-1]
        Write-Info "GitHub: $fileName"

        try {
            $outPath = Join-Path $MODS_DIR $fileName
            Invoke-WebRequest -Uri $url -OutFile $outPath -ErrorAction Stop
            Write-Ok "  $fileName"
            $success++
        } catch {
            Write-Err "  $url - $($_.Exception.Message)"
            $failed.Add($url)
        }

    } else {
        Write-Warn "Skipping unrecognised URL: $url"
    }
}

# --- Summary -----------------------------------------------------------------
Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "  ================================================" -ForegroundColor Green
    Write-Host "   Done - $success downloaded, 0 failed" -ForegroundColor Green
    Write-Host "  ================================================" -ForegroundColor Green
} else {
    Write-Host "  ================================================" -ForegroundColor Yellow
    Write-Host "   Done - $success downloaded, $($failed.Count) failed" -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Failed mods:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
}

Write-Host ""
Write-Host "  Mods saved to: $MODS_DIR" -ForegroundColor Cyan
Write-Host "  Run sync-mods.ps1 when ready to push to the server." -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to exit"
