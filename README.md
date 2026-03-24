# 🖥️ LsAgent Mac Tools

> **macOS scripts for forcing a Lansweeper Agent (LsAgent) rescan and remote execution via GoTo Resolve.**

---

## 📋 Table of Contents

- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Script 1: force-rescan-lsagent.sh](#-script-1-force-rescan-lsagentsh)
- [Script 2: remote-exec-template.sh](#-script-2-remote-exec-templatesh)
- [lsagent.ini Field Reference](#-lsagentini-field-reference)
- [Troubleshooting](#-troubleshooting)
- [Customizing the Template](#-customizing-the-template)
- [Notes](#-notes)

---

## ✅ Prerequisites

Before running any script, confirm:

- 🍎 **macOS** endpoint with LsAgent installed
- 🔑 **Admin/sudo access** on the target machine
- 📄 LsAgent config file exists at:
  ```
  /Library/Application Support/LanSweeper/LsAgent/lsagent.ini
  ```
- 🔌 LsAgent plist is registered at:
  ```
  /Library/LaunchDaemons/com.lansweeper.lsagent.plist
  ```
- 🌐 (For remote use) GoTo Resolve agent installed and endpoint is online

---

## ⚡ Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/GreenHornet-Dev/lsagent-mac.git
cd lsagent-mac

# 2. Make scripts executable
chmod +x force-rescan-lsagent.sh
chmod +x remote-exec-template.sh

# 3. Run the interactive rescan tool
sudo ./force-rescan-lsagent.sh
```

---

## 🛠️ Script 1: `force-rescan-lsagent.sh`

**Use this when you are hands-on at the Mac or SSH'd in.**

### What It Does

| Step | Action |
|------|--------|
| 1️⃣ | Stops the LsAgent service (`launchctl unload` + `pkill`) |
| 2️⃣ | Creates a timestamped backup of `lsagent.ini` |
| 3️⃣ | Displays ALL current settings — color-coded 🟢🔴 |
| 4️⃣ | Lets you **edit any setting by number** before continuing |
| 5️⃣ | Auto-clears **Field7** and **Field8** (scan cache fields) |
| 6️⃣ | Restarts LsAgent and confirms it's running |
| 7️⃣ | Prints a summary of all changes made |

### How to Use

```bash
# Make executable (first time only)
chmod +x force-rescan-lsagent.sh

# Run with sudo
sudo ./force-rescan-lsagent.sh
```

### Interactive Menu Options

When the script shows your current settings, you'll see:

```
[1] Server = lansweeper.yourdomain.com
[2] Port = 9524
[3] ScanInterval = 86400
[4] Field7 = a3f8c2... ← WILL BE CLEARED  🔴
[5] Field8 = 1711234... ← WILL BE CLEARED  🔴
────────────────────────────────────────
Options:
[number] - Edit a setting by its number
[a]      - Show all settings again
[c]      - Continue with rescan
[q]      - Quit without restarting
```

| Input | Action |
|-------|--------|
| `1` (any number) | Edit that setting — prompts for new value |
| `a` | Re-display all settings after edits |
| `c` | Confirm and proceed — clears fields, restarts agent |
| `q` | Quit safely — LsAgent stays stopped, no changes made |

### Example: Fixing a Wrong Server

```
Enter choice: 1
Current: Server = lansweeper-old.domain.com
New value for Server: lansweeper.domain.com
Updated: Server = lansweeper.domain.com ✅

Enter choice: c
Proceeding with rescan...
```

---

## 🚀 Script 2: `remote-exec-template.sh`

**Use this for silent, unattended execution via GoTo Resolve Remote Execution.**

### How to Use in GoTo Resolve

1. Open **GoTo Resolve**
2. Navigate to **Remote Execution** (or **Helpdesk > Scripts**)
3. Click **New Script** or **Paste Script**
4. Copy and paste the entire contents of `remote-exec-template.sh`
5. Set **OS Type** to `macOS`
6. Select your target device(s)
7. Click **Run**
8. Check results in the GoTo Resolve dashboard — exit code `0` = ✅ SUCCESS

### How to Use Locally (Testing)

```bash
chmod +x remote-exec-template.sh
sudo ./remote-exec-template.sh
```

### Log Location

All runs log to the endpoint automatically:
```
/var/log/goto-resolve-scripts/<TASK_NAME>-<TIMESTAMP>.log
```

### Built-in Helper Functions

| Function | What It Does |
|----------|--------------|
| `preflight()` | Logs hostname, macOS version, current user, network check |
| `stop_service()` | Gracefully unloads a plist + force-kills the process |
| `start_service()` | Loads a plist and verifies the process is running |
| `backup_file()` | Creates a timestamped `.bak` copy before any edits |
| `edit_ini_field()` | Safely set or clear any `key=value` field in a config file |
| `display_config()` | Dumps full config contents to the log |
| `report_result()` | Outputs `SUCCESS` or `FAILURE` with exit code for GoTo dashboard |

---

## 📄 `lsagent.ini` Field Reference

| Field | Purpose | Action |
|-------|---------|--------|
| `Server` | Lansweeper server hostname or IP | ✏️ Verify/correct if agent isn't reporting |
| `Port` | Communication port (default `9524`) | ✏️ Verify matches your server config |
| `Field7` | Last scan timestamp cache | 🗑️ **Clear to force fresh scan** |
| `Field8` | Scan result/status cache | 🗑️ **Clear to force fresh scan** |
| Other fields | Various agent state values | ✏️ Edit only if directed by Lansweeper support |

> 💡 **Tip:** Open the ini manually first to confirm your exact field names:
> ```bash
> sudo cat "/Library/Application Support/LanSweeper/LsAgent/lsagent.ini"
> ```

---

## 🔧 Troubleshooting

### LsAgent won't stop
```bash
# Force kill by process name
sudo pkill -9 -f lsagent
# Confirm it's stopped
pgrep -f lsagent && echo "Still running" || echo "Stopped"
```

### `lsagent.ini` not found
```bash
# Search for it
sudo find / -name "lsagent.ini" 2>/dev/null
```
Update the `INI_PATH` variable at the top of the script to match.

### LsAgent won't restart
```bash
# Manually load the plist
sudo launchctl load /Library/LaunchDaemons/com.lansweeper.lsagent.plist
# Check system logs
log show --predicate 'process == "lsagent"' --last 10m
```

### Agent reports but scan doesn't update in Lansweeper console
- Confirm `Server=` points to the correct Lansweeper server
- Confirm port `9524` is open between Mac and server
- Allow up to 10–15 minutes for the rescan to appear in the console

### Backup restore
```bash
# List backups
ls "/Library/Application Support/LanSweeper/LsAgent/"*.bak.*

# Restore most recent backup
sudo cp "/Library/Application Support/LanSweeper/LsAgent/lsagent.ini.bak.YYYYMMDDHHMMSS" \
        "/Library/Application Support/LanSweeper/LsAgent/lsagent.ini"
```

---

## 🔁 Customizing the Template

To repurpose `remote-exec-template.sh` for a different task:

1. Copy the file: `cp remote-exec-template.sh my-new-task.sh`
2. Update the header variables:
   ```bash
   TASK_NAME="my-new-task"
   TASK_VERSION="1.0"
   ```
3. Replace only the `main()` function with your task logic
4. Keep all the helper functions — they're reusable for any job

---

## 📝 Notes

- 🍎 **macOS only** — uses `launchctl`, macOS paths, and BSD `sed`
- 💾 Always creates a timestamped backup before modifying any config
- ⏱️ After restart, allow a few minutes for the agent to check in and rescan
- 🔁 Tested on macOS Monterey, Ventura, and Sonoma
- 📬 Issues or improvements? Open a PR or issue on this repo

---

*Maintained by [GreenHornet-Dev](https://github.com/GreenHornet-Dev)*
