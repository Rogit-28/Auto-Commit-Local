<#
.SYNOPSIS
    Local Git Auto Commit & Push Daemon for Windows.

.DESCRIPTION
    Monitors a specified Git repository for file changes, automatically
    commits them at periodic intervals, and pushes to the remote branch.

.NOTES
    Author:  Rogit
    Version: 0.2.0
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
# ENTRY POINT (placeholder — more to come)
# ============================================================================

$config = Get-Config
$logPath = $config["LOG_PATH"]
Initialize-LogDirectory -LogPath $logPath

Write-Log -Message "Config loaded. Repo: $($config['REPO_PATH'])" -Level "INFO" -LogPath $logPath
Write-Log -Message "Logging system initialized." -Level "SUCCESS" -LogPath $logPath
