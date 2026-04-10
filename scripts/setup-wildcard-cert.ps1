#Requires -Version 5.1
<#
.SYNOPSIS
    One-time setup: issues a Let's Encrypt wildcard SSL cert for the
    BizarreCRM origin, via DNS-01 challenge using the Cloudflare API.

.DESCRIPTION
    Uses the existing CLOUDFLARE_API_TOKEN from .env to solve the DNS-01
    challenge, so no new credentials are required. Covers both the apex
    domain (e.g. bizarrecrm.com) and the wildcard (*.bizarrecrm.com) in a
    single cert, so the origin can serve valid HTTPS for ANY subdomain —
    provisioned or not. Combined with a wildcard DNS A record in Cloudflare
    (grey cloud), this eliminates the NXDOMAIN edge case where a browser
    visiting a subdomain BEFORE it exists caches a negative result that
    only clears via manual DNS flush.

    After issuing the cert, this script:
      - Backs up the existing server.cert + server.key to .selfsigned.bak
      - Writes the new LE cert + key to packages/server/certs/server.cert + .key
      - Registers a daily Windows Scheduled Task that runs
        scripts/renew-wildcard-cert.ps1 to keep the cert fresh (LE certs
        are valid 90 days; Posh-ACME renews at the 30-day mark)

    Safe to re-run. If a valid (not-near-expiry) cert already exists in
    the Posh-ACME store, this script will NOT re-issue — that would burn
    LE rate limits unnecessarily. Pass -Force to override.

.PARAMETER Force
    Re-issue the cert even if a valid one already exists in the
    Posh-ACME store. Use sparingly — LE rate limits are 50 certs per
    registered domain per week.

.PREREQUISITES
    1. .env in the project root containing CLOUDFLARE_API_TOKEN,
       CLOUDFLARE_ZONE_ID, and BASE_DOMAIN
    2. A wildcard DNS A record already added in Cloudflare:
         Type: A, Name: *, IPv4: <SERVER_PUBLIC_IP>, Proxy: DNS only (grey cloud)
    3. PowerShell 5.1+ (built into Windows 10/11/Server 2016+)
    4. Internet access (Posh-ACME module from PSGallery, Let's Encrypt servers,
       Cloudflare API)

.EXAMPLE
    # Run from an elevated PowerShell prompt in the project root:
    cd C:\Users\Administrator\BizarreCRM
    powershell.exe -ExecutionPolicy Bypass -File scripts\setup-wildcard-cert.ps1
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir '..')
$EnvFile     = Join-Path $ProjectRoot '.env'
$CertsDir    = Join-Path $ProjectRoot 'packages\server\certs'
$CertFile    = Join-Path $CertsDir 'server.cert'
$KeyFile     = Join-Path $CertsDir 'server.key'

function Write-Step { param([string]$Msg) Write-Host "`n[setup-wildcard-cert] $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  OK - $Msg" -ForegroundColor Green }
function Write-Warn2{ param([string]$Msg) Write-Host "  WARNING: $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "  ERROR: $Msg" -ForegroundColor Red }

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "    BizarreCRM - Wildcard SSL Cert Setup" -ForegroundColor Cyan
Write-Host "    (Let's Encrypt via Cloudflare DNS-01)" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan

# ─── Step 1: Load .env ────────────────────────────────────────────────
Write-Step "Step 1/7 - Loading .env"

if (-not (Test-Path $EnvFile)) {
    Write-Err ".env not found at $EnvFile"
    Write-Err "Run setup.bat first to generate it, or add CLOUDFLARE_* vars manually."
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

$CfToken    = $envVars['CLOUDFLARE_API_TOKEN']
$CfZoneId   = $envVars['CLOUDFLARE_ZONE_ID']
$BaseDomain = $envVars['BASE_DOMAIN']

if (-not $CfToken -or -not $CfZoneId -or -not $BaseDomain) {
    Write-Err "Missing required .env vars:"
    if (-not $CfToken)    { Write-Err "  CLOUDFLARE_API_TOKEN (empty)" }
    if (-not $CfZoneId)   { Write-Err "  CLOUDFLARE_ZONE_ID (empty)" }
    if (-not $BaseDomain) { Write-Err "  BASE_DOMAIN (empty)" }
    Write-Err ""
    Write-Err "Run setup.bat to regenerate .env with all sections, or add them manually."
    exit 1
}

if ($BaseDomain -eq 'localhost' -or $BaseDomain.EndsWith('.localhost')) {
    Write-Err "BASE_DOMAIN is '$BaseDomain' — Let's Encrypt cannot issue certs for localhost."
    Write-Err "This script is only for production domains (e.g. bizarrecrm.com)."
    exit 1
}

Write-Ok "BASE_DOMAIN = $BaseDomain"
# Never print any portion of the token — even a prefix is partial secret material.
# If pasted into a bug report or chat, even 4-8 chars can help an attacker confirm
# which org/account the token belongs to.
Write-Ok "CLOUDFLARE_API_TOKEN = (set, $($CfToken.Length) chars)"

# ─── Step 2: Ensure Posh-ACME module is installed ────────────────────
Write-Step "Step 2/7 - Ensuring Posh-ACME module is installed"

# Trust PSGallery so Install-Module doesn't prompt
$gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if ($gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
    Write-Host "  Marking PSGallery as trusted (needed for unattended install)..."
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}

# Ensure NuGet provider is present (required for Install-Module on fresh Windows)
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object Version -ge '2.8.5.201')) {
    Write-Host "  Installing NuGet package provider..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
}

if (-not (Get-Module -ListAvailable -Name Posh-ACME)) {
    Write-Host "  Installing Posh-ACME from PSGallery..."
    Install-Module -Name Posh-ACME -Scope CurrentUser -Force -AllowClobber
    Write-Ok "Posh-ACME installed"
} else {
    $poshAcme = Get-Module -ListAvailable -Name Posh-ACME | Select-Object -First 1
    Write-Ok "Posh-ACME already installed (version $($poshAcme.Version))"
}

Import-Module Posh-ACME -Force

# ─── Step 3: Point Posh-ACME at Let's Encrypt production ─────────────
Write-Step "Step 3/7 - Configuring ACME server"

Set-PAServer LE_PROD
Write-Ok "ACME server = LE_PROD (Let's Encrypt production)"

# ─── Step 4: Ensure an ACME account exists ───────────────────────────
Write-Step "Step 4/7 - Ensuring ACME account exists"

$account = Get-PAAccount -List -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $account) {
    Write-Host "  Creating new ACME account (contact: admin@$BaseDomain)..."
    New-PAAccount -AcceptTOS -Contact "admin@$BaseDomain" -Force | Out-Null
    Write-Ok "Account created"
} else {
    Write-Ok "Account already exists ($($account.Id))"
}

# ─── Step 5: Issue or reuse the wildcard cert ────────────────────────
Write-Step "Step 5/7 - Issuing wildcard certificate"

$mainDomain = "*.$BaseDomain"
$existingOrder = Get-PAOrder -MainDomain $mainDomain -ErrorAction SilentlyContinue

$needsIssue = $true
if ($existingOrder -and -not $Force) {
    try {
        $existingCert = Get-PACertificate -MainDomain $mainDomain -ErrorAction SilentlyContinue
        if ($existingCert -and $existingCert.NotAfter -gt (Get-Date).AddDays(30)) {
            Write-Ok "Valid cert already exists (expires $($existingCert.NotAfter.ToString('yyyy-MM-dd')))"
            Write-Host "  Skipping issuance — use -Force to re-issue anyway."
            $needsIssue = $false
        }
    } catch { }
}

if ($needsIssue) {
    Write-Host "  Requesting wildcard cert for: $mainDomain + $BaseDomain"
    Write-Host "  (This will add a _acme-challenge TXT record to Cloudflare, wait for"
    Write-Host "   propagation, let LE validate, then receive the signed cert.)"
    Write-Host ""

    $cfTokenSecure = ConvertTo-SecureString $CfToken -AsPlainText -Force
    $pluginArgs = @{ CFToken = $cfTokenSecure }

    # The Cloudflare plugin in Posh-ACME auto-discovers the zone from the domain,
    # but we pass the token that has Zone.DNS:Edit scope on our zone.
    New-PACertificate `
        -Domain $mainDomain, $BaseDomain `
        -AcceptTOS `
        -DnsPlugin Cloudflare `
        -PluginArgs $pluginArgs `
        -Force | Out-Null

    Write-Ok "Cert issued by Let's Encrypt"
}

$cert = Get-PACertificate -MainDomain $mainDomain
if (-not $cert) {
    Write-Err "Failed to retrieve cert from Posh-ACME store"
    exit 1
}

Write-Ok "Cert valid from $($cert.NotBefore.ToString('yyyy-MM-dd')) to $($cert.NotAfter.ToString('yyyy-MM-dd'))"
Write-Ok "Subject: $($cert.Subject)"

# ─── Step 6: Back up existing cert + install new one ─────────────────
Write-Step "Step 6/7 - Installing cert to packages/server/certs/"

if (-not (Test-Path $CertsDir)) {
    New-Item -Path $CertsDir -ItemType Directory -Force | Out-Null
}

# Back up existing files (per the project rule: preserve, don't delete)
$backupSuffix = ".selfsigned.bak"
if (Test-Path $CertFile) {
    $backupCert = $CertFile + $backupSuffix
    if (-not (Test-Path $backupCert)) {
        Copy-Item $CertFile $backupCert -Force
        Write-Ok "Backed up old cert -> $(Split-Path $backupCert -Leaf)"
    } else {
        Write-Ok "Old cert backup already exists, leaving it alone"
    }
}
if (Test-Path $KeyFile) {
    $backupKey = $KeyFile + $backupSuffix
    if (-not (Test-Path $backupKey)) {
        Copy-Item $KeyFile $backupKey -Force
        Write-Ok "Backed up old key -> $(Split-Path $backupKey -Leaf)"
    } else {
        Write-Ok "Old key backup already exists, leaving it alone"
    }
}

# FullChainFile = cert + intermediate chain, which is what browsers want
# KeyFile = the private key in PEM format
Copy-Item $cert.FullChainFile $CertFile -Force
Copy-Item $cert.KeyFile       $KeyFile  -Force
Write-Ok "Installed cert  -> $CertFile"
Write-Ok "Installed key   -> $KeyFile"

# ─── Step 7: Register the renewal scheduled task ─────────────────────
Write-Step "Step 7/7 - Registering BizarreCRM-LE-Renew scheduled task"

$taskName   = 'BizarreCRM-LE-Renew'
$renewScript = Join-Path $ScriptDir 'renew-wildcard-cert.ps1'

if (-not (Test-Path $renewScript)) {
    Write-Warn2 "Renew script not found at $renewScript"
    Write-Warn2 "Scheduled task will NOT be registered. Create the renew script and re-run this setup."
} else {
    # Remove any prior task with the same name (idempotent)
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "  Removed prior task with the same name"
    }

    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$renewScript`""
    # Off-hour + non-:00 minute (per project convention of avoiding exact 0/30 marks
    # to spread load across the Windows task scheduler fleet).
    $trigger   = New-ScheduledTaskTrigger -Daily -At '3:17AM'
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable

    try {
        # S4U = run even when user is not logged in, no password needed, no interactive access.
        # Requires running THIS setup script as admin (or current user with task scheduler rights).
        Register-ScheduledTask `
            -TaskName $taskName `
            -Description 'BizarreCRM: daily Let''s Encrypt wildcard cert renewal check (Posh-ACME)' `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -User $env:USERNAME `
            -RunLevel Highest `
            -LogonType S4U | Out-Null
        Write-Ok "Scheduled task '$taskName' registered (runs daily at 03:17 as $env:USERNAME)"
    } catch {
        Write-Warn2 "Failed to register scheduled task: $($_.Exception.Message)"
        Write-Warn2 "You may need to run this script from an elevated PowerShell prompt."
        Write-Warn2 "Cert is installed; only the auto-renewal is missing. You can register it later."
    }
}

# ─── Done ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "    Wildcard cert setup complete!" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "    1. Confirm the wildcard DNS A record exists in Cloudflare:"
Write-Host "         Type: A, Name: *, IPv4: <your server public IP>,"
Write-Host "         Proxy: DNS only (grey cloud)"
Write-Host ""
Write-Host "    2. Restart the server to pick up the new cert:"
Write-Host "         pm2 restart bizarre-crm"
Write-Host ""
Write-Host "    3. Test an un-provisioned subdomain (should return HTTP 404, not 'Server Not Found'):"
Write-Host "         curl.exe -v https://totally-fake-shop-xyz.$BaseDomain/"
Write-Host ""
Write-Host "  Cert auto-renewal: scheduled task '$taskName' runs daily at 03:17."
Write-Host "  Renewal log: packages\server\data\logs\le-renew.log"
Write-Host ""
