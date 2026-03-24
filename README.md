# 🖥️ LsAgent Mac Tools

Scripts for managing and troubleshooting the Lansweeper Agent (LsAgent) on macOS endpoints.

---

## 📂 Scripts

### `force-rescan-lsagent.sh`
**Interactive** script for hands-on use at the Mac.

- ✅ Stops the LsAgent service
- ✅ Backs up `lsagent.ini` with timestamp
- ✅ Displays ALL current settings with color coding
- ✅ Lets you edit any setting by number before proceeding
- ✅ Auto-clears Field7 and Field8 (scan cache)
- ✅ Restarts LsAgent and verifies it's running

**Usage:**
```bash
chmod +x force-rescan-lsagent.sh
sudo ./force-rescan-lsagent.sh
```

---

### `remote-exec-template.sh`
**GoTo Resolve remote execution template** — designed to be pasted into GoTo Resolve's Remote Execution and run silently on target devices.

Includes reusable helper functions:

| Function | Purpose |
|---|---|
| `preflight()` | Logs host info, OS, user, connectivity |
| `stop_service()` | Unloads plist + kills process |
| `start_service()` | Loads plist + verifies running |
| `backup_file()` | Timestamped backup before edits |
| `edit_ini_field()` | Set or clear any key=value field |
| `display_config()` | Dumps all settings to log |
| `report_result()` | Exits SUCCESS/FAILURE for GoTo dashboard |

**Usage (GoTo Resolve):**
1. Copy the script contents
2. Go to **GoTo Resolve > Remote Execution**
3. Paste the script
4. Target your device(s) and run

**Usage (Local Testing):**
```bash
chmod +x remote-exec-template.sh
sudo ./remote-exec-template.sh
```

Logs are saved to: `/var/log/goto-resolve-scripts/`

---

## 🔧 Customizing the Template

To use the template for a different task:

1. Copy `remote-exec-template.sh`
2. Update the `TASK_NAME` and `TASK_VERSION` variables
3. Replace the `main()` function with your task logic
4. Reuse all the helper functions (stop/start service, backup, edit ini, etc.)

---

## 📝 Notes

- **macOS only** — uses `launchctl` and macOS-specific paths
- Always creates a timestamped backup before modifying config files
- Field7 = last scan timestamp, Field8 = scan result cache
- Clearing both forces a fresh rescan on next agent start
- Verify your actual `lsagent.ini` field names match before running
