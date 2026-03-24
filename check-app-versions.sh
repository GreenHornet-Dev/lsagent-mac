#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# check-app-versions.sh  v1.0
# Mac 3rd-Party App Version Checker
#
# Scans installed macOS apps, checks current versions against
# latest releases via Homebrew Cask API, and outputs:
#   🖥️  Color-coded terminal report
#   📄  JSON file for PA-LsAgent Power Automate flow
#
# Can run standalone OR feed into the pa-lsagent spreadsheet
# for fleet-wide outdated-app tracking via Lansweeper.
#
# GreenHornet-Dev / Custom Design Systems
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────
SCRIPT_VERSION="1.0"
APPS_DIR="/Applications"
USER_APPS_DIR="$HOME/Applications"
OUTPUT_DIR="/tmp/lsagent-mac"
JSON_OUTPUT="$OUTPUT_DIR/app-versions-$(hostname)-$(date +%Y%m%d_%H%M%S).json"
LOG_FILE="$OUTPUT_DIR/check-app-versions.log"
BREW_CASK_API="https://formulae.brew.sh/api/cask"

# How long to cache cask lookups (seconds) — avoids hammering the API
CACHE_DIR="$OUTPUT_DIR/.cache"
CACHE_TTL=3600  # 1 hour

# Timeout for API calls (seconds)
CURL_TIMEOUT=10

# ─────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─────────────────────────────────────────────
# KNOWN APP → CASK MAPPINGS
# Common Mac apps that don't have obvious cask names
# Add your own here or load from version-check-apps.json
# ─────────────────────────────────────────────
declare -A CASK_MAP
CASK_MAP=(
    # Browsers
    ["Google Chrome"]="google-chrome"
    ["Firefox"]="firefox"
    ["Mozilla Firefox"]="firefox"
    ["Microsoft Edge"]="microsoft-edge"
    ["Brave Browser"]="brave-browser"
    ["Arc"]="arc"
    # Communication
    ["Zoom"]="zoom"
    ["zoom.us"]="zoom"
    ["Slack"]="slack"
    ["Microsoft Teams"]="microsoft-teams"
    ["Microsoft Teams classic"]="microsoft-teams"
    ["Discord"]="discord"
    ["Signal"]="signal"
    # Microsoft Office
    ["Microsoft Outlook"]="microsoft-outlook"
    ["Microsoft Word"]="microsoft-word"
    ["Microsoft Excel"]="microsoft-excel"
    ["Microsoft PowerPoint"]="microsoft-powerpoint"
    ["Microsoft OneNote"]="microsoft-onenote"
    ["OneDrive"]="onedrive"
    # Development
    ["Visual Studio Code"]="visual-studio-code"
    ["iTerm"]="iterm2"
    ["Docker"]="docker"
    ["Postman"]="postman"
    ["GitHub Desktop"]="github"
    ["Sublime Text"]="sublime-text"
    # Security
    ["1Password 7 - Password Manager"]="1password@7"
    ["1Password"]="1password"
    ["Bitwarden"]="bitwarden"
    ["KeePassXC"]="keepassxc"
    ["Malwarebytes"]="malwarebytes"
    # Utilities
    ["VLC"]="vlc"
    ["Adobe Acrobat Reader"]="adobe-acrobat-reader"
    ["Adobe Creative Cloud"]="adobe-creative-cloud"
    ["Cyberduck"]="cyberduck"
    ["Spotify"]="spotify"
    ["Figma"]="figma"
    ["Notion"]="notion"
    ["Obsidian"]="obsidian"
    ["Tailscale"]="tailscale"
    # Cloud Storage
    ["Dropbox"]="dropbox"
    ["Google Drive"]="google-drive"
    # Remote Access
    ["TeamViewer"]="teamviewer"
    ["AnyDesk"]="anydesk"
    ["GoTo Resolve"]="goto-resolve"
    # Virtualization
    ["Parallels Desktop"]="parallels"
    ["VMware Fusion"]="vmware-fusion"
    # System
    ["Wireshark"]="wireshark"
    ["Rectangle"]="rectangle"
    ["AppCleaner"]="appcleaner"
    ["The Unarchiver"]="the-unarchiver"
    ["Keka"]="keka"
)

# ─────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR" "$CACHE_DIR" 2>/dev/null

# ─────────────────────────────────────────────
# HELPER: Get installed version from Info.plist
# ─────────────────────────────────────────────
get_installed_version() {
    local APP_PATH="$1"
    local PLIST="$APP_PATH/Contents/Info.plist"

    if [ ! -f "$PLIST" ]; then
        echo "unknown"
        return
    fi

    # Try CFBundleShortVersionString first (human-readable), then CFBundleVersion
    local VER
    VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null)
    if [ -z "$VER" ] || [ "$VER" = "" ]; then
        VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null)
    fi

    if [ -z "$VER" ] || [ "$VER" = "" ]; then
        echo "unknown"
    else
        echo "$VER"
    fi
}

# ─────────────────────────────────────────────
# HELPER: Get bundle identifier
# ─────────────────────────────────────────────
get_bundle_id() {
    local APP_PATH="$1"
    local PLIST="$APP_PATH/Contents/Info.plist"

    if [ ! -f "$PLIST" ]; then
        echo "unknown"
        return
    fi

    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST" 2>/dev/null || echo "unknown"
}

# ─────────────────────────────────────────────
# HELPER: Normalize app name to cask token
# ─────────────────────────────────────────────
name_to_cask() {
    local NAME="$1"

    # Check the explicit map first
    if [ -n "${CASK_MAP[$NAME]+x}" ]; then
        echo "${CASK_MAP[$NAME]}"
        return
    fi

    # Auto-generate: lowercase, spaces→hyphens, strip special chars
    echo "$NAME" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g; s/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//'
}

# ─────────────────────────────────────────────
# HELPER: Query Homebrew Cask API for latest version
# Uses local cache to avoid repeated API hits
# ─────────────────────────────────────────────
get_latest_version() {
    local CASK_TOKEN="$1"
    local CACHE_FILE="$CACHE_DIR/${CASK_TOKEN}.json"

    # Check cache
    if [ -f "$CACHE_FILE" ]; then
        local CACHE_AGE
        CACHE_AGE=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
        if [ "$CACHE_AGE" -lt "$CACHE_TTL" ]; then
            # Use cached version
            local CACHED_VER
            CACHED_VER=$(cat "$CACHE_FILE" 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$CACHED_VER" ]; then
                echo "$CACHED_VER"
                return
            fi
        fi
    fi

    # Fetch from API
    local RESPONSE
    RESPONSE=$(curl -s --max-time "$CURL_TIMEOUT" "${BREW_CASK_API}/${CASK_TOKEN}.json" 2>/dev/null)

    if [ -z "$RESPONSE" ] || echo "$RESPONSE" | grep -q '"error"' 2>/dev/null; then
        echo "not_found"
        return
    fi

    # Cache the response
    echo "$RESPONSE" > "$CACHE_FILE" 2>/dev/null

    # Extract version
    local VER
    VER=$(echo "$RESPONSE" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$VER" ] || [ "$VER" = "latest" ]; then
        echo "latest"
    else
        echo "$VER"
    fi
}

# ─────────────────────────────────────────────
# HELPER: Compare versions (basic semver)
# Returns: "outdated", "current", "newer", "unknown"
# ─────────────────────────────────────────────
compare_versions() {
    local INSTALLED="$1"
    local LATEST="$2"

    # Can't compare unknowns
    if [ "$INSTALLED" = "unknown" ] || [ "$LATEST" = "not_found" ] || [ "$LATEST" = "latest" ]; then
        echo "unknown"
        return
    fi

    # Exact match (most common case)
    if [ "$INSTALLED" = "$LATEST" ]; then
        echo "current"
        return
    fi

    # Strip everything after first space or dash-alpha (e.g., "1.2.3 (1234)" → "1.2.3")
    local I_CLEAN L_CLEAN
    I_CLEAN=$(echo "$INSTALLED" | sed 's/[[:space:]].*//' | sed 's/-[a-zA-Z].*//')
    L_CLEAN=$(echo "$LATEST" | sed 's/[[:space:]].*//' | sed 's/-[a-zA-Z].*//')

    if [ "$I_CLEAN" = "$L_CLEAN" ]; then
        echo "current"
        return
    fi

    # Numeric comparison using sort -V
    local HIGHER
    HIGHER=$(printf '%s\n%s' "$I_CLEAN" "$L_CLEAN" | sort -V | tail -1)

    if [ "$HIGHER" = "$L_CLEAN" ] && [ "$I_CLEAN" != "$L_CLEAN" ]; then
        echo "outdated"
    elif [ "$HIGHER" = "$I_CLEAN" ]; then
        echo "newer"
    else
        echo "unknown"
    fi
}

# ═══════════════════════════════════════════════════════════════
#   MAIN SCAN
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  🟢 Mac App Version Checker  v${SCRIPT_VERSION}${NC}"
echo -e "${CYAN}  GreenHornet-Dev / Custom Design Systems${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${DIM}  Host:    $(hostname)${NC}"
echo -e "${DIM}  macOS:   $(sw_vers -productVersion 2>/dev/null || echo 'unknown')${NC}"
echo -e "${DIM}  Date:    $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${DIM}  Output:  $JSON_OUTPUT${NC}"
echo ""

# Counters
TOTAL=0
OUTDATED=0
CURRENT=0
UNKNOWN=0
NEWER=0

# JSON array start
JSON_ITEMS="["

# Scan /Applications and ~/Applications
echo -e "${YELLOW}Scanning installed apps...${NC}"
echo ""
printf "  ${BOLD}%-35s %-15s %-15s %-10s${NC}\n" "APP NAME" "INSTALLED" "LATEST" "STATUS"
echo -e "  ${CYAN}───────────────────────────────────────────────────────────────────────────────${NC}"

for DIR in "$APPS_DIR" "$USER_APPS_DIR"; do
    [ ! -d "$DIR" ] && continue

    for APP_PATH in "$DIR"/*.app; do
        [ ! -d "$APP_PATH" ] && continue

        APP_NAME=$(basename "$APP_PATH" .app)
        INSTALLED_VER=$(get_installed_version "$APP_PATH")
        BUNDLE_ID=$(get_bundle_id "$APP_PATH")
        CASK_TOKEN=$(name_to_cask "$APP_NAME")

        # Skip Apple built-in apps (com.apple.*)
        if [[ "$BUNDLE_ID" == com.apple.* ]]; then
            continue
        fi

        # Skip known system apps
        case "$APP_NAME" in
            "Xcode"|"Safari"|"Mail"|"Maps"|"Notes"|"Reminders"|"Calendar"|"FaceTime"|"Messages"|"Photos"|"Preview"|"Music"|"TV"|"Podcasts"|"Books"|"News"|"Stocks"|"Home"|"Voice Memos"|"Shortcuts"|"Find My"|"Freeform"|"Clock"|"Calculator"|"Weather"|"Journal"|"Passwords")
                continue
                ;;
        esac

        LATEST_VER=$(get_latest_version "$CASK_TOKEN")
        STATUS=$(compare_versions "$INSTALLED_VER" "$LATEST_VER")

        TOTAL=$((TOTAL + 1))

        # Display status with color
        case "$STATUS" in
            "outdated")
                OUTDATED=$((OUTDATED + 1))
                STATUS_ICON="🔴 UPDATE"
                STATUS_COLOR="$RED"
                ;;
            "current")
                CURRENT=$((CURRENT + 1))
                STATUS_ICON="🟢 OK"
                STATUS_COLOR="$GREEN"
                ;;
            "newer")
                NEWER=$((NEWER + 1))
                STATUS_ICON="🔵 NEWER"
                STATUS_COLOR="$CYAN"
                ;;
            *)
                UNKNOWN=$((UNKNOWN + 1))
                STATUS_ICON="⚪ N/A"
                STATUS_COLOR="$DIM"
                ;;
        esac

        # Truncate long names for display
        DISPLAY_NAME="$APP_NAME"
        if [ ${#DISPLAY_NAME} -gt 33 ]; then
            DISPLAY_NAME="${DISPLAY_NAME:0:30}..."
        fi

        printf "  ${STATUS_COLOR}%-35s %-15s %-15s %-10s${NC}\n" \
            "$DISPLAY_NAME" "$INSTALLED_VER" "$LATEST_VER" "$STATUS_ICON"

        # Build JSON entry
        # Escape quotes in values
        local J_NAME J_VER J_LATEST J_CASK J_BUNDLE
        J_NAME=$(echo "$APP_NAME" | sed 's/"/\\"/g')
        J_VER=$(echo "$INSTALLED_VER" | sed 's/"/\\"/g')
        J_LATEST=$(echo "$LATEST_VER" | sed 's/"/\\"/g')
        J_CASK=$(echo "$CASK_TOKEN" | sed 's/"/\\"/g')
        J_BUNDLE=$(echo "$BUNDLE_ID" | sed 's/"/\\"/g')

        if [ "$TOTAL" -gt 1 ]; then
            JSON_ITEMS="$JSON_ITEMS,"
        fi

        JSON_ITEMS="$JSON_ITEMS
    {
      \"appName\": \"$J_NAME\",
      \"bundleId\": \"$J_BUNDLE\",
      \"installedVersion\": \"$J_VER\",
      \"latestVersion\": \"$J_LATEST\",
      \"caskToken\": \"$J_CASK\",
      \"status\": \"$STATUS\",
      \"hostname\": \"$(hostname)\",
      \"scanDate\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"
    }"

    done
done

# Close JSON
JSON_ITEMS="$JSON_ITEMS
]"

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}───────────────────────────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  📊 Summary — $(hostname)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Total scanned:    ${BOLD}$TOTAL${NC}"
echo -e "  ${GREEN}🟢 Up to date:     $CURRENT${NC}"
echo -e "  ${RED}🔴 Needs update:   $OUTDATED${NC}"
echo -e "  ${CYAN}🔵 Newer than repo: $NEWER${NC}"
echo -e "  ${DIM}⚪ Unknown/N/A:    $UNKNOWN${NC}"
echo ""

if [ "$OUTDATED" -gt 0 ]; then
    echo -e "${RED}${BOLD}  ⚠️  $OUTDATED app(s) need updating!${NC}"
    echo ""
    echo -e "  ${YELLOW}Outdated apps:${NC}"
    # Re-scan just for the outdated list
    for DIR in "$APPS_DIR" "$USER_APPS_DIR"; do
        [ ! -d "$DIR" ] && continue
        for APP_PATH in "$DIR"/*.app; do
            [ ! -d "$APP_PATH" ] && continue
            APP_NAME=$(basename "$APP_PATH" .app)
            BUNDLE_ID=$(get_bundle_id "$APP_PATH")
            [[ "$BUNDLE_ID" == com.apple.* ]] && continue
            INSTALLED_VER=$(get_installed_version "$APP_PATH")
            CASK_TOKEN=$(name_to_cask "$APP_NAME")
            LATEST_VER=$(get_latest_version "$CASK_TOKEN")  # Cached, so fast
            STATUS=$(compare_versions "$INSTALLED_VER" "$LATEST_VER")
            if [ "$STATUS" = "outdated" ]; then
                echo -e "    ${RED}• $APP_NAME${NC}  ${DIM}$INSTALLED_VER → $LATEST_VER${NC}"
            fi
        done
    done
    echo ""
else
    echo -e "${GREEN}${BOLD}  ✅ All apps are up to date!${NC}"
    echo ""
fi

# ─────────────────────────────────────────────
# WRITE JSON OUTPUT
# ─────────────────────────────────────────────
JSON_FULL="{
  \"hostname\": \"$(hostname)\",
  \"macosVersion\": \"$(sw_vers -productVersion 2>/dev/null || echo 'unknown')\",
  \"scanDate\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\",
  \"scriptVersion\": \"$SCRIPT_VERSION\",
  \"summary\": {
    \"total\": $TOTAL,
    \"current\": $CURRENT,
    \"outdated\": $OUTDATED,
    \"newer\": $NEWER,
    \"unknown\": $UNKNOWN
  },
  \"apps\": $JSON_ITEMS
}"

echo "$JSON_FULL" > "$JSON_OUTPUT"

echo -e "${GREEN}  📄 JSON report saved: ${BOLD}$JSON_OUTPUT${NC}"
echo ""
echo -e "${DIM}  Feed this JSON to the pa-lsagent Power Automate flow${NC}"
echo -e "${DIM}  to sync with the tblMacSoftware Excel table.${NC}"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  🟢 Done — $(hostname) — $(date '+%H:%M:%S')${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
