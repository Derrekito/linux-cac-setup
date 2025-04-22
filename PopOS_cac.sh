#!/usr/bin/env bash
# cac_setup.sh
# CAC setup for Debian Distributions e.g., Pop!_OS 22.04, Ubuntu with OpenSC
# Configures OpenSC, NSS databases, and DoD certificates for Firefox/Chrome

# Rosé Pine Moon color palette (ANSI escape codes)
RP_BASE='\033[0;30m'      # #232136 (not used for text)
RP_SURFACE='\033[0;30m'   # #2a273f (not used for text)
RP_OVERLAY='\033[0;30m'   # #393552
RP_MUTED='\033[0;37m'     # #6e6a86
RP_TEXT='\033[0;37m'      # #e0def4 (bright white for text)
RP_LOVE='\033[0;31m'      # #eb6f92 (bright red for errors)
RP_GOLD='\033[0;33m'      # #f6c177 (yellow for info/warn)
RP_ROSE='\033[0;31m'      # #ea9a97
RP_PINE='\033[0;36m'      # #3e8fb0 (cyan)
RP_FOAM='\033[0;36m'      # #9ccfd8 (light cyan)
RP_IRIS='\033[0;35m'      # #c4a7e7 (magenta)
RP_NC='\033[0m'           # No Color (reset)

# Log file for debugging
LOG_FILE="/tmp/cac_setup_$(date +%s).log"

# Log function with Rosé Pine Moon colors
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "INFO")
            echo -e "${RP_GOLD}[INFO]${RP_NC} [${timestamp}] ${message}"
            ;;
        "ERROR")
            echo -e "${RP_LOVE}[ERROR]${RP_NC} [${timestamp}] ${message}" >&2
            exit 1
            ;;
        "WARN")
            echo -e "${RP_GOLD}[WARN]${RP_NC} [${timestamp}] ${message}"
            ;;
        "DEBUG")
            echo -e "${RP_IRIS}[DEBUG]${RP_NC} [${timestamp}] ${message}"
            ;;
        *)
            echo -e "${RP_MUTED}[UNKNOWN]${RP_NC} [${timestamp}] ${message}" >&2
            ;;
    esac
}

# Function: Check if script is run as root
check_root() {
    log "INFO" "Checking root privileges..."
    [ "${EUID:-$(id -u)}" -ne 0 ] && log "ERROR" "Run as sudo."
}

# Function: Set up user home and browser directories
setup_directories() {
    log "INFO" "Setting up user directories..."
    USER_HOME="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}"
    [ -z "$USER_HOME" ] && USER_HOME="$HOME"
    [ -d "$USER_HOME" ] || log "ERROR" "User home directory not found."

    FF_DIR="$(find "$USER_HOME/.mozilla/firefox" -name "*.default*" -type d | head -n1)"
    [ -z "$FF_DIR" ] && log "ERROR" "No Firefox profile found in $USER_HOME/.mozilla/firefox."

    CHROME_DIR="$USER_HOME/.pki/nssdb"
    mkdir -p "$CHROME_DIR" || log "ERROR" "Failed to create $CHROME_DIR."

    # Set permissions
    chown -R "$SUDO_USER:$SUDO_USER" "$FF_DIR" "$CHROME_DIR" || log "ERROR" "Failed to set permissions for $SUDO_USER."

    log "DEBUG" "Firefox dir: $FF_DIR"
    log "DEBUG" "Chrome dir: $CHROME_DIR"
}

# Function: Check and locate OpenSC library
check_opensc() {
    log "INFO" "Checking OpenSC..."
    OPENSC_LIB=$(find /usr/lib* -name opensc-pkcs11.so 2>/dev/null | head -n1)
    [ -z "$OPENSC_LIB" ] && log "ERROR" "OpenSC PKCS#11 library not found."
    [ -f "$OPENSC_LIB" ] || log "ERROR" "OpenSC not found at $OPENSC_LIB. Install opensc-pkcs11."

    pkcs11-tool --module "$OPENSC_LIB" --list-slots >>"$LOG_FILE" 2>&1 || \
        log "ERROR" "OpenSC failed to list slots. See $LOG_FILE for details."

    log "DEBUG" "OpenSC library: $OPENSC_LIB"
}

# Function: Install required packages
install_packages() {
    log "INFO" "Installing packages..."
    for cmd in certutil pkcs11-tool wget unzip; do
        command -v "$cmd" >/dev/null || log "WARN" "$cmd not found, will attempt to install."
    done

    ping -c 1 archive.ubuntu.com >/dev/null 2>&1 || log "WARN" "No network connectivity. Apt may fail."
    apt update >>"$LOG_FILE" 2>&1 || log "ERROR" "Apt update failed. See $LOG_FILE for details."
    apt install -y -f >>"$LOG_FILE" 2>&1 || log "ERROR" "Dependency resolution failed. See $LOG_FILE for details."
    apt install -y pcscd libnss3-tools unzip wget opensc opensc-pkcs11 >>"$LOG_FILE" 2>&1 || \
        log "ERROR" "Install failed. Check $LOG_FILE for details."
    log "INFO" "Required packages installed successfully."
}

# Function: Clean old NSS databases
clean_nss_databases() {
    log "INFO" "Cleaning old NSS databases..."
    rm -f "$FF_DIR/cert9.db" "$FF_DIR/key4.db" "$FF_DIR/pkcs11.txt"
    rm -f "$CHROME_DIR/cert9.db" "$CHROME_DIR/key4.db" "$CHROME_DIR/pkcs11.txt"

    # Ensure directories are writable
    chown -R "$SUDO_USER:$SUDO_USER" "$FF_DIR" "$CHROME_DIR" || log "ERROR" "Failed to set permissions for $SUDO_USER."
}

# Function: Initialize NSS databases
initialize_nss_databases() {
    log "INFO" "Initializing NSS databases..."
    certutil -d sql:"$FF_DIR" -N --empty-password >>"$LOG_FILE" 2>&1 || \
        log "ERROR" "Failed to init Firefox NSS DB. Check certutil version or NSS DB path. See $LOG_FILE."
    certutil -d sql:"$CHROME_DIR" -N --empty-password >>"$LOG_FILE" 2>&1 || \
        log "ERROR" "Failed to init Chrome NSS DB. See $LOG_FILE."

    chown -R "$SUDO_USER:$SUDO_USER" "$FF_DIR" "$CHROME_DIR" || log "ERROR" "Failed to set permissions for $SUDO_USER."
}

# Function: Download and extract DoD certificates
download_certs() {
    log "INFO" "Downloading DoD certs..."
    wget -qP /tmp "https://militarycac.com/maccerts/AllCerts.zip" >>"$LOG_FILE" 2>&1 || \
        log "ERROR" "Cert download failed. Ensure network access or manually download AllCerts.zip from https://militarycac.com."

    unzip -q /tmp/AllCerts.zip -d /tmp/AllCerts >>"$LOG_FILE" 2>&1 || log "ERROR" "Unzip failed."
    [ -z "$(ls /tmp/AllCerts/*.cer 2>/dev/null)" ] && log "ERROR" "No .cer files found in /tmp/AllCerts."
}

# Function: Import DoD certificates and configure PKCS#11
import_certs() {
    log "INFO" "Importing DoD certs..."
    for dir in "$FF_DIR" "$CHROME_DIR"; do
        for cert in /tmp/AllCerts/*.cer; do
            [ -f "$cert" ] && certutil -d sql:"$dir" -A -t "CT,," -n "$(basename "$cert")" -i "$cert" >>"$LOG_FILE" 2>&1 || \
                log "ERROR" "Cert import failed: $cert in $dir. See $LOG_FILE."
        done
        for cert in "DoDRoot3.cer" "DoDRoot4.cer" "DoDRoot5.cer" "DoDRoot6.cer"; do
            certutil -d sql:"$dir" -M -t "CT,C,C" -n "$cert" >>"$LOG_FILE" 2>&1 || \
                log "ERROR" "Failed to set trust for $cert in $dir. See $LOG_FILE."
        done
        echo -e "library=$OPENSC_LIB\nname=OpenSC-PKCS11" > "$dir/pkcs11.txt" || \
            log "ERROR" "Failed to configure $dir/pkcs11.txt"
    done

    chown -R "$SUDO_USER:$SUDO_USER" "$FF_DIR" "$CHROME_DIR" || log "ERROR" "Failed to set permissions for $SUDO_USER."
}

# Function: Start pcscd service
start_pcscd() {
    log "INFO" "Starting pcscd..."
    systemctl --version >/dev/null 2>&1 || log "ERROR" "Systemd not detected. Ensure pcscd is running manually."
    systemctl enable pcscd.socket >>"$LOG_FILE" 2>&1 || log "ERROR" "Enable pcscd.socket failed. See $LOG_FILE."
    systemctl start pcscd.socket >>"$LOG_FILE" 2>&1 || log "ERROR" "Start pcscd.socket failed. See $LOG_FILE."
}

# Function: Clean up temporary files
cleanup() {
    log "INFO" "Cleaning up..."
    rm -rf /tmp/AllCerts.zip /tmp/AllCerts
}

# Function: Print final instructions
print_instructions() {
    log "INFO" "CAC setup complete. Test in Firefox/Chrome:"
    log "INFO" "1. Open browser with CAC inserted."
    log "INFO" "2. Select 'Certificate for PIV Authentication' when prompted."
    log "INFO" "3. Verify 'OpenSC-PKCS11' is listed. If not, load it with path $OPENSC_LIB."
    log "INFO" "To debug: pkcs11-tool --module $OPENSC_LIB --list-objects"
    log "INFO" "Debug log: $LOG_FILE"
}

# Main execution flow
check_root
setup_directories
check_opensc
install_packages
clean_nss_databases
initialize_nss_databases
download_certs
import_certs
start_pcscd
cleanup
print_instructions

exit 0
