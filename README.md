# Local Git Auto Commit & Push Daemon

A lightweight PowerShell daemon that automatically monitors a Git repository for file changes, commits them at configurable intervals, and pushes to the remote — keeping your GitHub contribution graph alive without manual intervention.

## Features

- **Automatic file monitoring** — detects additions, modifications, and deletions
- **Scheduled commits** — batches changes every N minutes (default: 5)
- **Auto-push to remote** — pushes immediately after each commit
- **Network-aware** — skips push when offline, retries next cycle
- **Safeguards** — skips during merge/rebase, respects Git lock files
- **Lock file** — prevents multiple daemon instances
- **Log rotation** — automatic log file management at configurable size
- **Large file filtering** — skips files exceeding a configurable size limit
- **Graceful shutdown** — handles Ctrl+C cleanly

## Prerequisites

- Windows 10/11
- PowerShell 5.1 or later
- [Git for Windows](https://git-scm.com/download/win)
- A Git repository with a configured remote

## Quick Start

1. **Clone this repository:**
   ```bash
   git clone https://github.com/Rogit-28/Auto-Commit-Local.git
   cd Auto-Commit-Local
   ```

2. **Create your `.env` file:**
   ```powershell
   Copy-Item .env.example .env
   ```

3. **Edit `.env`** with your repository path:
   ```
   REPO_PATH="C:\Users\YourName\Documents\my-project"
   BRANCH="main"
   INTERVAL_MINUTES="5"
   ```

4. **Run the daemon:**
   ```powershell
   .\auto-commit.ps1
   ```

## Configuration

All settings live in the `.env` file:

| Parameter           | Default                | Description                                  |
| ------------------- | ---------------------- | -------------------------------------------- |
| `REPO_PATH`         | Current directory      | Path to the Git repo to monitor              |
| `BRANCH`            | `main`                 | Branch to commit and push to                 |
| `INTERVAL_MINUTES`  | `5`                    | Minutes between each commit cycle            |
| `LOG_PATH`          | `.logs\auto-commit.log`| Where logs are written                       |
| `PUSH_ENABLED`      | `true`                 | Set to `false` for commit-only mode          |
| `MAX_LOG_SIZE_KB`   | `1024`                 | Log rotation threshold (KB)                  |
| `MAX_FILE_SIZE_MB`  | `50`                   | Skip files larger than this (MB)             |
| `NETWORK_CHECK_URL` | `https://github.com`   | URL pinged before push attempts              |

## Auto-Start with Windows

Register the daemon as a scheduled task that launches on login:

```powershell
# Install (requires admin)
.\setup-scheduler.ps1 -Action install

# Check status
.\setup-scheduler.ps1 -Action status

# Remove
.\setup-scheduler.ps1 -Action uninstall
```

## How It Works

Each cycle, the daemon:

1. Checks repository health (no merge/rebase in progress, no lock files)
2. Detects changes via `git status --porcelain`
3. Stages all eligible files (`git add -A`), skipping oversized files
4. Commits with an auto-generated message: `auto: updated files on YYYY-MM-DD HH:MM:SS`
5. Pushes to the configured remote branch (if network is available)
6. Logs the result and sleeps until the next cycle

If a push fails (e.g., due to remote conflicts), the daemon halts and logs the error for manual resolution.

## Logs

Logs are written to `.logs/auto-commit.log` with timestamped entries:

```
[2025-09-18 11:15:44] [INFO] Detected 3 change(s). Processing...
[2025-09-18 11:15:45] [SUCCESS] Commit a1b2c3d created: auto: updated files on 2025-09-18 11:15:44
[2025-09-18 11:15:46] [SUCCESS] Push successful to origin/main.
[2025-09-18 11:15:46] [INFO] Next cycle in 5 minute(s).
```

Logs are automatically rotated when they exceed `MAX_LOG_SIZE_KB`.

## Safeguards

| Condition              | Behavior                            |
| ---------------------- | ----------------------------------- |
| Merge in progress      | Skip cycle                          |
| Rebase in progress     | Skip cycle                          |
| Cherry-pick in progress| Skip cycle                          |
| Git index locked       | Skip cycle                          |
| No network             | Commit locally, skip push           |
| Push failure           | Halt daemon, log for manual fix     |
| Duplicate instance     | Refuse to start (lock file)         |
| Oversized file         | Skip that file, commit the rest     |

## Project Structure

```
Auto-Commit-Local/
  auto-commit.ps1       # Main daemon script
  setup-scheduler.ps1   # Windows Task Scheduler helper
  .env.example          # Configuration template
  .gitignore            # Excludes .env, logs, temp files
  auto-git-PRD.txt      # Product requirements document
  README.md             # This file
```

## License

MIT
