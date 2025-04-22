#!/usr/bin/env bash
# cac_setup.sh
# CAC setup for Arch Linux with OpenSC, using Rosé Pine Moon theme

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

[ "${EUID:-$(id -u)}" -ne 0 ] && { log "ERROR" "Run as sudo."; }

USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
CHROME_DIR="$USER_HOME/.pki/nssdb"
OPENSC_LIB="/usr/lib/opensc-pkcs11.so"

log "INFO" "Installing packages..."
pacman -Sy || { log "ERROR" "Pacman sync failed."; }
pacman -S --needed pcsclite ccid nss unzip wget opensc pcsc-tools firefox || { log "ERROR" "Package installation failed."; }

log "INFO" "Starting pcscd..."
systemctl enable pcscd.socket || { log "ERROR" "Failed to enable pcscd.socket."; }
systemctl start pcscd.socket || { log "ERROR" "Failed to start pcscd.socket."; }

log "INFO" "Checking OpenSC library..."
[ -f "$OPENSC_LIB" ] || { log "ERROR" "OpenSC library not found at $OPENSC_LIB."; }

log "INFO" "Finding Firefox profiles..."
FF_DIRS=($(find "$USER_HOME/.mozilla/firefox" -name "*.default*" -type d))
[ ${#FF_DIRS[@]} -eq 0 ] && { log "ERROR" "No Firefox profiles found in $USER_HOME/.mozilla/firefox. Create a profile with 'firefox --ProfileManager'."; }
log "DEBUG" "Found Firefox profiles: ${FF_DIRS[*]}"

log "INFO" "Cleaning temporary certificate directory..."
rm -rf /tmp/AllCerts /tmp/AllCerts.zip

log "INFO" "Downloading DoD certificates..."
wget -qP /tmp "https://militarycac.com/maccerts/AllCerts.zip" || { log "ERROR" "Failed to download DoD certificates."; }
unzip -qo /tmp/AllCerts.zip -d /tmp/AllCerts || { log "ERROR" "Failed to unzip DoD certificates."; }

for dir in "${FF_DIRS[@]}" "$CHROME_DIR"; do
    log "INFO" "Configuring NSS database for $dir..."
    rm -f "$dir"/{cert9.db,key4.db,pkcs11.txt}
    [ "$dir" = "$CHROME_DIR" ] && mkdir -p "$CHROME_DIR"

    log "INFO" "Initializing NSS database for $dir..."
    certutil -d sql:"$dir" -N --empty-password || { log "ERROR" "Failed to initialize NSS database for $dir."; }

    log "INFO" "Adding PKCS#11 module for $dir..."
    modutil -dbdir sql:"$dir" -add "OpenSC-PKCS11" -libfile "$OPENSC_LIB" -force || { log "ERROR" "Failed to add PKCS#11 module for $dir"; }
    log "DEBUG" "modutil output for $dir: $(modutil -dbdir sql:"$dir" -list | grep -i OpenSC || echo 'No OpenSC module found')"

    log "INFO" "Importing DoD certificates for $dir..."
    for cert in /tmp/AllCerts/*.cer; do
        if [ -f "$cert" ]; then
            cert_name="$(basename "$cert")"
            certutil -d sql:"$dir" -A -t "CT,," -n "$cert_name" -i "$cert" || { log "ERROR" "Failed to import certificate: $cert_name in $dir"; }
            log "DEBUG" "Imported certificate: $cert_name in $dir"
        fi
    done
    for cert in "DoDRoot3.cer" "DoDRoot4.cer" "DoDRoot5.cer" "DoDRoot6.cer"; do
        if certutil -d sql:"$dir" -L | grep -q "$cert"; then
            certutil -d sql:"$dir" -M -t "CT,C,C" -n "$cert" || { log "ERROR" "Failed to set trust for $cert in $dir"; }
            log "DEBUG" "Set trust for $cert in $dir"
        else
            log "WARN" "Certificate $cert not found in $dir"
        fi
    done

    log "INFO" "Setting permissions for $dir..."
    chown "$SUDO_USER":"$SUDO_USER" "$dir"/{cert9.db,key4.db,pkcs11.txt} 2>/dev/null
    chmod 600 "$dir"/{cert9.db,key4.db,pkcs11.txt} 2>/dev/null

    log "INFO" "Verifying NSS database setup for $dir..."
    [ -f "$dir/cert9.db" ] || { log "ERROR" "$dir/cert9.db not created."; }
    log "DEBUG" "NSS files for $dir: $(ls -l "$dir"/{cert9.db,pkcs11.txt} 2>/dev/null || echo 'Files missing')"
    log "DEBUG" "Certs for $dir: $(certutil -d sql:"$dir" -L | grep -E 'DoDRoot[3-6]' || echo 'No DoD certs found')"
    log "DEBUG" "PKCS#11 module for $dir: $(certutil -d sql:"$dir" -U | grep -i OpenSC || echo 'No PKCS#11 module found')"
done

log "INFO" "Cleaning up..."
rm -rf /tmp/AllCerts /tmp/AllCerts.zip

log "INFO" "CAC setup complete. To test in Firefox/Chrome:"
log "INFO" "1. Ensure CAC reader (e.g., SCM SCR3500) is plugged in and CAC card is inserted."
log "INFO" "2. Open browser and go to Preferences > Privacy & Security > Security Devices (Firefox) or Settings > Privacy and Security > Manage Certificates (Chrome)."
log "INFO" "3. Verify 'OpenSC-PKCS11' is listed. If not, load it with path $OPENSC_LIB."
log "INFO" "To debug: pkcs11-tool --module $OPENSC_LIB --list-objects"
exit 0
