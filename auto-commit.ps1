<#
.SYNOPSIS
    Local Git Auto Commit & Push Daemon for Windows.

.DESCRIPTION
    Monitors a specified Git repository for file changes, automatically
    commits them at periodic intervals, and pushes to the remote branch.

.NOTES
    Author:  Rogit
    Version: 0.3.0
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
# ENTRY POINT (placeholder — git operations coming next)
# ============================================================================

$config = Get-Config
$logPath = $config["LOG_PATH"]
$repoPath = $config["REPO_PATH"]

Initialize-LogDirectory -LogPath $logPath

Write-Log -Message "Config loaded. Repo: $repoPath" -Level "INFO" -LogPath $logPath

# Lock file check
$lockPath = Get-LockFilePath -LogPath $logPath
if (Test-LockFile -LockPath $lockPath) {
    Write-Log -Message "Another instance is already running. Exiting." -Level "ERROR" -LogPath $logPath
    exit 1
}
New-LockFile -LockPath $lockPath

# Health check
if (Test-RepoHealth -RepoPath $repoPath -LogPath $logPath) {
    Write-Log -Message "Repository health check passed." -Level "SUCCESS" -LogPath $logPath
}
else {
    Write-Log -Message "Repository health check failed." -Level "ERROR" -LogPath $logPath
}

Remove-LockFile -LockPath $lockPath
