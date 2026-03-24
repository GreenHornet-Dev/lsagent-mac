# 🟢 LsAgent Mac Tools

> **macOS scripts for Lansweeper Agent management, force rescan, remote execution, and 3rd-party app version checking.**

[![macOS](https://img.shields.io/badge/macOS-Monterey%20%7C%20Ventura%20%7C%20Sonoma%20%7C%20Sequoia-blue?logo=apple)](https://www.apple.com/macos/)
[![Lansweeper](https://img.shields.io/badge/Lansweeper-LsAgent-green)](https://www.lansweeper.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📋 What's In This Repo

| Script | Purpose | Run As |
|--------|---------|--------|
| 🛠️ [`force-rescan-lsagent.sh`](#-force-rescan-lsagentsh) | Interactive LsAgent rescan with settings editor | `sudo` on Mac |
| 🚀 [`remote-exec-template.sh`](#-remote-exec-templatesh) | GoTo Resolve remote execution template | GoTo Resolve / `sudo` |
| 🔍 [`check-app-versions.sh`](#-check-app-versionssh) | Scan installed apps, check for updates via Homebrew Cask API | Any user / `sudo` |

### How This Ties Into PA-LsAgent

These scripts complement the [pa-lsagent](https://github.com/GreenHornet-Dev/pa-lsagent) Power Automate flow:

```
┌──────────────────────┐       ┌───────────────────────────┐
│  🖥️ Mac Endpoints     │       │  ☁️ Lansweeper Cloud       │
│                      │──────▶│  (scans assets + software)│
│  LsAgent installed   │ scan  │                           │
│  check-app-versions  │       └─────────┬─────────────────┘
│  force-rescan        │                 │ GraphQL API
└──────────────────────┘                 ▼
                               ┌───────────────────────────┐
                               │  ⚡ PA-LsAgent Flow        │
                               │  (Power Automate)         │
                               │                           │
                               │  tblPCs / tblMonitors     │
                               │  tblPeripherals           │
                               │  tblNetwork               │
                               │  tblMacSoftware  ← NEW    │
                               └─────────┬─────────────────┘
                                         │
                                         ▼
                               ┌───────────────────────────┐
                               │  📊 SharePoint Excel       │
                               │  Asset Tracking Workbook   │
                               └───────────────────────────┘
```

---

## ⚡ Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/GreenHornet-Dev/lsagent-mac.git
cd lsagent-mac

# 2. Make scripts executable
chmod +x *.sh

# 3. Force rescan (interactive)
sudo ./force-rescan-lsagent.sh

# 4. Check app versions (no sudo needed)
./check-app-versions.sh
```

---

## ✅ Prerequisites

- 🍎 **macOS** Monterey 12+ / Ventura 13+ / Sonoma 14+ / Sequoia 15+
- 🔑 **Admin/sudo access** for LsAgent scripts
- 📄 LsAgent installed with config at:
  ```
  /Library/Application Support/LanSweeper/LsAgent/lsagent.ini
  ```
- 🔌 LaunchDaemon plist at:
  ```
  /Library/LaunchDaemons/com.lansweeper.lsagent.plist
  ```
- 🌐 Internet access for version checking (Homebrew Cask API)
- 🌐 (Optional) GoTo Resolve agent for remote execution

---

## 🛠️ `force-rescan-lsagent.sh`

**Interactive tool for hands-on LsAgent rescan.** Run this when you're at the Mac or SSH'd in.

### What It Does (Step by Step)

| Step | Action |
|------|--------|
| 1️⃣ | Checks for root/sudo access |
| 2️⃣ | Stops LsAgent (graceful → force kill if needed) |
| 3️⃣ | Creates timestamped backup of `lsagent.ini` |
| 4️⃣ | Displays ALL settings — color-coded 🟢🔴 |
| 5️⃣ | Interactive editor — change any setting by number |
| 6️⃣ | Auto-clears **Field7** and **Field8** (scan cache) |
| 7️⃣ | Restarts LsAgent and confirms it's running |
| 8️⃣ | Prints summary with agent status check |

### Interactive Menu

```
[1] Server = lansweeper.yourdomain.com
[2] Port = 9524
[3] ScanInterval = 86400
[4] Field7 = a3f8c2... ← WILL BE CLEARED 🔴
[5] Field8 = 1711234... ← WILL BE CLEARED 🔴
────────────────────────────────────────
Options:
  [number]  - Edit a setting by its number
  [a]       - Show all settings again
  [c]       - Continue with rescan
  [q]       - Quit without restarting
```

### v1.1 Improvements

- Added `set -euo pipefail` for safer execution
- Root check at startup (no more silent failures)
- Escalating kill: graceful → `pkill -9` → error with manual command
- `sed` escaping for special characters in values
- Auto-search for `lsagent.ini` if not found at default path
- Delayed restart check (waits extra 5s if agent doesn't appear immediately)
- Agent running status in final summary

---

## 🚀 `remote-exec-template.sh`

**Silent, unattended execution via GoTo Resolve Remote Execution.** Copy and customize for any remote macOS task.

### How to Use in GoTo Resolve

1. Open **GoTo Resolve**
2. Navigate to **Remote Execution** (or **Helpdesk > Scripts**)
3. Click **New Script** or **Paste Script**
4. Copy/paste the entire contents of `remote-exec-template.sh`
5. Set **OS Type** to `macOS`
6. Select target device(s)
7. Click **Run**
8. Check results in dashboard — exit code `0` = ✅ SUCCESS

### How to Test Locally

```bash
chmod +x remote-exec-template.sh
sudo ./remote-exec-template.sh
```

### Built-in Helper Functions

| Function | What It Does |
|----------|--------------|
| `setup_logging()` | Creates log directory, rotates old logs (30+ days) |
| `log()` | Timestamped logging — color in terminal, plain text in GoTo |
| `preflight()` | Logs hostname, macOS version, arch, user, connectivity |
| `stop_service()` | Graceful unload → force kill → error reporting |
| `start_service()` | Load plist → verify process → delayed retry |
| `backup_file()` | Timestamped `.bak` copy before any edits |
| `edit_ini_field()` | Safely set or clear any `key=value` with sed escaping |
| `display_config()` | Dump full config to log with line numbers |
| `report_result()` | `SUCCESS`/`FAILURE` exit code for GoTo dashboard |

### Creating a New Task

```bash
cp remote-exec-template.sh my-new-task.sh
```

Edit the header:
```bash
TASK_NAME="My Custom Task"
TASK_VERSION="1.0"
```

Replace only `main()` — all helpers stay the same.

### v1.1 Improvements

- `set -uo pipefail` for safer execution
- Smart logging: detects terminal vs GoTo Resolve (color vs plain text)
- Log rotation: auto-cleans logs older than 30 days
- Fallback log dir (`/tmp`) if `/var/log` is not writable
- Escalating kill in `stop_service()` (graceful → force → error)
- Delayed retry in `start_service()` (waits extra 5s if process slow)
- macOS arch and build version in preflight
- Proper sed escaping in `edit_ini_field()`

### Log Location

```
/var/log/goto-resolve-scripts/<TIMESTAMP>_<TASK_NAME>.log
```

---

## 🔍 `check-app-versions.sh`

**Scans all installed 3rd-party Mac apps and checks for available updates using the [Homebrew Cask API](https://formulae.brew.sh/docs/api/).**

### What It Does

1. Scans `/Applications` and `~/Applications`
2. Skips Apple built-in apps (com.apple.* bundle IDs)
3. Reads each app's version from `Info.plist`
4. Looks up the latest version via `https://formulae.brew.sh/api/cask/<token>.json`
5. Compares installed vs. latest using semver sort
6. Outputs:
   - 🖥️ **Color-coded terminal report** (outdated = 🔴, current = 🟢, unknown = ⚪)
   - 📄 **JSON file** for the pa-lsagent Power Automate flow

### How to Run

```bash
# No sudo needed for basic scan
chmod +x check-app-versions.sh
./check-app-versions.sh
```

### Example Output

```
  APP NAME                            INSTALLED       LATEST          STATUS
  ─────────────────────────────────────────────────────────────────────────
  Google Chrome                       131.0.6778.86   132.0.6834.57   🔴 UPDATE
  Slack                               4.39.95         4.39.95         🟢 OK
  Visual Studio Code                  1.96.0          1.96.0          🟢 OK
  Zoom                                6.3.5           6.3.6           🔴 UPDATE
  Firefox                             133.0           133.0           🟢 OK
  Docker                              4.37.1          4.37.2          🔴 UPDATE

  ═══════════════════════════════════════════════════
    📊 Summary — MACBOOK-PRO.local
  ═══════════════════════════════════════════════════

  Total scanned:    42
  🟢 Up to date:     35
  🔴 Needs update:   5
  🔵 Newer than repo: 0
  ⚪ Unknown/N/A:    2

  ⚠️  5 app(s) need updating!

  Outdated apps:
    • Google Chrome  131.0.6778.86 → 132.0.6834.57
    • Zoom           6.3.5 → 6.3.6
    • Docker         4.37.1 → 4.37.2
    ...
```

### JSON Output

The script writes a JSON file to `/tmp/lsagent-mac/` that the **pa-lsagent** Power Automate flow can consume:

```json
{
  "hostname": "MACBOOK-PRO.local",
  "macosVersion": "14.5",
  "scanDate": "2026-03-24T05:00:00Z",
  "scriptVersion": "1.0",
  "summary": {
    "total": 42,
    "current": 35,
    "outdated": 5,
    "newer": 0,
    "unknown": 2
  },
  "apps": [
    {
      "appName": "Google Chrome",
      "bundleId": "com.google.Chrome",
      "installedVersion": "131.0.6778.86",
      "latestVersion": "132.0.6834.57",
      "caskToken": "google-chrome",
      "status": "outdated",
      "hostname": "MACBOOK-PRO.local",
      "scanDate": "2026-03-24T05:00:00Z"
    }
  ]
}
```

### Feeding Into PA-LsAgent

The JSON output is designed to match a **tblMacSoftware** Excel table in the pa-lsagent spreadsheet:

| Column | JSON Key | Description |
|--------|----------|-------------|
| Hostname | `hostname` | Mac computer name |
| AppName | `appName` | Application name |
| BundleID | `bundleId` | macOS bundle identifier |
| InstalledVersion | `installedVersion` | Currently installed version |
| LatestVersion | `latestVersion` | Latest available from Homebrew |
| CaskToken | `caskToken` | Homebrew Cask identifier |
| Status | `status` | `outdated` / `current` / `newer` / `unknown` |
| ScanDate | `scanDate` | When the check ran (UTC) |

### How the Cask Lookup Works

1. Script maps app names → Homebrew Cask tokens (60+ built-in mappings)
2. For unmapped apps, auto-generates a token from the name (lowercase, hyphens)
3. Queries `https://formulae.brew.sh/api/cask/<token>.json`
4. Caches responses for 1 hour to avoid hitting the API repeatedly
5. Compares versions using `sort -V` (handles semver correctly)

### Adding Custom App Mappings

Edit the `CASK_MAP` array at the top of the script:

```bash
CASK_MAP=(
    # Your custom mappings
    ["My Internal App"]="my-internal-cask"
    ["Company Tool"]="company-tool"
    ...
)
```

Or use the `version-check-apps.json` from the [pa-lsagent repo](https://github.com/GreenHornet-Dev/pa-lsagent) for centralized config.

---

## 📄 `lsagent.ini` Field Reference

| Field | Purpose | Action |
|-------|---------|--------|
| `Server` | Lansweeper server hostname or IP | ✏️ Verify/correct if agent isn't reporting |
| `Port` | Communication port (default `9524`) | ✏️ Match your server config |
| `Field7` | Last scan timestamp cache | 🗑️ **Clear to force fresh scan** |
| `Field8` | Scan result/status cache | 🗑️ **Clear to force fresh scan** |
| Other fields | Various agent state values | ✏️ Edit only if directed by Lansweeper support |

> 💡 **Tip:** View the ini manually to confirm your exact field names:
> ```bash
> sudo cat "/Library/Application Support/LanSweeper/LsAgent/lsagent.ini"
> ```

---

## 🔧 Troubleshooting

### LsAgent won't stop
```bash
# Force kill by process name
sudo pkill -9 -f lsagent
# Confirm
pgrep -f lsagent && echo "Still running" || echo "Stopped"
```

### `lsagent.ini` not found
```bash
# Search for it
sudo find / -name "lsagent.ini" 2>/dev/null
```
Update `INI_PATH` at the top of the script to match.

### LsAgent won't restart
```bash
# Manually load the plist
sudo launchctl load /Library/LaunchDaemons/com.lansweeper.lsagent.plist
# Check system logs
log show --predicate 'process == "lsagent"' --last 10m
```

### Agent reports but scan doesn't update in Lansweeper
- Confirm `Server=` points to the correct server
- Confirm port `9524` is open between Mac and server
- Allow 10–15 minutes for the rescan to appear

### Backup restore
```bash
# List backups
ls "/Library/Application Support/LanSweeper/LsAgent/"*.bak.*

# Restore most recent
sudo cp "/Library/Application Support/LanSweeper/LsAgent/lsagent.ini.bak.YYYYMMDDHHMMSS" \
        "/Library/Application Support/LanSweeper/LsAgent/lsagent.ini"
```

### check-app-versions.sh shows "not_found" for an app
The app doesn't have a matching Homebrew Cask. Add a custom mapping:
```bash
# In the CASK_MAP array at the top of check-app-versions.sh
["Your App Name"]="homebrew-cask-token"
```
Find the cask token at [formulae.brew.sh/cask](https://formulae.brew.sh/cask/).

---

## 📁 Files

| File | Version | Description |
|------|---------|-------------|
| `force-rescan-lsagent.sh` | v1.1 | Interactive LsAgent rescan + settings editor |
| `remote-exec-template.sh` | v1.1 | GoTo Resolve remote execution template |
| `check-app-versions.sh` | v1.0 | Mac app version checker (terminal + JSON) |
| `README.md` | — | This documentation |

---

## 🔗 Related Repos

| Repo | Description |
|------|-------------|
| [pa-lsagent](https://github.com/GreenHornet-Dev/pa-lsagent) | Power Automate flow — syncs Lansweeper data to SharePoint Excel |
| [green-tools](https://github.com/GreenHornet-Dev/green-tools) | Windows PowerShell toolkit — system updates, app scanning |
| [little-helper](https://github.com/GreenHornet-Dev/little-helper) | Java console tool — WinGet automation, deployment checklists |

---

## 📝 Notes

- 🍎 **macOS only** — uses `launchctl`, `PlistBuddy`, BSD `sed`, and macOS paths
- 💾 All scripts create timestamped backups before modifying any config
- ⏱️ After rescan restart, allow a few minutes for the agent to check in
- 🔄 Version checker caches Homebrew API responses for 1 hour
- 🧪 Tested on macOS Monterey 12, Ventura 13, Sonoma 14, Sequoia 15
- 📬 Issues or improvements? Open a PR or issue on this repo

---

**Built by [GreenHornet-Dev](https://github.com/GreenHornet-Dev) / Custom Design Systems** 🟢
