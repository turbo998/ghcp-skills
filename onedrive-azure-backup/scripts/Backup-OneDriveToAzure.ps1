<#
.SYNOPSIS
  Monthly incremental backup of a local OneDrive-synced folder to Azure Blob
  Storage using `azcopy sync`.

.DESCRIPTION
  This is the PREFERRED tool for recurring (repeat) OneDrive backups after the
  initial full `azcopy copy` has completed. It:

  - Auto-locates azcopy.exe under the WinGet packages folder (fails fast with a
    clear message if AzCopy is not installed).
  - Verifies the Azure CLI is logged in; if not, prints instructions to run
    `az login` and exits non-zero.
  - Generates a FRESH short-lived container SAS token each run (expiry = now +
    1 day) using the storage account key. The key/SAS never persist on disk.
  - Runs `azcopy sync` with `--delete-destination=false`, so files removed
    locally are NEVER deleted from the backup (append-only safety).
  - Excludes the WeChat live-churning cache (`Documents\xwechat_files`) which
    otherwise causes 'file in use' / 'source modified during transfer' thrash.
  - Tees all output to a timestamped log under $env:TEMP and appends a
    DONE_MARKER_EXIT_CODE completion sentinel.
  - Parses and prints the AzCopy final summary block, then exits with AzCopy's
    exit code.

  Designed to run monthly (e.g. on the 1st of each month) via Windows Task
  Scheduler or a Copilot scheduled workflow. Because it uses `azcopy sync`, only
  new/changed files are uploaded on each run.

.PARAMETER Source
  Local OneDrive folder to back up.

.PARAMETER ResourceGroup
  Azure resource group holding the storage account.

.PARAMETER StorageAccount
  Azure Storage account name.

.PARAMETER Container
  Blob container name.

.PARAMETER Prefix
  Destination prefix (virtual folder) inside the container.

.PARAMETER ExcludePath
  Semicolon-separated source-relative path(s) to exclude. Defaults to the WeChat
  live cache.

.EXAMPLE
  .\Backup-OneDriveToAzure.ps1

  Run with all defaults (this environment's OneDrive → stodbackupqc1981).

.EXAMPLE
  .\Backup-OneDriveToAzure.ps1 -Source 'C:\Users\alice\OneDrive - Contoso' -StorageAccount stcontosobackup

  Back up a different source to a different storage account.

.EXAMPLE
  # Scheduled monthly (Task Scheduler) on the 1st at 02:00:
  schtasks /Create /TN "OneDrive Azure Backup" /SC MONTHLY /D 1 /ST 02:00 `
    /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\path\to\Backup-OneDriveToAzure.ps1"
#>
[CmdletBinding()]
param(
    [string]$Source         = 'C:\Users\qichen2\OneDrive - Microsoft',
    [string]$ResourceGroup  = 'rg-onedrive-backup',
    [string]$StorageAccount = 'stodbackupqc1981',
    [string]$Container       = 'onedrive-backup',
    [string]$Prefix          = 'full-backup/OneDrive - Microsoft',
    [string]$ExcludePath     = 'Documents\xwechat_files'
)

$ErrorActionPreference = 'Stop'

function Fail {
    param([string]$Message, [int]$Code = 1)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit $Code
}

# --- 1. Locate azcopy.exe -----------------------------------------------------
Write-Host "==> Locating azcopy.exe" -ForegroundColor Cyan
$azcopy = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Microsoft.Azure.AZCopy.10_*" `
    -Recurse -Filter azcopy.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $azcopy) {
    Fail "azcopy.exe not found under WinGet packages. Install it with: winget install Microsoft.Azure.AZCopy.10"
}
Write-Host "    $azcopy"

# --- 2. Verify Azure CLI login ------------------------------------------------
Write-Host "==> Verifying Azure CLI login" -ForegroundColor Cyan
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Fail "Azure CLI (az) not found on PATH. Install with: winget install Microsoft.AzureCLI"
}
$account = az account show -o json 2>$null
if (-not $account) {
    Fail "Not logged in to Azure CLI. Run 'az login' to the target personal account, then re-run this script."
}
$acct = $account | ConvertFrom-Json
Write-Host ("    Subscription: {0} ({1})" -f $acct.name, $acct.id)

# --- 3. Generate a fresh short-lived container SAS ----------------------------
Write-Host "==> Generating fresh container SAS (expiry = now + 1 day)" -ForegroundColor Cyan
$key = az storage account keys list -g $ResourceGroup -n $StorageAccount --query "[0].value" -o tsv 2>$null
if (-not $key) {
    Fail "Failed to retrieve storage account key for '$StorageAccount' in resource group '$ResourceGroup'."
}
$expiry = (Get-Date).ToUniversalTime().AddDays(1).ToString("yyyy-MM-ddTHH:mmZ")
# sync needs read+list on the source side plus write/create on destination -> racwdl
$sas = az storage container generate-sas --account-name $StorageAccount --account-key $key `
    -n $Container --permissions racwdl --expiry $expiry -o tsv 2>$null
if (-not $sas) {
    Fail "Failed to generate SAS token for container '$Container'."
}
$sas = $sas.Trim()

# --- 4. Run azcopy sync -------------------------------------------------------
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log = Join-Path $env:TEMP "onedrive_sync_$timestamp.log"
$dest = "https://$StorageAccount.blob.core.windows.net/$Container/$Prefix" + "?$sas"

Write-Host "==> Starting azcopy sync" -ForegroundColor Cyan
Write-Host "    Source: $Source"
Write-Host "    Dest  : https://$StorageAccount.blob.core.windows.net/$Container/$Prefix"
Write-Host "    Log   : $log"

& $azcopy sync $Source $dest `
    --recursive=true `
    --delete-destination=false `
    --exclude-path=$ExcludePath 2>&1 | Tee-Object -FilePath $log
$exitCode = $LASTEXITCODE

Add-Content -Path $log -Value "DONE_MARKER_EXIT_CODE=$exitCode"

# --- 5. Print concise summary -------------------------------------------------
Write-Host ""
Write-Host "==> AzCopy summary" -ForegroundColor Cyan
$summary = Select-String -Path $log -Pattern `
    'Number of File Transfers|Number of Folder Property Transfers|Total Number of Transfers|Number of Transfers Completed|Number of Transfers Failed|Number of Transfers Skipped|TotalBytesTransferred|Final Job Status' `
    -SimpleMatch | Select-Object -ExpandProperty Line
if ($summary) {
    $summary | ForEach-Object { Write-Host "    $_" }
} else {
    Write-Host "    (no summary block parsed — check the log: $log)" -ForegroundColor Yellow
}

if ($exitCode -eq 0) {
    Write-Host "==> Backup completed (exit code 0)." -ForegroundColor Green
} else {
    Write-Host "==> Backup finished with exit code $exitCode. Review the log: $log" -ForegroundColor Yellow
}

exit $exitCode
