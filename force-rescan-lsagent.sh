#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# force-rescan-lsagent.sh  v1.1
# Forces Lansweeper Agent to rescan on macOS
# Interactive settings review with validation
#
# GreenHornet-Dev / Custom Design Systems
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────
# CONFIGURATION — edit if your paths differ
# ─────────────────────────────────────────────
INI_PATH="/Library/Application Support/LanSweeper/LsAgent/lsagent.ini"
PLIST="com.lansweeper.lsagent.plist"
PLIST_PATH="/Library/LaunchDaemons/$PLIST"

# ─────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─────────────────────────────────────────────
# ROOT CHECK
# ─────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root (sudo).${NC}"
    echo -e "  Usage: ${CYAN}sudo ./force-rescan-lsagent.sh${NC}"
    exit 1
fi

# ─────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  🟢 LsAgent Force Rescan Tool (macOS)${NC}"
echo -e "${CYAN}  v1.1 — GreenHornet-Dev${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ─────────────────────────────────────────────
# STEP 1: Stop LsAgent
# ─────────────────────────────────────────────
echo -e "${YELLOW}[1/5] Stopping LsAgent...${NC}"

if [ ! -f "$PLIST_PATH" ]; then
    echo -e "${RED}  WARNING: Plist not found at $PLIST_PATH${NC}"
    echo -e "${YELLOW}  Attempting to kill process directly...${NC}"
else
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

pkill -f lsagent 2>/dev/null || true
sleep 2

if pgrep -f lsagent > /dev/null 2>&1; then
    echo -e "${YELLOW}  Process still alive — force killing...${NC}"
    pkill -9 -f lsagent 2>/dev/null || true
    sleep 1
fi

if pgrep -f lsagent > /dev/null 2>&1; then
    echo -e "${RED}  ERROR: Cannot stop LsAgent. Manual intervention needed.${NC}"
    echo -e "  Try: ${CYAN}sudo kill -9 \$(pgrep -f lsagent)${NC}"
    exit 1
else
    echo -e "${GREEN}  ✅ LsAgent stopped.${NC}"
fi

# ─────────────────────────────────────────────
# STEP 2: Backup the ini
# ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[2/5] Backing up lsagent.ini...${NC}"
if [ -f "$INI_PATH" ]; then
    BACKUP="$INI_PATH.bak.$(date +%Y%m%d%H%M%S)"
    cp "$INI_PATH" "$BACKUP"
    echo -e "${GREEN}  ✅ Backup: $BACKUP${NC}"
else
    echo -e "${RED}  ERROR: lsagent.ini not found at:${NC}"
    echo -e "${RED}  $INI_PATH${NC}"
    echo ""
    echo -e "${YELLOW}  Searching for it...${NC}"
    FOUND=$(find / -name "lsagent.ini" 2>/dev/null | head -3)
    if [ -n "$FOUND" ]; then
        echo -e "${CYAN}  Found at:${NC}"
        echo "$FOUND" | while read -r f; do echo -e "    ${GREEN}$f${NC}"; done
        echo ""
        echo -e "  Update ${CYAN}INI_PATH${NC} at the top of this script and re-run."
    else
        echo -e "${RED}  Not found anywhere. Is LsAgent installed?${NC}"
    fi
    exit 1
fi

# ─────────────────────────────────────────────
# STEP 3: Display ALL current settings
# ─────────────────────────────────────────────
display_settings() {
    echo ""
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    local NUM=0
    KEYS=()
    VALUES=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*\[ ]] && continue

        if [[ "$line" == *"="* ]]; then
            NUM=$((NUM + 1))
            local KEY="${line%%=*}"
            local VALUE="${line#*=}"
            KEYS+=("$KEY")
            VALUES+=("$VALUE")

            if [[ "$KEY" == "Field7" || "$KEY" == "Field8" ]]; then
                if [ -n "$VALUE" ]; then
                    echo -e "  ${RED}[$NUM] $KEY = $VALUE  ← WILL BE CLEARED 🔴${NC}"
                else
                    echo -e "  ${GREEN}[$NUM] $KEY = (empty) ✅${NC}"
                fi
            else
                echo -e "  ${GREEN}[$NUM]${NC} $KEY = ${BOLD}$VALUE${NC}"
            fi
        fi
    done < "$INI_PATH"

    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e "  ${CYAN}Total settings: $NUM${NC}"
}

echo ""
echo -e "${YELLOW}[3/5] Current lsagent.ini settings:${NC}"
display_settings

# ─────────────────────────────────────────────
# STEP 4: Interactive edit prompt
# ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[4/5] Review & Edit Settings${NC}"
echo ""
echo -e "  Fields 7 and 8 will be ${RED}automatically cleared${NC}."
echo -e "  If any other settings look wrong (e.g. Server, Port),"
echo -e "  you can edit them now."
echo ""

CHANGES_MADE=false

while true; do
    echo -e "${CYAN}Options:${NC}"
    echo -e "  ${GREEN}[number]${NC}  - Edit a setting by its number"
    echo -e "  ${GREEN}[a]${NC}      - Show all settings again"
    echo -e "  ${GREEN}[c]${NC}      - Continue with rescan"
    echo -e "  ${GREEN}[q]${NC}      - Quit without restarting"
    echo ""
    read -rp "$(echo -e "${YELLOW}Enter choice: ${NC}")" CHOICE

    case "$CHOICE" in
        [0-9]*)
            IDX=$((CHOICE - 1))
            if [ "$IDX" -ge 0 ] && [ "$IDX" -lt "${#KEYS[@]}" ]; then
                echo -e "  Current: ${CYAN}${KEYS[$IDX]}${NC} = ${BOLD}${VALUES[$IDX]}${NC}"
                read -rp "$(echo -e "  ${YELLOW}New value for ${KEYS[$IDX]}: ${NC}")" NEW_VAL
                if [ -n "$NEW_VAL" ]; then
                    OLD_KEY="${KEYS[$IDX]}"
                    # Escape special chars for sed
                    ESCAPED_VAL=$(printf '%s\n' "$NEW_VAL" | sed 's/[&/\]/\\&/g')
                    sed -i '' "s|^${OLD_KEY}=.*|${OLD_KEY}=${ESCAPED_VAL}|" "$INI_PATH"
                    VALUES[$IDX]="$NEW_VAL"
                    CHANGES_MADE=true
                    echo -e "  ${GREEN}✅ Updated: ${OLD_KEY} = ${NEW_VAL}${NC}"
                else
                    echo -e "  ${YELLOW}Skipped (no value entered).${NC}"
                fi
            else
                echo -e "  ${RED}Invalid number. Valid range: 1-${#KEYS[@]}${NC}"
            fi
            echo ""
            ;;
        a|A)
            display_settings
            echo ""
            ;;
        c|C)
            echo ""
            echo -e "${GREEN}  Proceeding with rescan...${NC}"
            break
            ;;
        q|Q)
            echo ""
            echo -e "${YELLOW}  Quitting. LsAgent is still stopped.${NC}"
            echo -e "${YELLOW}  To restart manually:${NC}"
            echo -e "  ${CYAN}sudo launchctl load $PLIST_PATH${NC}"
            exit 0
            ;;
        *)
            echo -e "  ${RED}Invalid choice. Use a number, a, c, or q.${NC}"
            echo ""
            ;;
    esac
done

# ─────────────────────────────────────────────
# Clear Fields 7 and 8
# ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}  Clearing scan cache fields (Field7, Field8)...${NC}"
if grep -q "^Field7=" "$INI_PATH" 2>/dev/null; then
    sed -i '' 's/^Field7=.*/Field7=/' "$INI_PATH"
    echo -e "  ${GREEN}✅ Field7 cleared${NC}"
else
    echo -e "  ${YELLOW}Field7 not found in config (OK)${NC}"
fi
if grep -q "^Field8=" "$INI_PATH" 2>/dev/null; then
    sed -i '' 's/^Field8=.*/Field8=/' "$INI_PATH"
    echo -e "  ${GREEN}✅ Field8 cleared${NC}"
else
    echo -e "  ${YELLOW}Field8 not found in config (OK)${NC}"
fi

# ─────────────────────────────────────────────
# STEP 5: Restart LsAgent
# ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[5/5] Restarting LsAgent...${NC}"

if [ ! -f "$PLIST_PATH" ]; then
    echo -e "${RED}  ERROR: Plist not found at $PLIST_PATH${NC}"
    echo -e "${RED}  Cannot restart LsAgent automatically.${NC}"
    exit 1
fi

launchctl load "$PLIST_PATH"
sleep 3

if pgrep -f lsagent > /dev/null 2>&1; then
    echo -e "${GREEN}  ✅ LsAgent is running — rescan should begin shortly.${NC}"
else
    echo -e "${YELLOW}  ⚠️  LsAgent not detected yet. Waiting 5 more seconds...${NC}"
    sleep 5
    if pgrep -f lsagent > /dev/null 2>&1; then
        echo -e "${GREEN}  ✅ LsAgent started (delayed).${NC}"
    else
        echo -e "${RED}  ❌ LsAgent may not have started. Check:${NC}"
        echo -e "  ${CYAN}log show --predicate 'process == \"lsagent\"' --last 5m${NC}"
    fi
fi

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  ✅ Done — Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "  Backup:        ${GREEN}$BACKUP${NC}"
echo -e "  Field7/8:      ${GREEN}Cleared${NC}"
if [ "$CHANGES_MADE" = true ]; then
    echo -e "  Manual edits:  ${GREEN}Yes${NC}"
else
    echo -e "  Manual edits:  None"
fi
echo -e "  Agent status:  $(pgrep -f lsagent > /dev/null 2>&1 && echo -e "${GREEN}Running ✅${NC}" || echo -e "${RED}Not running ❌${NC}")"
echo ""
