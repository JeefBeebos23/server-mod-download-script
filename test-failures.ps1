# Quick script to retry only the previously-failed mods.
# Downloads to .\test-output\ - does not touch your real mods folder.

$MC_VERSION = "26.1.2"
$MODS_DIR   = Join-Path $PSScriptRoot "test-output"

function Write-Ok     { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Err    { param($m) Write-Host "  [XX] $m" -ForegroundColor Red }
function Write-Info   { param($m) Write-Host "  [..] $m" -ForegroundColor Cyan }

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

$failures = @(
    'https://www.curseforge.com/minecraft/mc-mods/entityculling',
    'https://www.curseforge.com/minecraft/mc-mods/exp-ore',
    'https://www.curseforge.com/minecraft/mc-mods/patpat',
    'https://www.curseforge.com/minecraft/mc-mods/echoes-of-the-end-structures',
    'https://www.curseforge.com/minecraft/mc-mods/rottenflesh-smelt-to-leather',
    'https://www.curseforge.com/minecraft/mc-mods/agritech',
    'https://modrinth.com/mod/mcpitanlibarch',
    'https://www.curseforge.com/minecraft/mc-mods/particleanimationlib'
)

Clear-Host
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Blue
Write-Host "   Retry Failed Mods - MC $MC_VERSION Fabric" -ForegroundColor Blue
Write-Host "  ================================================" -ForegroundColor Blue
Write-Host ""

Write-Host "  Get a free API key at: https://console.curseforge.com/" -ForegroundColor DarkGray
Write-Host ""
$CF_API_KEY = Read-Host "  Paste your CurseForge API key"
$CF_API_KEY = $CF_API_KEY.Trim()
if (-not $CF_API_KEY) {
    Write-Host "  [XX] No API key entered. Exiting." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Path $MODS_DIR)) {
    New-Item -ItemType Directory -Path $MODS_DIR | Out-Null
}

$cfHeaders = @{ "x-api-key" = $CF_API_KEY }
$success   = 0
$failed    = New-Object System.Collections.Generic.List[string]

Write-Host ""
Write-Host "--- Downloading $($failures.Count) mods ---" -ForegroundColor Blue
Write-Host ""

foreach ($url in $failures) {

    if ($url -match 'curseforge\.com/minecraft/mc-mods/([^/]+)') {
        $slug = $Matches[1]
        Write-Info "CF: $slug"

        try {
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

            $filesUri = "https://api.curseforge.com/v1/mods/$modId/files?gameVersion=$MC_VERSION" + "&modLoaderType=4&pageSize=20"
            $files = Invoke-RestMethod -Uri $filesUri -Headers $cfHeaders -ErrorAction Stop

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

            $file     = $files.data | Sort-Object { [datetime]$_.fileDate } -Descending | Select-Object -First 1
            $fileName = $file.fileName
            $dlUrl    = $file.downloadUrl

            if (-not $dlUrl) {
                $id    = [int]$file.id
                $dlUrl = "https://mediafilez.forgecdn.net/files/" + [int]($id / 1000) + "/" + ($id % 1000) + "/$fileName"
            }

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
    }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "  ================================================" -ForegroundColor Green
    Write-Host "   Done - $success/$($failures.Count) succeeded" -ForegroundColor Green
    Write-Host "  ================================================" -ForegroundColor Green
} else {
    Write-Host "  ================================================" -ForegroundColor Yellow
    Write-Host "   Done - $success/$($failures.Count) succeeded, $($failed.Count) still failing" -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Still failing:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
}

Write-Host ""
Write-Host "  Output: $MODS_DIR" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to exit"
