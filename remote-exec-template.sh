#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# remote-exec-template.sh  v1.1
# GoTo Resolve — Remote Execution Template for macOS
#
# Use as a base template for running scripts remotely
# on macOS endpoints via GoTo Resolve (formerly GoTo RMM).
#
# HOW TO USE:
#   1. Copy this template
#   2. Fill in the TASK CONFIGURATION section
#   3. Replace the main() function with your task logic
#   4. Paste into GoTo Resolve > Remote Execution
#   5. Target your device(s) and run
#
# GreenHornet-Dev / Custom Design Systems
# TEMPLATE VERSION: 1.1
# ═══════════════════════════════════════════════════════════════

set -uo pipefail
# Note: not using -e here — we handle errors via report_result

# ─────────────────────────────────────────────
# COLORS (for local testing — GoTo logs are plain text)
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─────────────────────────────────────────────
# TASK CONFIGURATION — EDIT THESE FOR EACH JOB
# ─────────────────────────────────────────────
TASK_NAME="LsAgent Force Rescan"
TASK_VERSION="1.1"
LOG_DIR="/var/log/goto-resolve-scripts"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/${TIMESTAMP}_${TASK_NAME// /_}.log"

# ─────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────
setup_logging() {
    mkdir -p "$LOG_DIR" 2>/dev/null || {
        LOG_DIR="/tmp"
        LOG_FILE="$LOG_DIR/${TIMESTAMP}_${TASK_NAME// /_}.log"
    }
    # Rotate old logs (keep last 20)
    find "$LOG_DIR" -name "*.log" -type f -mtime +30 -delete 2>/dev/null || true
}

log() {
    local LEVEL="$1"
    local MSG="$2"
    local TS
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    local ENTRY="[$TS] [$LEVEL] $MSG"

    # Always write to log file
    echo "$ENTRY" >> "$LOG_FILE" 2>/dev/null

    # Color output for terminal (local testing)
    if [ -t 1 ]; then
        case "$LEVEL" in
            INFO)    echo -e "${GREEN}$ENTRY${NC}" ;;
            WARN)    echo -e "${YELLOW}$ENTRY${NC}" ;;
            ERROR)   echo -e "${RED}$ENTRY${NC}" ;;
            *)       echo "$ENTRY" ;;
        esac
    else
        # Plain text for GoTo Resolve
        echo "$ENTRY"
    fi
}

# ─────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────
preflight() {
    log "INFO" "═══════════════════════════════════════"
    log "INFO" "Task:     $TASK_NAME v$TASK_VERSION"
    log "INFO" "Host:     $(hostname 2>/dev/null || echo 'unknown')"
    log "INFO" "User:     $(whoami 2>/dev/null || echo 'unknown')"
    log "INFO" "OS:       $(sw_vers -productName 2>/dev/null || echo '?') $(sw_vers -productVersion 2>/dev/null || echo '?') ($(sw_vers -buildVersion 2>/dev/null || echo '?'))"
    log "INFO" "Arch:     $(uname -m 2>/dev/null || echo 'unknown')"
    log "INFO" "Date:     $(date)"
    log "INFO" "Log:      $LOG_FILE"
    log "INFO" "═══════════════════════════════════════"

    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        log "WARN" "Script not running as root. Some operations may fail."
    fi
}

# ─────────────────────────────────────────────
# STOP SERVICE
# ─────────────────────────────────────────────
stop_service() {
    local PLIST_NAME="$1"
    local PLIST_PATH="/Library/LaunchDaemons/$PLIST_NAME"
    local PROCESS_NAME="${2:-}"

    log "INFO" "Stopping service: $PLIST_NAME"

    if [ -f "$PLIST_PATH" ]; then
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        log "INFO" "  Unloaded plist: $PLIST_PATH"
    else
        log "WARN" "  Plist not found: $PLIST_PATH"
    fi

    if [ -n "$PROCESS_NAME" ]; then
        pkill -f "$PROCESS_NAME" 2>/dev/null || true
        sleep 2

        # Force kill if still running
        if pgrep -f "$PROCESS_NAME" > /dev/null 2>&1; then
            log "WARN" "  Process still alive, force killing..."
            pkill -9 -f "$PROCESS_NAME" 2>/dev/null || true
            sleep 1
        fi

        if pgrep -f "$PROCESS_NAME" > /dev/null 2>&1; then
            log "ERROR" "  Process $PROCESS_NAME could not be stopped"
            return 1
        else
            log "INFO" "  ✅ Process $PROCESS_NAME stopped"
        fi
    fi
}

# ─────────────────────────────────────────────
# START SERVICE
# ─────────────────────────────────────────────
start_service() {
    local PLIST_NAME="$1"
    local PLIST_PATH="/Library/LaunchDaemons/$PLIST_NAME"
    local PROCESS_NAME="${2:-}"

    log "INFO" "Starting service: $PLIST_NAME"

    if [ ! -f "$PLIST_PATH" ]; then
        log "ERROR" "  Plist not found: $PLIST_PATH"
        return 1
    fi

    launchctl load "$PLIST_PATH" 2>/dev/null || {
        log "ERROR" "  Failed to load plist"
        return 1
    }
    sleep 3

    if [ -n "$PROCESS_NAME" ]; then
        if pgrep -f "$PROCESS_NAME" > /dev/null 2>&1; then
            log "INFO" "  ✅ Service $PROCESS_NAME is running"
        else
            # Give it a bit more time
            sleep 5
            if pgrep -f "$PROCESS_NAME" > /dev/null 2>&1; then
                log "INFO" "  ✅ Service $PROCESS_NAME started (delayed)"
            else
                log "ERROR" "  ❌ Service $PROCESS_NAME failed to start"
                return 1
            fi
        fi
    fi
}

# ─────────────────────────────────────────────
# BACKUP FILE
# ─────────────────────────────────────────────
backup_file() {
    local FILE_PATH="$1"

    if [ ! -f "$FILE_PATH" ]; then
        log "ERROR" "File not found for backup: $FILE_PATH"
        return 1
    fi

    local BACKUP_PATH="${FILE_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$FILE_PATH" "$BACKUP_PATH" || {
        log "ERROR" "Failed to create backup: $BACKUP_PATH"
        return 1
    }
    log "INFO" "✅ Backup: $BACKUP_PATH"
    echo "$BACKUP_PATH"
}

# ─────────────────────────────────────────────
# EDIT INI FIELD
# ─────────────────────────────────────────────
edit_ini_field() {
    local FILE_PATH="$1"
    local KEY="$2"
    local NEW_VALUE="${3:-}"

    if ! grep -q "^${KEY}=" "$FILE_PATH" 2>/dev/null; then
        log "WARN" "  Key not found in config: $KEY"
        return 0
    fi

    # Escape special chars for sed
    local ESCAPED_VAL
    ESCAPED_VAL=$(printf '%s\n' "$NEW_VALUE" | sed 's/[&/\]/\\&/g')
    sed -i '' "s|^${KEY}=.*|${KEY}=${ESCAPED_VAL}|" "$FILE_PATH"

    if [ -z "$NEW_VALUE" ]; then
        log "INFO" "  ✅ Cleared: $KEY"
    else
        log "INFO" "  ✅ Set: $KEY = $NEW_VALUE"
    fi
}

# ─────────────────────────────────────────────
# DISPLAY CONFIG
# ─────────────────────────────────────────────
display_config() {
    local FILE_PATH="$1"

    if [ ! -f "$FILE_PATH" ]; then
        log "ERROR" "Config file not found: $FILE_PATH"
        return 1
    fi

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
    log "INFO" "  Total settings: $NUM"
}

# ─────────────────────────────────────────────
# RESULT REPORTING
# ─────────────────────────────────────────────
report_result() {
    local STATUS="$1"
    local MESSAGE="$2"

    echo ""
    log "INFO" "═══════════════════════════════════════"
    if [ "$STATUS" == "SUCCESS" ]; then
        log "INFO" "RESULT: ✅ SUCCESS — $MESSAGE"
    else
        log "ERROR" "RESULT: ❌ FAILURE — $MESSAGE"
    fi
    log "INFO" "Log:    $LOG_FILE"
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
#   Below is the LsAgent Force Rescan as a working example.
#   Copy this file, rename it, and swap out main() for your task.
#   All helper functions above are reusable.
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
    if [ $? -ne 0 ]; then
        report_result "FAILURE" "Could not stop LsAgent"
    fi

    # --- Backup config ---
    backup_file "$INI_PATH"
    if [ $? -ne 0 ]; then
        report_result "FAILURE" "Could not backup config file"
    fi

    # --- Show current settings ---
    display_config "$INI_PATH"

    # --- Clear scan cache fields ---
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
setup_logging
main "$@"
