#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# remote-exec-template.sh
# GoTo Resolve — Remote Execution Template
#
# Use this as a base template for running scripts remotely
# on macOS endpoints via GoTo Resolve (formerly GoTo RMM).
#
# HOW TO USE:
#   1. Copy this template
#   2. Fill in the TASK CONFIGURATION section
#   3. Paste into GoTo Resolve > Remote Execution
#   4. Target your device(s) and run
#
# TEMPLATE VERSION: 1.0
# ═══════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# COLORS (for local testing — GoTo logs are plain text)
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─────────────────────────────────────────────
# TASK CONFIGURATION — EDIT THESE FOR EACH JOB
# ─────────────────────────────────────────────
TASK_NAME="LsAgent Force Rescan"          # Friendly name for logs
TASK_VERSION="1.0"                         # Version tracking
LOG_DIR="/var/log/goto-resolve-scripts"    # Where to save logs
LOG_FILE="$LOG_DIR/$(date +%Y%m%d_%H%M%S)_${TASK_NAME// /_}.log"

# ─────────────────────────────────────────────
# LOGGING SETUP
# ─────────────────────────────────────────────
sudo mkdir -p "$LOG_DIR"

log() {
    local LEVEL="$1"
    local MSG="$2"
    local TIMESTAMP
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    local ENTRY="[$TIMESTAMP] [$LEVEL] $MSG"

    echo "$ENTRY" | sudo tee -a "$LOG_FILE"

    # Color output for local testing
    case "$LEVEL" in
        INFO)    echo -e "${GREEN}$ENTRY${NC}" ;;
        WARN)    echo -e "${YELLOW}$ENTRY${NC}" ;;
        ERROR)   echo -e "${RED}$ENTRY${NC}" ;;
        *)       echo -e "$ENTRY" ;;
    esac
}

# ─────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────
preflight() {
    log "INFO" "═══════════════════════════════════════"
    log "INFO" "Task:     $TASK_NAME v$TASK_VERSION"
    log "INFO" "Host:     $(hostname)"
    log "INFO" "User:     $(whoami)"
    log "INFO" "OS:       $(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
    log "INFO" "Date:     $(date)"
    log "INFO" "═══════════════════════════════════════"

    # Check for root/sudo
    if [ "$EUID" -ne 0 ]; then
        log "WARN" "Script not running as root. Some operations may fail."
    fi

    # Check connectivity (optional — uncomment if task needs network)
    # if ! ping -c 1 -W 3 your-server.domain.com > /dev/null 2>&1; then
    #     log "ERROR" "Cannot reach server. Aborting."
    #     exit 1
    # fi
}

# ─────────────────────────────────────────────
# STOP SERVICE
# Generic function — pass service plist name
# ─────────────────────────────────────────────
stop_service() {
    local PLIST_NAME="$1"
    local PLIST_PATH="/Library/LaunchDaemons/$PLIST_NAME"
    local PROCESS_NAME="$2"

    log "INFO" "Stopping service: $PLIST_NAME"

    if [ -f "$PLIST_PATH" ]; then
        sudo launchctl unload "$PLIST_PATH" 2>/dev/null
        log "INFO" "  Unloaded plist: $PLIST_PATH"
    else
        log "WARN" "  Plist not found: $PLIST_PATH"
    fi

    if [ -n "$PROCESS_NAME" ]; then
        sudo pkill -f "$PROCESS_NAME" 2>/dev/null
        sleep 2
        if pgrep -f "$PROCESS_NAME" > /dev/null; then
            log "WARN" "  Process $PROCESS_NAME may still be running"
        else
            log "INFO" "  Process $PROCESS_NAME stopped"
        fi
    fi
}

# ─────────────────────────────────────────────
# START SERVICE
# ─────────────────────────────────────────────
start_service() {
    local PLIST_NAME="$1"
    local PLIST_PATH="/Library/LaunchDaemons/$PLIST_NAME"
    local PROCESS_NAME="$2"

    log "INFO" "Starting service: $PLIST_NAME"

    if [ -f "$PLIST_PATH" ]; then
        sudo launchctl load "$PLIST_PATH"
        sleep 3

        if [ -n "$PROCESS_NAME" ]; then
            if pgrep -f "$PROCESS_NAME" > /dev/null; then
                log "INFO" "  Service $PROCESS_NAME is running"
            else
                log "ERROR" "  Service $PROCESS_NAME failed to start"
                return 1
            fi
        fi
    else
        log "ERROR" "  Plist not found: $PLIST_PATH"
        return 1
    fi
}

# ─────────────────────────────────────────────
# BACKUP FILE
# Creates a timestamped backup before editing
# ─────────────────────────────────────────────
backup_file() {
    local FILE_PATH="$1"

    if [ -f "$FILE_PATH" ]; then
        local BACKUP_PATH="${FILE_PATH}.bak.$(date +%Y%m%d%H%M%S)"
        sudo cp "$FILE_PATH" "$BACKUP_PATH"
        log "INFO" "Backup created: $BACKUP_PATH"
        echo "$BACKUP_PATH"
    else
        log "ERROR" "File not found for backup: $FILE_PATH"
        return 1
    fi
}

# ─────────────────────────────────────────────
# EDIT INI FIELD
# Clear or set a value in a key=value config
# ─────────────────────────────────────────────
edit_ini_field() {
    local FILE_PATH="$1"
    local KEY="$2"
    local NEW_VALUE="$3"  # Leave empty to clear

    if grep -q "^${KEY}=" "$FILE_PATH" 2>/dev/null; then
        sudo sed -i '' "s|^${KEY}=.*|${KEY}=${NEW_VALUE}|" "$FILE_PATH"
        if [ -z "$NEW_VALUE" ]; then
            log "INFO" "  Cleared: $KEY"
        else
            log "INFO" "  Set: $KEY = $NEW_VALUE"
        fi
    else
        log "WARN" "  Key not found in config: $KEY"
    fi
}

# ─────────────────────────────────────────────
# DISPLAY CONFIG
# Show all settings from a key=value file
# ─────────────────────────────────────────────
display_config() {
    local FILE_PATH="$1"

    log "INFO" "Current config: $FILE_PATH"
    log "INFO" "────────────────────────────────────"

    local NUM=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*\[ ]] && continue

        if [[ "$line" == *"="* ]]; then
            NUM=$((NUM + 1))
            log "INFO" "  [$NUM] $line"
        fi
    done < "$FILE_PATH"

    log "INFO" "────────────────────────────────────"
}

# ─────────────────────────────────────────────
# RESULT REPORTING
# Exit with status for GoTo Resolve dashboard
# ─────────────────────────────────────────────
report_result() {
    local STATUS="$1"   # SUCCESS or FAILURE
    local MESSAGE="$2"

    echo ""
    log "INFO" "═══════════════════════════════════════"
    if [ "$STATUS" == "SUCCESS" ]; then
        log "INFO" "RESULT: SUCCESS — $MESSAGE"
    else
        log "ERROR" "RESULT: FAILURE — $MESSAGE"
    fi
    log "INFO" "Log file: $LOG_FILE"
    log "INFO" "═══════════════════════════════════════"

    if [ "$STATUS" == "SUCCESS" ]; then
        exit 0
    else
        exit 1
    fi
}


# ═══════════════════════════════════════════════════════════════
#
#   MAIN TASK — REPLACE THIS SECTION FOR EACH JOB
#
#   Below is the LsAgent Force Rescan as an example.
#   Swap out the main() function for any remote task.
#
# ═══════════════════════════════════════════════════════════════

main() {
    local INI_PATH="/Library/Application Support/LanSweeper/LsAgent/lsagent.ini"
    local PLIST="com.lansweeper.lsagent.plist"
    local PROCESS="lsagent"

    # --- Pre-flight ---
    preflight

    # --- Stop the service ---
    stop_service "$PLIST" "$PROCESS"

    # --- Backup config ---
    backup_file "$INI_PATH"
    if [ $? -ne 0 ]; then
        report_result "FAILURE" "Could not backup config file"
    fi

    # --- Show current settings ---
    display_config "$INI_PATH"

    # --- Clear fields 7 and 8 ---
    log "INFO" "Clearing scan cache fields..."
    edit_ini_field "$INI_PATH" "Field7" ""
    edit_ini_field "$INI_PATH" "Field8" ""

    # --- Fix server hostname if needed (uncomment & set) ---
    # edit_ini_field "$INI_PATH" "Server" "your-correct-server.domain.com"

    # --- Show updated settings ---
    display_config "$INI_PATH"

    # --- Restart the service ---
    start_service "$PLIST" "$PROCESS"
    if [ $? -ne 0 ]; then
        report_result "FAILURE" "LsAgent failed to restart"
    fi

    # --- Done ---
    report_result "SUCCESS" "LsAgent rescan triggered"
}

# ─────────────────────────────────────────────
# RUN
# ─────────────────────────────────────────────
main "$@"
