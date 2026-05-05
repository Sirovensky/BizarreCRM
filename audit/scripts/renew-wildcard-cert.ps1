#Requires -Version 5.1
<#
.SYNOPSIS
    Daily renewal check for the BizarreCRM Let's Encrypt wildcard cert.

.DESCRIPTION
    Called by the 'BizarreCRM-LE-Renew' scheduled task (registered by
    setup-wildcard-cert.ps1). Runs Posh-ACME's built-in renewal logic:
    if the cert is within the renewal window (default: 30 days before
    expiry), it re-issues via Cloudflare DNS-01 using the API token
    stored by the initial setup. If not due for renewal yet, it's a
    fast no-op.

    If a renewal occurs, the new cert + key are copied to
    packages/server/certs/server.cert + server.key, and pm2 is told
    to restart bizarre-crm so the running process picks up the new
    cert on its next TLS handshake.

    All actions (and no-ops) are logged to
    packages/server/data/logs/le-renew.log with timestamps, so the
    operator can audit history.

    Safe to re-run manually any time:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\renew-wildcard-cert.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'  # log errors but don't crash the scheduled task
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir '..')
$EnvFile     = Join-Path $ProjectRoot '.env'
$CertsDir    = Join-Path $ProjectRoot 'packages\server\certs'
$CertFile    = Join-Path $CertsDir 'server.cert'
$KeyFile     = Join-Path $CertsDir 'server.key'
$LogDir      = Join-Path $ProjectRoot 'packages\server\data\logs'
$LogFile     = Join-Path $LogDir 'le-renew.log'

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-LogLine {
    param([string]$Level, [string]$Msg)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Msg"
    Add-Content -Path $LogFile -Value $line
    # Also write to stdout in case run interactively
    Write-Host $line
}

Write-LogLine 'INFO' '--- Renewal check started ---'

try {
    # --- Load BASE_DOMAIN from .env ---------------------------------
    if (-not (Test-Path $EnvFile)) {
        Write-LogLine 'ERROR' ".env not found at $EnvFile -- aborting"
        exit 1
    }

    $envVars = @{}
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $parts = $line.Split('=', 2)
            $envVars[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
    $BaseDomain = $envVars['BASE_DOMAIN']

    if (-not $BaseDomain -or $BaseDomain -eq 'localhost' -or $BaseDomain.EndsWith('.localhost')) {
        Write-LogLine 'ERROR' "BASE_DOMAIN not set or is localhost-only -- cannot renew"
        exit 1
    }

    # --- Load Posh-ACME ---------------------------------------------
    if (-not (Get-Module -ListAvailable -Name Posh-ACME)) {
        Write-LogLine 'ERROR' 'Posh-ACME module not found. Run setup-wildcard-cert.ps1 first.'
        exit 1
    }
    Import-Module Posh-ACME -Force

    # --- Check current cert state -----------------------------------
    $mainDomain  = "*.$BaseDomain"
    $certBefore  = Get-PACertificate -MainDomain $mainDomain -ErrorAction SilentlyContinue
    if (-not $certBefore) {
        Write-LogLine 'ERROR' "No existing cert found for $mainDomain in Posh-ACME store. Run setup-wildcard-cert.ps1 first."
        exit 1
    }

    $daysUntilExpiry = [int]($certBefore.NotAfter - (Get-Date)).TotalDays
    Write-LogLine 'INFO' "Current cert expires $($certBefore.NotAfter.ToString('yyyy-MM-dd')) ($daysUntilExpiry days from now)"

    # --- Run Posh-ACME's renewal (only acts if within window) -------
    # Submit-Renewal with no args renews only certs that are within 30 days of expiry.
    # If nothing is due, it returns quickly with no state change.
    Write-LogLine 'INFO' 'Running Submit-Renewal...'
    $renewalResult = Submit-Renewal -ErrorAction Continue 2>&1

    # --- Detect if the cert was actually renewed --------------------
    $certAfter = Get-PACertificate -MainDomain $mainDomain -ErrorAction SilentlyContinue
    $wasRenewed = $false
    if ($certAfter -and $certBefore -and $certAfter.NotAfter -ne $certBefore.NotAfter) {
        $wasRenewed = $true
    }

    if (-not $wasRenewed) {
        Write-LogLine 'INFO' 'No renewal needed (cert not yet within renewal window). Exiting cleanly.'
        Write-LogLine 'INFO' '--- Renewal check done (no-op) ---'
        exit 0
    }

    Write-LogLine 'INFO' "Cert RENEWED -- new expiry: $($certAfter.NotAfter.ToString('yyyy-MM-dd'))"

    # --- Copy new cert to the server's cert path -------------------
    # We do NOT back up the old cert here -- setup-wildcard-cert.ps1 already
    # made the initial .selfsigned.bak, and overwriting the LE cert with
    # the newer LE cert is expected behavior on every renewal.
    Copy-Item $certAfter.FullChainFile $CertFile -Force
    Copy-Item $certAfter.KeyFile       $KeyFile  -Force
    Write-LogLine 'INFO' "Installed new cert -> $CertFile"
    Write-LogLine 'INFO' "Installed new key  -> $KeyFile"

    # --- Restart pm2 so Node re-reads the cert files ---------------
    # Node's https.createServer reads the cert via fs.readFileSync at startup,
    # so a restart is required. pm2 graceful-restart keeps downtime minimal.
    $pm2Path = Join-Path $env:APPDATA 'npm\pm2.cmd'
    if (-not (Test-Path $pm2Path)) {
        # Fallback: try PATH
        $pm2Path = 'pm2'
    }
    Write-LogLine 'INFO' "Restarting pm2 bizarre-crm (using: $pm2Path)"
    try {
        & $pm2Path restart bizarre-crm 2>&1 | ForEach-Object { Write-LogLine 'INFO' "  pm2: $_" }
        if ($LASTEXITCODE -eq 0) {
            Write-LogLine 'INFO' 'pm2 restart succeeded -- server now serving new cert'
        } else {
            Write-LogLine 'WARN' "pm2 restart exited with code $LASTEXITCODE -- new cert is on disk but may not be loaded until next manual restart"
        }
    } catch {
        Write-LogLine 'ERROR' "pm2 restart failed: $($_.Exception.Message)"
        Write-LogLine 'WARN' 'New cert is on disk but server is still using the old one. Restart manually: pm2 restart bizarre-crm'
    }

    Write-LogLine 'INFO' '--- Renewal check done (renewed) ---'
    exit 0

} catch {
    Write-LogLine 'ERROR' "Unhandled exception: $($_.Exception.Message)"
    Write-LogLine 'ERROR' "Stack: $($_.ScriptStackTrace)"
    Write-LogLine 'INFO' '--- Renewal check done (failed) ---'
    exit 1
}
