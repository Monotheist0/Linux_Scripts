#!/bin/bash

# ============================================================================
# SYSTEM INVENTORY SCRIPT FOR FEDORA KDE PLASMA (FIXED VERSION)
# ============================================================================
# Purpose: Generate a comprehensive list of all installed applications and
#          packages for backup and tracking purposes
# Author: Monotheist0
# System: Fedora KDE Plasma 42
# Version: 1
# ============================================================================

# STRICT MODE: Exit on error, undefined variables, and pipe failures
set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OUTPUT_FILE="$HOME/system_inventory_$(date +%Y%m%d_%H%M%S).txt"
readonly TEMP_DIR="$(mktemp -d -t inventory.XXXXXXXXXX)"
readonly ERROR_LOG="${OUTPUT_FILE}.errors"
readonly LOG_FILE="${OUTPUT_FILE}.log"

# CLI Options
GAMING_ONLY=false
INCLUDE_HARDWARE=true
COMPRESS_OUTPUT=true
DRY_RUN=false

# Color codes for terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# ============================================================================
# CLEANUP TRAP
# ============================================================================

cleanup() {
    exit_code=$?
    print_progress "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR" 2>/dev/null || true

    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}✗ Script failed with exit code: $exit_code${NC}" >&2
        echo -e "${YELLOW}Check error log: $ERROR_LOG${NC}" >&2
    fi

    exit "$exit_code"
}

trap cleanup EXIT INT TERM

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
    level="$1"
    shift
    message="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE" >&2
}

print_banner() {
    title="$1"
    {
        echo ""
        echo "╔════════════════════════════════════════════════════════════════════╗"
        printf "║ %-66s ║\n" "$title"
        echo "╚════════════════════════════════════════════════════════════════════╝"
        echo ""
    } | tee -a "$OUTPUT_FILE"
}

print_section() {
    title="$1"
    {
        echo ""
        echo "────────────────────────────────────────────────────────────────────"
        echo "  $title"
        echo "────────────────────────────────────────────────────────────────────"
        echo ""
    } | tee -a "$OUTPUT_FILE"
}

print_progress() {
    echo -e "${BLUE}[INFO]${NC} $*"
    log "INFO" "$*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    log "ERROR" "$*"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
    log "WARN" "$*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log "SUCCESS" "$*"
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Detect package manager (DNF5 vs DNF4)
detect_dnf() {
    if command_exists dnf5; then
        echo "dnf5"
    elif command_exists dnf; then
        echo "dnf"
    else
        echo ""
    fi
}

# ============================================================================
# PARSE COMMAND LINE OPTIONS
# ============================================================================

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Generate a comprehensive system inventory for Fedora KDE Plasma.

OPTIONS:
    -g, --gaming         Focus on gaming packages only
    -n, --no-hardware    Skip hardware information
    -u, --uncompressed   Don't compress output file
    -d, --dry-run        Show what would be done without executing
    -h, --help           Show this help message

EXAMPLES:
    $SCRIPT_NAME                    # Full inventory
    $SCRIPT_NAME -g                 # Gaming packages only
    $SCRIPT_NAME -d                 # Dry run mode

OUTPUT:
    Report: $OUTPUT_FILE
    Errors: $ERROR_LOG
    Log:    $LOG_FILE

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--gaming)
            GAMING_ONLY=true
            shift
            ;;
        -n|--no-hardware)
            INCLUDE_HARDWARE=false
            shift
            ;;
        -u|--uncompressed)
            COMPRESS_OUTPUT=false
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

print_progress "Starting system inventory scan..."
log "INFO" "Script started with PID $$"

# Detect distribution
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    DISTRO="${ID:-unknown}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    DISTRO_NAME="${NAME:-unknown}"
else
    print_error "/etc/os-release not found. Cannot detect distribution."
    exit 1
fi

if [[ "$DISTRO" != "fedora" ]]; then
    print_warning "Non-Fedora system detected: $DISTRO_NAME"
    print_warning "Some features may not work correctly."
fi

# Detect DNF version
DNF_CMD="$(detect_dnf)"
if [[ -z "$DNF_CMD" ]]; then
    print_error "Neither dnf5 nor dnf found. Cannot continue."
    exit 1
fi

print_progress "Using package manager: $DNF_CMD"

# ============================================================================
# CACHE PACKAGE INFORMATION
# ============================================================================

print_progress "Caching package information (this may take a moment)..."

DNF_INSTALLED_CACHE="$TEMP_DIR/dnf_installed.txt"
DNF_USERINSTALLED_CACHE="$TEMP_DIR/dnf_userinstalled.txt"
FLATPAK_CACHE="$TEMP_DIR/flatpak.txt"

# Cache DNF installed packages - FIX: Use rpm as fallback
print_progress "Caching DNF installed packages..."
if ! "$DNF_CMD" list --installed 2>>"$ERROR_LOG" | tail -n +2 > "$DNF_INSTALLED_CACHE"; then
    print_warning "DNF list failed, using RPM as fallback..."
    rpm -qa --qf '%{NAME}.%{ARCH} %{VERSION}-%{RELEASE} @%{VENDOR}\n' | sort > "$DNF_INSTALLED_CACHE" 2>>"$ERROR_LOG" || touch "$DNF_INSTALLED_CACHE"
fi

# Cache user-installed packages
print_progress "Caching user-installed packages..."
if [[ "$DNF_CMD" == "dnf5" ]]; then
    "$DNF_CMD" repoquery --userinstalled 2>>"$ERROR_LOG" > "$DNF_USERINSTALLED_CACHE" || touch "$DNF_USERINSTALLED_CACHE"
else
    "$DNF_CMD" repoquery --userinstalled --qf '%{name}' 2>>"$ERROR_LOG" > "$DNF_USERINSTALLED_CACHE" || touch "$DNF_USERINSTALLED_CACHE"
fi

# Cache Flatpak list
if command_exists flatpak; then
    print_progress "Caching Flatpak packages..."
    flatpak list --app 2>>"$ERROR_LOG" > "$FLATPAK_CACHE" || touch "$FLATPAK_CACHE"
else
    touch "$FLATPAK_CACHE"
fi

print_success "Caching complete"

# ============================================================================
# INITIALIZE OUTPUT FILE
# ============================================================================

cat > "$OUTPUT_FILE" << EOF
╔════════════════════════════════════════════════════════════════════╗
║                                                                    ║
║         FEDORA KDE PLASMA - COMPREHENSIVE SYSTEM INVENTORY         ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝

Generated:     $(date +"%A, %B %d, %Y at %H:%M:%S %Z")
Hostname:      $(hostname)
Distribution:  $DISTRO_NAME $DISTRO_VERSION
Kernel:        $(uname -r)
Architecture:  $(uname -m)
User:          $USER
Package Mgr:   $DNF_CMD
Gaming Focus:  $GAMING_ONLY
Hardware Info: $INCLUDE_HARDWARE

═══════════════════════════════════════════════════════════════════

EOF

# ============================================================================
# SECTION 1: GUI APPLICATIONS (Desktop Entries)
# ============================================================================

if [[ $GAMING_ONLY == false ]]; then
    print_banner "SECTION 1: GUI APPLICATIONS"
    print_progress "Scanning desktop applications..."

    (
        set +e

        desktop_count=0
        desktop_output=""

        if [[ -d /usr/share/applications ]] || [[ -d ~/.local/share/applications ]]; then
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                [[ ! -f "$file" ]] && continue

                if grep -q "^Type=Application" "$file" 2>/dev/null && ! grep -q "^NoDisplay=true" "$file" 2>/dev/null; then
                    ((desktop_count++)) || true

                    name=$(grep -E "^Name=" "$file" 2>/dev/null | head -n 1 | cut -d'=' -f2- || echo "")
                    comment=$(grep -E "^Comment=" "$file" 2>/dev/null | head -n 1 | cut -d'=' -f2- || echo "")
                    exec=$(grep -E "^Exec=" "$file" 2>/dev/null | head -n 1 | cut -d'=' -f2- | awk '{print $1}' || echo "")
                    categories=$(grep -E "^Categories=" "$file" 2>/dev/null | head -n 1 | cut -d'=' -f2- || echo "")

                    if [[ -n "$name" ]]; then
                        desktop_output+="• $name"$'\n'
                        [[ -n "$comment" ]] && desktop_output+="  Description: $comment"$'\n'
                        [[ -n "$exec" ]] && desktop_output+="  Executable: $exec"$'\n'
                        [[ -n "$categories" ]] && desktop_output+="  Categories: $categories"$'\n'
                        desktop_output+=$'\n'
                    fi
                fi
            done < <(find /usr/share/applications ~/.local/share/applications -name "*.desktop" 2>/dev/null || true)
        fi

        echo "Total GUI Applications: $desktop_count"
        echo ""

        if [[ $desktop_count -gt 0 ]]; then
            echo "$desktop_output" | sort -u
        else
            echo "No GUI applications found."
        fi
    ) >> "$OUTPUT_FILE"
fi

# ============================================================================
# SECTION 2: FLATPAK APPLICATIONS
# ============================================================================

if [[ $GAMING_ONLY == false ]] || grep -qiE 'steam|proton|lutris|gaming' "$FLATPAK_CACHE" 2>/dev/null; then
    print_banner "SECTION 2: FLATPAK APPLICATIONS"
    print_progress "Processing Flatpak packages..."

    if command_exists flatpak; then
        (
            set +e
            flatpak_count=0
            [[ -f "$FLATPAK_CACHE" ]] && flatpak_count=$(wc -l < "$FLATPAK_CACHE" 2>/dev/null || echo 0)

            echo "Total Flatpak Applications: $flatpak_count"
            echo ""

            if [[ $flatpak_count -gt 0 ]]; then
                echo "Application Name                    | Application ID                              | Version      | Branch"
                echo "-----------------------------------|---------------------------------------------|--------------|----------"
                flatpak list --app --columns=name,application,version,branch 2>/dev/null | sort || echo "Failed to list Flatpak apps"

                echo ""
                echo "--- Flatpak Runtimes ---"
                echo ""
                flatpak list --runtime --columns=name,version,branch 2>/dev/null | sort || echo "Failed to list runtimes"
            else
                echo "No Flatpak applications installed."
            fi
        ) >> "$OUTPUT_FILE"
    else
        echo "Flatpak is not installed on this system." >> "$OUTPUT_FILE"
    fi
fi

# ============================================================================
# SECTION 3: SNAP PACKAGES
# ============================================================================

print_banner "SECTION 3: SNAP PACKAGES"
print_progress "Scanning Snap packages..."

if command_exists snap; then
    (
        set +e
        snap_count=$(snap list 2>/dev/null | tail -n +2 | wc -l || echo 0)

        echo "Total Snap Packages: $snap_count"
        echo ""

        if [[ $snap_count -gt 0 ]]; then
            snap list 2>/dev/null || echo "Failed to list Snap packages"
        else
            echo "No Snap packages installed."
        fi
    ) >> "$OUTPUT_FILE"
else
    echo "Snap is not installed on this system." >> "$OUTPUT_FILE"
fi

# ============================================================================
# SECTION 4: USER-INSTALLED DNF PACKAGES
# ============================================================================

print_banner "SECTION 4: USER-INSTALLED DNF PACKAGES"
print_progress "Processing user-installed packages..."

(
    set +e
    echo "These are packages explicitly installed by the user (not dependencies)."
    echo ""

    user_pkg_count=0
    [[ -f "$DNF_USERINSTALLED_CACHE" ]] && user_pkg_count=$(wc -l < "$DNF_USERINSTALLED_CACHE" 2>/dev/null || echo 0)

    echo "Total User-Installed Packages: $user_pkg_count"
    echo ""

    if [[ $user_pkg_count -gt 0 ]]; then
        echo "Package Name                          | Version                    | Repository"
        echo "--------------------------------------|----------------------------|------------------"
        "$DNF_CMD" repoquery --userinstalled --qf '%-37{name} | %-26{version} | %{reponame}' 2>/dev/null | sort || echo "Failed to query user packages"
    else
        echo "No user-installed packages found."
    fi
) >> "$OUTPUT_FILE"

# ============================================================================
# SECTION 5: ALL INSTALLED DNF PACKAGES (CATEGORIZED)
# ============================================================================

print_banner "SECTION 5: ALL INSTALLED DNF PACKAGES (CATEGORIZED)"
print_progress "Categorizing all DNF packages..."

(
    set +e
    total_pkg_count=0
    [[ -f "$DNF_INSTALLED_CACHE" ]] && total_pkg_count=$(wc -l < "$DNF_INSTALLED_CACHE" 2>/dev/null || echo 0)

    echo "Total Installed Packages: $total_pkg_count"
    echo ""

    if [[ $total_pkg_count -gt 0 ]]; then
        print_section "5.1 Development Tools & Libraries"
        grep -iE 'devel|gcc|g\+\+|clang|cmake|make|git|python.*dev|lib.*-devel|rust|cargo|nodejs' "$DNF_INSTALLED_CACHE" 2>/dev/null | head -50 | sort || echo "None found"

        print_section "5.2 Gaming & Wine Packages"
        grep -iE 'wine|lutris|gamemode|mangohud|dxvk|mingw|steam|proton|gamescope|nvidia|amd-gpu' "$DNF_INSTALLED_CACHE" 2>/dev/null | sort || echo "None found"

        print_section "5.3 Graphics & Multimedia"
        grep -iE 'vulkan|mesa|ffmpeg|gstreamer|codecs|vlc|gimp|inkscape|blender|krita|kdenlive|obs' "$DNF_INSTALLED_CACHE" 2>/dev/null | sort || echo "None found"

        print_section "5.4 KDE Plasma & Desktop Environment"
        grep -iE 'plasma|kde|kwin|dolphin|konsole|breeze|sddm|wayland' "$DNF_INSTALLED_CACHE" 2>/dev/null | head -50 | sort || echo "None found"

        print_section "5.5 System Libraries & Core Components"
        grep -iE 'systemd|glibc|dbus|polkit|udev|kernel|dracut|grub|firmware' "$DNF_INSTALLED_CACHE" 2>/dev/null | head -50 | sort || echo "None found"

        if [[ $GAMING_ONLY == false ]]; then
            print_section "5.6 Web Browsers & Communication"
            grep -iE 'firefox|chrome|chromium|brave|discord|telegram|slack|zoom' "$DNF_INSTALLED_CACHE" 2>/dev/null | sort || echo "None found"

            print_section "5.7 Office & Productivity"
            grep -iE 'libreoffice|okular|kate|gwenview|spectacle|korganizer' "$DNF_INSTALLED_CACHE" 2>/dev/null | sort || echo "None found"
        fi
    else
        echo "No packages found in cache."
    fi
) >> "$OUTPUT_FILE"

# ============================================================================
# SECTION 6: PACKAGE GROUPS
# ============================================================================

if [[ $GAMING_ONLY == false ]]; then
    print_banner "SECTION 6: INSTALLED PACKAGE GROUPS"
    print_progress "Scanning package groups..."

    (
        set +e
        echo "These are meta-packages that bundle multiple related packages together."
        echo ""
        "$DNF_CMD" group list --installed 2>/dev/null || echo "Failed to list package groups"
    ) >> "$OUTPUT_FILE"
fi

# ============================================================================
# SECTION 7: ENABLED REPOSITORIES
# ============================================================================

if [[ $GAMING_ONLY == false ]]; then
    print_banner "SECTION 7: ENABLED DNF REPOSITORIES"
    print_progress "Scanning repositories..."

    (
        set +e
        "$DNF_CMD" repolist 2>/dev/null || echo "Failed to list repositories"
    ) >> "$OUTPUT_FILE"
fi

# ============================================================================
# SECTION 8: STORAGE USAGE ANALYSIS
# ============================================================================

print_banner "SECTION 8: STORAGE USAGE ANALYSIS"
print_progress "Calculating storage usage..."

(
    set +e
    echo "--- DNF Package Cache ---"
    [[ -d /var/cache/dnf ]] && du -sh /var/cache/dnf 2>/dev/null || echo "Cache directory not found"
    echo ""

    if command_exists flatpak; then
        echo "--- Flatpak Storage ---"
        [[ -d ~/.var/app ]] && du -sh ~/.var/app 2>/dev/null || echo "No Flatpak user data"
        [[ -d /var/lib/flatpak ]] && du -sh /var/lib/flatpak 2>/dev/null || echo "Unable to calculate system Flatpak storage"
        echo ""
    fi

    if command_exists snap; then
        echo "--- Snap Storage ---"
        [[ -d /var/lib/snapd/snaps ]] && du -sh /var/lib/snapd/snaps 2>/dev/null || echo "Unable to calculate"
        echo ""
    fi

    echo "--- Top 20 Largest Installed Packages ---"
    # FIX: Use rpm directly instead of repoquery for size info
    rpm -qa --qf '%{SIZE} %{NAME}\n' 2>/dev/null | sort -rn | head -20 | awk '{printf "%-40s %10.2f MB\n", $2, $1/1024/1024}' || echo "Failed to query package sizes"
) >> "$OUTPUT_FILE"

# ============================================================================
# SECTION 9: HARDWARE INVENTORY
# ============================================================================

if [[ $INCLUDE_HARDWARE == true ]]; then
    print_banner "SECTION 9: HARDWARE INVENTORY"
    print_progress "Scanning hardware..."

    (
        set +e
        echo "--- CPU Information ---"
        command_exists lscpu && lscpu | grep -E 'Model name|Architecture|CPU\(s\)|Thread|Core|Socket|MHz' 2>/dev/null || echo "lscpu not available"
        echo ""

        echo "--- GPU Information ---"
        command_exists lspci && lspci | grep -i 'vga\|3d\|display' 2>/dev/null || echo "lspci not available"
        echo ""

        echo "--- Memory Information ---"
        command_exists free && free -h 2>/dev/null || echo "free not available"
        echo ""

        echo "--- Disk Information ---"
        command_exists lsblk && lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL 2>/dev/null || echo "lsblk not available"
        echo ""

        echo "--- USB Devices ---"
        command_exists lsusb && lsusb 2>/dev/null || echo "lsusb not available"
        echo ""

        echo "--- Network Interfaces ---"
        command_exists ip && ip -brief addr show 2>/dev/null || echo "ip not available"
    ) >> "$OUTPUT_FILE"
fi

# ============================================================================
# SECTION 10: SYSTEM SUMMARY
# ============================================================================

print_banner "SECTION 10: SYSTEM SUMMARY"

(
    set +e
    echo "Inventory Generation Completed: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Total Sections: $(grep -c 'SECTION [0-9]' "$OUTPUT_FILE" 2>/dev/null || echo 0)"
    echo ""
    echo "Quick Statistics:"
    echo "════════════════"

    # Count GUI apps
    gui_count=0
    if [[ -d /usr/share/applications ]] || [[ -d ~/.local/share/applications ]]; then
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            [[ ! -f "$file" ]] && continue
            grep -q "^Type=Application" "$file" 2>/dev/null && ! grep -q "^NoDisplay=true" "$file" 2>/dev/null && ((gui_count++)) || true
        done < <(find /usr/share/applications ~/.local/share/applications -name "*.desktop" 2>/dev/null || true)
    fi
    echo "  • GUI Applications: $gui_count"

    # Flatpak count
    command_exists flatpak && [[ -f "$FLATPAK_CACHE" ]] && echo "  • Flatpak Apps: $(wc -l < "$FLATPAK_CACHE" 2>/dev/null || echo 0)"

    # Snap count
    command_exists snap && echo "  • Snap Packages: $(snap list 2>/dev/null | tail -n +2 | wc -l || echo 0)"

    # DNF packages
    [[ -f "$DNF_INSTALLED_CACHE" ]] && echo "  • Total DNF Packages: $(wc -l < "$DNF_INSTALLED_CACHE" 2>/dev/null || echo 0)"
    [[ -f "$DNF_USERINSTALLED_CACHE" ]] && echo "  • User-Installed Packages: $(wc -l < "$DNF_USERINSTALLED_CACHE" 2>/dev/null || echo 0)"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "                      END OF INVENTORY REPORT"
    echo "════════════════════════════════════════════════════════════════════"
) >> "$OUTPUT_FILE"

# ============================================================================
# POST-PROCESSING
# ============================================================================

print_success "Inventory generation complete!"

# Compress if requested
FINAL_OUTPUT="$OUTPUT_FILE"
if [[ $COMPRESS_OUTPUT == true ]]; then
    print_progress "Compressing output file..."
    if gzip -9 "$OUTPUT_FILE" 2>>"$ERROR_LOG"; then
        FINAL_OUTPUT="${OUTPUT_FILE}.gz"
        print_success "Output compressed successfully"
    else
        print_warning "Compression failed, keeping uncompressed file"
    fi
fi

# ============================================================================
# FINAL REPORT
# ============================================================================

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ System Inventory Complete!${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "📄 Report Location:"
echo "   $FINAL_OUTPUT"
echo ""
echo "📊 File Statistics:"
echo "   Size: $(du -h "$FINAL_OUTPUT" 2>/dev/null | cut -f1 || echo 'N/A')"
if [[ "$FINAL_OUTPUT" == *.gz ]]; then
    echo "   Lines: $(zcat "$FINAL_OUTPUT" 2>/dev/null | wc -l || echo 'N/A')"
else
    echo "   Lines: $(wc -l < "$FINAL_OUTPUT" 2>/dev/null || echo 'N/A')"
fi
echo ""
echo "📝 Additional Files:"
echo "   Error Log: $ERROR_LOG"
echo "   Debug Log: $LOG_FILE"
echo ""
echo "🔍 Quick Commands:"
if [[ "$FINAL_OUTPUT" == *.gz ]]; then
    echo "   View:   zless '$FINAL_OUTPUT'"
    echo "   Search: zgrep -i 'search-term' '$FINAL_OUTPUT'"
else
    echo "   View:   less '$FINAL_OUTPUT'"
    echo "   Search: grep -i 'search-term' '$FINAL_OUTPUT'"
fi
echo ""
echo -e "${CYAN}💡 Tip: Run WITHOUT sudo for better user package detection${NC}"
echo ""
