<#
.SYNOPSIS
    Local Git Auto Commit & Push Daemon for Windows.

.DESCRIPTION
    Monitors a specified Git repository for file changes, automatically
    commits them at periodic intervals, and pushes to the remote branch.

.NOTES
    Author:  Rogit
    Version: 0.1.0
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
# ENTRY POINT (placeholder — more to come)
# ============================================================================

$config = Get-Config
Write-Host "Config loaded. Repo: $($config['REPO_PATH']), Branch: $($config['BRANCH'])"
