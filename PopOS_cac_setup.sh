#!/usr/bin/env bash

# Rosé Pine Moon color palette (ANSI escape codes)
RP_GOLD='\033[0;33m'
RP_LOVE='\033[0;31m'
RP_IRIS='\033[0;35m'
RP_NC='\033[0m'

LOG_FILE="/tmp/cac_setup_$(date +%s).log"

ENABLE_FIREFOX=true
ENABLE_CHROME=true

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "INFO") echo -e "${RP_GOLD}[INFO]${RP_NC} [${timestamp}] ${message}" ;;
        "ERROR") echo -e "${RP_LOVE}[ERROR]${RP_NC} [${timestamp}] ${message}" >&2; exit 1 ;;
        "WARN") echo -e "${RP_GOLD}[WARN]${RP_NC} [${timestamp}] ${message}" ;;
        "DEBUG") echo -e "${RP_IRIS}[DEBUG]${RP_NC} [${timestamp}] ${message}" ;;
        *) echo -e "[UNKNOWN] [${timestamp}] ${message}" >&2 ;;
    esac
}

check_root() {
    log "INFO" "Checking root privileges..."
    [ "${EUID:-$(id -u)}" -ne 0 ] && log "ERROR" "Run as sudo."
}

setup_directories() {
    log "INFO" "Setting up user directories..."
    USER_HOME="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}"
    [ -z "$USER_HOME" ] && USER_HOME="$HOME"
    [ -d "$USER_HOME" ] || log "ERROR" "User home directory not found."

    FF_DIR="$(find "$USER_HOME/.mozilla/firefox" -name "*.default*" -type d | head -n1)"
    if [ -z "$FF_DIR" ]; then
        log "WARN" "No Firefox profile found."
        read -rp "$(echo -e "${RP_GOLD}Continue without Firefox support? (y/N): ${RP_NC}")" reply
        [[ ! "$reply" =~ ^[Yy]$ ]] && log "ERROR" "Aborted by user."
        ENABLE_FIREFOX=false
    fi

    CHROME_DIR="$USER_HOME/.pki/nssdb"
    if ! mkdir -p "$CHROME_DIR"; then
        log "WARN" "Failed to create Chrome NSS DB dir."
        read -rp "$(echo -e "${RP_GOLD}Continue without Chrome support? (y/N): ${RP_NC}")" reply
        [[ ! "$reply" =~ ^[Yy]$ ]] && log "ERROR" "Aborted by user."
        ENABLE_CHROME=false
    fi

    [ "$ENABLE_FIREFOX" = true ] && chown -R "$SUDO_USER:$SUDO_USER" "$FF_DIR"
    [ "$ENABLE_CHROME" = true ] && chown -R "$SUDO_USER:$SUDO_USER" "$CHROME_DIR"
}

check_opensc() {
    log "INFO" "Checking OpenSC..."

    OPENSC_LIB=$(find /usr/lib* -name opensc-pkcs11.so 2>/dev/null | head -n1)

    if [ -z "$OPENSC_LIB" ] || [ ! -f "$OPENSC_LIB" ]; then
        log "WARN" "OpenSC PKCS#11 library not found. Attempting to install..."
        apt update >>"$LOG_FILE" 2>&1
        apt install -y opensc opensc-pkcs11 >>"$LOG_FILE" 2>&1 || \
            log "ERROR" "Failed to install OpenSC. Check $LOG_FILE."

        OPENSC_LIB=$(find /usr/lib* -name opensc-pkcs11.so 2>/dev/null | head -n1)
        if [ -z "$OPENSC_LIB" ] || [ ! -f "$OPENSC_LIB" ]; then
            log "ERROR" "OpenSC PKCS#11 library still not found after installation."
        fi
    fi

    pkcs11-tool --module "$OPENSC_LIB" --list-slots >>"$LOG_FILE" 2>&1 || \
        log "WARN" "OpenSC detected but no slots available. You may need to insert a CAC or restart pcscd."

    log "DEBUG" "OpenSC library: $OPENSC_LIB"
}

install_packages() {
    log "INFO" "Installing packages..."
    apt update >>"$LOG_FILE" 2>&1 || log "ERROR" "apt update failed"
    apt install -y pcscd libnss3-tools unzip wget opensc opensc-pkcs11 >>"$LOG_FILE" 2>&1 || \
        log "ERROR" "Package install failed. See $LOG_FILE"
}

clean_nss_databases() {
    log "INFO" "Cleaning old NSS DBs..."
    [ "$ENABLE_FIREFOX" = true ] && rm -f "$FF_DIR"/{cert9.db,key4.db,pkcs11.txt}
    [ "$ENABLE_CHROME" = true ] && rm -f "$CHROME_DIR"/{cert9.db,key4.db,pkcs11.txt}
}

initialize_nss_databases() {
    log "INFO" "Initializing NSS DBs..."
    [ "$ENABLE_FIREFOX" = true ] && certutil -d sql:"$FF_DIR" -N --empty-password >>"$LOG_FILE" 2>&1
    [ "$ENABLE_CHROME" = true ] && certutil -d sql:"$CHROME_DIR" -N --empty-password >>"$LOG_FILE" 2>&1
}

download_certs() {
    log "INFO" "Downloading DoD certs..."
    wget -qP /tmp "https://militarycac.com/maccerts/AllCerts.zip" >>"$LOG_FILE" 2>&1 || \
        log "ERROR" "Failed to download AllCerts.zip"
    unzip -q /tmp/AllCerts.zip -d /tmp/AllCerts >>"$LOG_FILE" 2>&1 || \
        log "ERROR" "Failed to unzip AllCerts.zip"
    [ -z "$(ls /tmp/AllCerts/*.cer 2>/dev/null)" ] && log "ERROR" "No .cer files found."
}

import_certs() {
    log "INFO" "Importing certs..."
    for dir in "$FF_DIR" "$CHROME_DIR"; do
        [ "$ENABLE_FIREFOX" = false ] && [ "$dir" = "$FF_DIR" ] && continue
        [ "$ENABLE_CHROME" = false ] && [ "$dir" = "$CHROME_DIR" ] && continue

        for cert in /tmp/AllCerts/*.cer; do
            certutil -d sql:"$dir" -A -t "CT,," -n "$(basename "$cert")" -i "$cert" >>"$LOG_FILE" 2>&1
        done

        for cert in "DoDRoot3.cer" "DoDRoot4.cer" "DoDRoot5.cer" "DoDRoot6.cer"; do
            certutil -d sql:"$dir" -M -t "CT,C,C" -n "$cert" >>"$LOG_FILE" 2>&1
        done

        echo -e "library=$OPENSC_LIB\nname=OpenSC-PKCS11" > "$dir/pkcs11.txt"
    done
}

start_pcscd() {
    log "INFO" "Starting pcscd..."
    systemctl enable pcscd.socket >>"$LOG_FILE" 2>&1
    systemctl start pcscd.socket >>"$LOG_FILE" 2>&1
}

cleanup() {
    log "INFO" "Cleaning up..."
    rm -rf /tmp/AllCerts.zip /tmp/AllCerts
}

print_instructions() {
    log "INFO" "CAC setup complete."
    [ "$ENABLE_FIREFOX" = true ] && log "INFO" "Firefox configured at $FF_DIR"
    [ "$ENABLE_CHROME" = true ] && log "INFO" "Chrome configured at $CHROME_DIR"
    log "INFO" "Debug log: $LOG_FILE"
}

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

