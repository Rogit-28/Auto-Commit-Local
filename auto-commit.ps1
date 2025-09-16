<#
.SYNOPSIS
    Local Git Auto Commit & Push Daemon for Windows.

.DESCRIPTION
    Monitors a specified Git repository for file changes, automatically
    commits them at periodic intervals, and pushes to the remote branch.

.NOTES
    Author:  Rogit
    Version: 0.5.0
    Requires: PowerShell 5.1+, Git for Windows
#>

# ============================================================================
# CONFIGURATION LOADER
# ============================================================================

function Get-Config {
    <#
    .SYNOPSIS
        Reads configuration from .env file with fallback defaults.
    #>
    $defaults = @{
        REPO_PATH         = (Get-Location).Path
        BRANCH            = "main"
        INTERVAL_MINUTES  = "5"
        LOG_PATH          = ".logs\auto-commit.log"
        PUSH_ENABLED      = "true"
        MAX_LOG_SIZE_KB   = "1024"
        MAX_FILE_SIZE_MB  = "50"
        NETWORK_CHECK_URL = "https://github.com"
    }

    $config = @{}
    foreach ($key in $defaults.Keys) {
        $config[$key] = $defaults[$key]
    }

    $envFile = Join-Path (Get-Location).Path ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            $line = $_.Trim()
            # Skip empty lines and comments
            if ($line -and -not $line.StartsWith("#")) {
                if ($line -match "^\s*([^=\s]+)\s*=\s*(.*)$") {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    # Strip surrounding quotes
                    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                        $value = $value.Substring(1, $value.Length - 2)
                    }
                    $config[$key] = $value
                }
            }
        }
    }
    else {
        Write-Host "[WARN] No .env file found at $envFile — using defaults." -ForegroundColor Yellow
    }

    return $config
}

# ============================================================================
# LOGGING MODULE
# ============================================================================

function Initialize-LogDirectory {
    param([string]$LogPath)

    $logDir = Split-Path $LogPath -Parent
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
}

function Invoke-LogRotation {
    <#
    .SYNOPSIS
        Rotates log file if it exceeds the configured size threshold.
    #>
    param(
        [string]$LogPath,
        [int]$MaxSizeKB
    )

    if (Test-Path $LogPath) {
        $fileSizeKB = (Get-Item $LogPath).Length / 1024
        if ($fileSizeKB -ge $MaxSizeKB) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $rotatedName = $LogPath -replace '\.log$', "-$timestamp.log"
            Move-Item -Path $LogPath -Destination $rotatedName -Force
            Write-Host "[INFO] Log rotated to: $rotatedName" -ForegroundColor Cyan
        }
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped log entry to both console and log file.
    #>
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        [string]$LogPath
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Console output with color coding
    switch ($Level) {
        "INFO"    { Write-Host $logEntry -ForegroundColor White }
        "WARN"    { Write-Host $logEntry -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
    }

    # File output
    if ($LogPath) {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# LOCK FILE MANAGEMENT
# ============================================================================

function Get-LockFilePath {
    param([string]$LogPath)
    $logDir = Split-Path $LogPath -Parent
    return Join-Path $logDir ".lockfile"
}

function Test-LockFile {
    <#
    .SYNOPSIS
        Checks if another instance is already running via lock file.
    #>
    param([string]$LockPath)

    if (Test-Path $LockPath) {
        $storedPid = Get-Content $LockPath -ErrorAction SilentlyContinue
        if ($storedPid) {
            $process = Get-Process -Id $storedPid -ErrorAction SilentlyContinue
            if ($process) {
                return $true  # Another instance is running
            }
            # Stale lock file — previous instance crashed
            Remove-Item $LockPath -Force -ErrorAction SilentlyContinue
        }
    }
    return $false
}

function New-LockFile {
    param([string]$LockPath)
    $PID | Out-File -FilePath $LockPath -Force
}

function Remove-LockFile {
    param([string]$LockPath)
    if (Test-Path $LockPath) {
        Remove-Item $LockPath -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# REPOSITORY HEALTH CHECKS
# ============================================================================

function Test-RepoHealth {
    <#
    .SYNOPSIS
        Validates repository state before performing Git operations.
    .OUTPUTS
        Returns $true if repo is healthy and ready for operations.
    #>
    param(
        [string]$RepoPath,
        [string]$LogPath
    )

    # Check .git directory exists
    $gitDir = Join-Path $RepoPath ".git"
    if (-not (Test-Path $gitDir)) {
        Write-Log -Message "Repository not found at $RepoPath — missing .git directory." -Level "ERROR" -LogPath $LogPath
        return $false
    }

    # Check for merge in progress
    if (Test-Path (Join-Path $gitDir "MERGE_HEAD")) {
        Write-Log -Message "Merge in progress — skipping this cycle." -Level "WARN" -LogPath $LogPath
        return $false
    }

    # Check for rebase in progress
    if ((Test-Path (Join-Path $gitDir "rebase-apply")) -or
        (Test-Path (Join-Path $gitDir "rebase-merge"))) {
        Write-Log -Message "Rebase in progress — skipping this cycle." -Level "WARN" -LogPath $LogPath
        return $false
    }

    # Check for cherry-pick in progress
    if (Test-Path (Join-Path $gitDir "CHERRY_PICK_HEAD")) {
        Write-Log -Message "Cherry-pick in progress — skipping this cycle." -Level "WARN" -LogPath $LogPath
        return $false
    }

    # Check for index lock (another git process running)
    if (Test-Path (Join-Path $gitDir "index.lock")) {
        Write-Log -Message "Git index is locked — another Git process may be running. Skipping." -Level "WARN" -LogPath $LogPath
        return $false
    }

    return $true
}

# ============================================================================
# NETWORK CONNECTIVITY CHECK
# ============================================================================

function Test-NetworkConnection {
    <#
    .SYNOPSIS
        Tests network connectivity by attempting to reach the configured URL.
    #>
    param([string]$CheckUrl)

    try {
        $request = [System.Net.WebRequest]::Create($CheckUrl)
        $request.Timeout = 5000  # 5 second timeout
        $request.Method = "HEAD"
        $response = $request.GetResponse()
        $response.Close()
        return $true
    }
    catch {
        return $false
    }
}

# ============================================================================
# GIT OPERATIONS
# ============================================================================

function Get-PendingChanges {
    <#
    .SYNOPSIS
        Returns list of pending changes in the repository.
    #>
    $status = git status --porcelain 2>&1
    return $status
}

function Invoke-StageAndCommit {
    <#
    .SYNOPSIS
        Stages all changes and creates an auto-generated commit.
    .OUTPUTS
        Returns $true if commit was successful.
    #>
    param(
        [string]$LogPath,
        [int]$MaxFileSizeMB
    )

    # Check for oversized files and warn
    $oversizedFiles = @()
    $status = git status --porcelain 2>&1
    foreach ($line in $status) {
        if ($line -match "^..\s+(.+)$") {
            $filePath = $matches[1].Trim()
            if (Test-Path $filePath) {
                $fileSizeMB = (Get-Item $filePath).Length / 1MB
                if ($fileSizeMB -gt $MaxFileSizeMB) {
                    $oversizedFiles += $filePath
                    Write-Log -Message "Skipping oversized file ($([math]::Round($fileSizeMB, 1))MB): $filePath" -Level "WARN" -LogPath $LogPath
                }
            }
        }
    }

    # Stage all changes
    git add -A 2>&1 | Out-Null

    # Unstage oversized files if any
    foreach ($file in $oversizedFiles) {
        git reset HEAD -- $file 2>&1 | Out-Null
    }

    # Verify there are still staged changes after filtering
    $staged = git diff --cached --name-only 2>&1
    if (-not $staged) {
        Write-Log -Message "No eligible files to commit after size filtering." -Level "INFO" -LogPath $LogPath
        return $false
    }

    # Generate commit message
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $commitMessage = "auto: updated files on $timestamp"

    # Commit
    $commitOutput = git commit -m $commitMessage 2>&1
    $commitSuccess = $LASTEXITCODE -eq 0

    if ($commitSuccess) {
        $shortHash = (git rev-parse --short HEAD 2>&1)
        Write-Log -Message "Commit $shortHash created: $commitMessage" -Level "SUCCESS" -LogPath $LogPath
    }
    else {
        Write-Log -Message "Commit failed: $commitOutput" -Level "ERROR" -LogPath $LogPath
    }

    return $commitSuccess
}

function Invoke-Push {
    <#
    .SYNOPSIS
        Pushes committed changes to the remote repository.
    .OUTPUTS
        Returns $true if push was successful.
    #>
    param(
        [string]$Branch,
        [string]$LogPath,
        [string]$NetworkCheckUrl
    )

    # Network connectivity check
    if (-not (Test-NetworkConnection -CheckUrl $NetworkCheckUrl)) {
        Write-Log -Message "Network unavailable — push deferred to next cycle." -Level "WARN" -LogPath $LogPath
        return $true  # Return true to not halt the daemon — just skip push
    }

    Write-Log -Message "Pushing to origin/$Branch..." -Level "INFO" -LogPath $LogPath

    $pushOutput = git push origin $Branch 2>&1
    $pushSuccess = $LASTEXITCODE -eq 0

    if ($pushSuccess) {
        Write-Log -Message "Push successful to origin/$Branch." -Level "SUCCESS" -LogPath $LogPath
    }
    else {
        Write-Log -Message "Push failed: $pushOutput" -Level "ERROR" -LogPath $LogPath
        Write-Log -Message "Daemon will halt — manual intervention required." -Level "ERROR" -LogPath $LogPath
    }

    return $pushSuccess
}

# ============================================================================
# ENTRY POINT (placeholder — main loop coming next)
# ============================================================================

$config = Get-Config
$logPath = $config["LOG_PATH"]
$repoPath = $config["REPO_PATH"]
$branch = $config["BRANCH"]
$pushEnabled = $config["PUSH_ENABLED"] -eq "true"
$networkCheckUrl = $config["NETWORK_CHECK_URL"]

Initialize-LogDirectory -LogPath $logPath

Write-Log -Message "Auto-Commit Daemon starting..." -Level "INFO" -LogPath $logPath

# Lock file check
$lockPath = Get-LockFilePath -LogPath $logPath
if (Test-LockFile -LockPath $lockPath) {
    Write-Log -Message "Another instance is already running. Exiting." -Level "ERROR" -LogPath $logPath
    exit 1
}
New-LockFile -LockPath $lockPath

Set-Location $repoPath

if (Test-RepoHealth -RepoPath $repoPath -LogPath $logPath) {
    $changes = Get-PendingChanges
    if ($changes) {
        Write-Log -Message "Changes detected. Staging and committing..." -Level "INFO" -LogPath $logPath
        $commitOk = Invoke-StageAndCommit -LogPath $logPath -MaxFileSizeMB ([int]$config["MAX_FILE_SIZE_MB"])

        if ($commitOk -and $pushEnabled) {
            $pushOk = Invoke-Push -Branch $branch -LogPath $logPath -NetworkCheckUrl $networkCheckUrl
            if (-not $pushOk) {
                Write-Log -Message "Push failure detected." -Level "ERROR" -LogPath $logPath
            }
        }
    }
    else {
        Write-Log -Message "No changes detected." -Level "INFO" -LogPath $logPath
    }
}

Remove-LockFile -LockPath $lockPath
