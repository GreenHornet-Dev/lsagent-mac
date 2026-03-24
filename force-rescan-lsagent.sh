#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# force-rescan-lsagent.sh
# Forces Lansweeper Agent to rescan on macOS
# With interactive settings review
# ═══════════════════════════════════════════════════════════════

INI_PATH="/Library/Application Support/LanSweeper/LsAgent/lsagent.ini"
PLIST="com.lansweeper.lsagent.plist"
PLIST_PATH="/Library/LaunchDaemons/$PLIST"

# ─────────────────────────────────────────────
# COLORS for readability
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────
# STEP 1: Stop LsAgent
# ─────────────────────────────────────────────
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  LsAgent Force Rescan Tool (macOS)${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

echo -e "${YELLOW}[1/5] Stopping LsAgent...${NC}"
sudo launchctl unload "$PLIST_PATH" 2>/dev/null
sudo pkill -f lsagent 2>/dev/null
sleep 2

if pgrep -f lsagent > /dev/null; then
    echo -e "${RED}  WARNING: LsAgent may still be running.${NC}"
else
    echo -e "${GREEN}  LsAgent stopped successfully.${NC}"
fi

# ─────────────────────────────────────────────
# STEP 2: Backup the ini
# ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[2/5] Backing up lsagent.ini...${NC}"
if [ -f "$INI_PATH" ]; then
    BACKUP="$INI_PATH.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$INI_PATH" "$BACKUP"
    echo -e "${GREEN}  Backup saved: $BACKUP${NC}"
else
    echo -e "${RED}  ERROR: lsagent.ini not found at:${NC}"
    echo -e "${RED}  $INI_PATH${NC}"
    echo -e "${RED}  Please verify the path and try again.${NC}"
    exit 1
fi

# ─────────────────────────────────────────────
# STEP 3: Display ALL current settings
# ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[3/5] Current lsagent.ini settings:${NC}"
echo -e "${CYAN}────────────────────────────────────────${NC}"

# Read all key=value pairs into arrays
declare -a KEYS
declare -a VALUES
LINE_NUM=0

while IFS= read -r line; do
    # Skip empty lines and comments and section headers
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*\[ ]] && continue

    if [[ "$line" == *"="* ]]; then
        LINE_NUM=$((LINE_NUM + 1))
        KEY="${line%%=*}"
        VALUE="${line#*=}"
        KEYS+=("$KEY")
        VALUES+=("$VALUE")

        # Highlight fields 7 and 8 (will be cleared)
        if [[ "$KEY" == "Field7" || "$KEY" == "Field8" ]]; then
            echo -e "  ${RED}[$LINE_NUM] $KEY = $VALUE  ← WILL BE CLEARED${NC}"
        else
            echo -e "  ${GREEN}[$LINE_NUM]${NC} $KEY = $VALUE"
        fi
    fi
done < "$INI_PATH"

echo -e "${CYAN}────────────────────────────────────────${NC}"
echo ""

# ─────────────────────────────────────────────
# STEP 4: Interactive edit prompt
# ─────────────────────────────────────────────
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
    read -rp "$(echo -e ${YELLOW}"Enter choice: "${NC})" CHOICE

    case "$CHOICE" in
        [0-9]*)
            IDX=$((CHOICE - 1))
            if [ $IDX -ge 0 ] && [ $IDX -lt ${#KEYS[@]} ]; then
                echo -e "  Current: ${CYAN}${KEYS[$IDX]}${NC} = ${VALUES[$IDX]}"
                read -rp "$(echo -e "  ${YELLOW}New value for ${KEYS[$IDX]}: ${NC}")" NEW_VAL
                if [ -n "$NEW_VAL" ]; then
                    OLD_KEY="${KEYS[$IDX]}"
                    OLD_VAL="${VALUES[$IDX]}"
                    sudo sed -i '' "s|^${OLD_KEY}=.*|${OLD_KEY}=${NEW_VAL}|" "$INI_PATH"
                    VALUES[$IDX]="$NEW_VAL"
                    CHANGES_MADE=true
                    echo -e "  ${GREEN}Updated: ${OLD_KEY} = ${NEW_VAL}${NC}"
                else
                    echo -e "  ${YELLOW}Skipped (no value entered).${NC}"
                fi
            else
                echo -e "  ${RED}Invalid number. Try again.${NC}"
            fi
            echo ""
            ;;
        a|A)
            echo ""
            echo -e "${CYAN}────────────────────────────────────────${NC}"
            for i in "${!KEYS[@]}"; do
                NUM=$((i + 1))
                if [[ "${KEYS[$i]}" == "Field7" || "${KEYS[$i]}" == "Field8" ]]; then
                    echo -e "  ${RED}[$NUM] ${KEYS[$i]} = ${VALUES[$i]}  ← WILL BE CLEARED${NC}"
                else
                    echo -e "  ${GREEN}[$NUM]${NC} ${KEYS[$i]} = ${VALUES[$i]}"
                fi
            done
            echo -e "${CYAN}────────────────────────────────────────${NC}"
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
            echo -e "  sudo launchctl load $PLIST_PATH"
            exit 0
            ;;
        *)
            echo -e "  ${RED}Invalid choice. Try again.${NC}"
            echo ""
            ;;
    esac
done

# ─────────────────────────────────────────────
# Clear Fields 7 and 8
# ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}  Clearing Field7 and Field8...${NC}"
sudo sed -i '' 's/^Field7=.*/Field7=/' "$INI_PATH"
sudo sed -i '' 's/^Field8=.*/Field8=/' "$INI_PATH"
echo -e "${GREEN}  Fields cleared.${NC}"

# ─────────────────────────────────────────────
# STEP 5: Restart LsAgent
# ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[5/5] Restarting LsAgent...${NC}"
sudo launchctl load "$PLIST_PATH"
sleep 3

if pgrep -f lsagent > /dev/null; then
    echo -e "${GREEN}  LsAgent is running — rescan should begin shortly.${NC}"
else
    echo -e "${RED}  WARNING: LsAgent may not have started.${NC}"
    echo -e "${RED}  Check logs at: /var/log/lsagent.log${NC}"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Done. Summary:${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "  Backup:        $BACKUP"
echo -e "  Field7/8:      ${GREEN}Cleared${NC}"
if [ "$CHANGES_MADE" = true ]; then
    echo -e "  Manual edits:  ${GREEN}Yes${NC}"
else
    echo -e "  Manual edits:  None"
fi
echo ""
