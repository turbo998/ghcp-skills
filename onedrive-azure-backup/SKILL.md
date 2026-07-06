---
name: onedrive-azure-backup
description: "Back up a local OneDrive-synced folder to Azure Blob Storage using AzCopy on Windows. Covers Azure resource provisioning (resource group, storage account, container), SAS generation, PoC validation, full initial backup via `azcopy copy`, and recurring monthly incremental backup via `azcopy sync`. Handles WeChat live-cache exclusion, detached-job liveness verification, and volatile-source pitfalls. WHEN: 'backup onedrive', 'onedrive to azure', 'azcopy backup', 'monthly backup onedrive', 'back up my files to azure', 'azure blob backup windows'."
license: MIT
metadata:
  version: "1.0.0"
---

# OneDrive → Azure Blob Backup (AzCopy, Windows)

> Proven end-to-end workflow to back up `C:\Users\<user>\OneDrive - <Tenant>` (~185 GB, ~54k files) to Azure Blob Storage. First run = full backup; subsequent monthly runs = incremental sync.

## Overview

- **Tool:** AzCopy v10.32+ (Windows ARM64/x64)
- **Destination:** Azure Blob container `onedrive-backup`, prefix `full-backup/`
- **Auth:** Personal Azure account (az login) + container SAS token
- **Initial backup:** `azcopy copy --overwrite=false`
- **Recurring monthly:** `azcopy sync` (only new/changed files)

## When to Use

- First-time full backup of a large OneDrive folder to Azure
- Recurring monthly incremental backups
- Troubleshooting stalled/thrashing AzCopy jobs on volatile sources

## Quick Reference (this environment)

| Property | Value |
|---|---|
| Source | `C:\Users\qichen2\OneDrive - Microsoft` |
| Azure account | turbo998@hotmail.com (personal) |
| Resource group | `rg-onedrive-backup` |
| Storage account | `stodbackupqc1981` |
| Container | `onedrive-backup` |
| Region | East Asia |
| Backup prefix | `full-backup/OneDrive - Microsoft/` |
| AzCopy | `C:\Users\qichen2\AppData\Local\Microsoft\WinGet\Packages\Microsoft.Azure.AZCopy.10_*\azcopy_windows_arm64_10.32.4\azcopy.exe` |

## Prerequisites

1. AzCopy installed: `winget install Microsoft.Azure.AZCopy.10`
2. Azure CLI: `winget install Microsoft.AzureCLI`
3. `az login` to the target personal account.
4. OneDrive files hydrated locally (Files On-Demand may leave cloud-only placeholders; AzCopy reads them as 0-byte unless hydrated). Force hydration for critical folders if needed.

## One-Time Provisioning

```powershell
az group create -n rg-onedrive-backup -l eastasia
az storage account create -n stodbackupqc1981 -g rg-onedrive-backup -l eastasia --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2
az storage container create --account-name stodbackupqc1981 -n onedrive-backup --auth-mode login
```

## SAS Generation (regenerate whenever expired)

```powershell
$key = az storage account keys list -g rg-onedrive-backup -n stodbackupqc1981 --query "[0].value" -o tsv
$expiry = (Get-Date).AddMonths(13).ToString("yyyy-MM-ddTHH:mmZ")
$sas = az storage container generate-sas --account-name stodbackupqc1981 --account-key $key -n onedrive-backup --permissions racwdl --expiry $expiry -o tsv
$sas | Out-File "$env:TEMP\onedrive_backup_sas.txt" -NoNewline
```

## Initial Full Backup (`azcopy copy`)

Run the FULL backup once. Exclude WeChat live cache (see Pitfalls). Use `--overwrite=false` so aborted-and-retried runs skip already-uploaded files.

```powershell
$az = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Microsoft.Azure.AZCopy.10_*" -Recurse -Filter azcopy.exe).FullName
$sas = (Get-Content "$env:TEMP\onedrive_backup_sas.txt" -Raw).Trim()
$src = "C:\Users\qichen2\OneDrive - Microsoft"
$dst = "https://stodbackupqc1981.blob.core.windows.net/onedrive-backup/full-backup?$sas"
& $az copy $src $dst --recursive=true --overwrite=false --exclude-path="Documents\xwechat_files"
```

## Recurring Monthly Incremental (`azcopy sync`) — PREFERRED for repeat runs

Use `scripts\Backup-OneDriveToAzure.ps1` (below). `azcopy sync` compares source and destination and uploads only new/changed files. `--delete-destination=false` so files removed locally are NEVER deleted from the backup (append-only safety).

```powershell
& $az sync "$src" "https://stodbackupqc1981.blob.core.windows.net/onedrive-backup/full-backup/OneDrive - Microsoft?$sas" --recursive=true --delete-destination=false --exclude-path="Documents\xwechat_files"
```

## Verification

```powershell
& $az list "https://stodbackupqc1981.blob.core.windows.net/onedrive-backup/full-backup?$sas" --output-type=text | Measure-Object -Line
```
Expect ~49,800+ blobs / ~158 GB after a full run.

## Pitfalls & Critical Findings (learned the hard way)

1. **WeChat `Documents\xwechat_files` is a live-churning cache** (31k files / 13 GB). It's constantly rewritten by the running WeChat process, causing 'file in use' / 'source modified during transfer' failures and job thrash. ALWAYS `--exclude-path="Documents\xwechat_files"`. To preserve WeChat history, use WeChat's own chat backup/migration feature instead of file-level copy.
2. **Detached background AzCopy jobs are NOT reliably persistent** — run #1 silently died at ~24%. Always verify liveness via BOTH `Get-Process -Name azcopy*` AND log-file freshness. Append `DONE_MARKER_EXIT_CODE=$LASTEXITCODE` to the log as a completion sentinel.
3. **`azcopy jobs resume` does NOT re-scan the source** — it only retries items from the original enumeration. On a volatile source (WeChat cache rotation), deleted paths fail with 'path not found' and thrash. Prefer a FRESH job (or `sync`) over resume.
4. **Do NOT use .NET `Process.Start` with `RedirectStandardOutput=true` without a stream consumer** — it deadlocks when the pipe buffer fills. Use native shell redirection (`*>> $log`) via a detached process instead.
5. **`--overwrite=false` verified** — safely skips already-present files across retried runs.

## Expected Results (reference run)

- Total enumerated: 49,826 · Completed: 46,076 · Failed: 109 (all WeChat cache DB files) · Skipped: 3,641 · 158.16 GB · ~143 min.
