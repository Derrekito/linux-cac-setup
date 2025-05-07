#!/usr/bin/env bash

# Rosé Pine Moon color palette (ANSI escape codes)
RP_BASE='\033[48;5;235m'   # Dark background (example)
RP_SURFACE='\033[48;5;237m' # Slightly lighter background
RP_OVERLAY='\033[38;5;244m' # Muted text color
RP_MUTED='\033[38;5;102m'     # #6e6a86
RP_TEXT='\033[38;5;231m'      # #e0def4 (bright white for text)
RP_LOVE='\033[38;5;161m'      # #eb6f92 (bright red for errors)
RP_GOLD='\033[38;5;214m'      # #f6c177 (yellow for info/warn)
RP_ROSE='\033[38;5;204m'      # #ea9a97
RP_PINE='\033[38;5;37m'      # #3e8fb0 (cyan)
RP_FOAM='\033[38;5;117m'      # #9ccfd8 (light cyan)
RP_IRIS='\033[38;5;139m'      # #c4a7e7 (magenta)
RP_NC='\033[0m'           # No Color (reset)

LOG_FILE="/tmp/cac_setup_$(date +%s).log"

ENABLE_FIREFOX=true
ENABLE_CHROME=true

# --- Print Instructions ---
print_instructions() {
  [ "$ENABLE_FIREFOX" = true ] && log "INFO" "Firefox configured at $FF_DIR"
  [ "$ENABLE_CHROME" = true ] && log "INFO" "Chrome configured at $CHROME_DIR"
  log "INFO" "Debug log: $LOG_FILE"
  log "INFO" "CAC setup complete. To test in Firefox/Chrome:"
  log "INFO" "1. Ensure CAC reader (e.g., SCM SCR3500) is plugged in and CAC card is inserted."
  log "INFO" "2. Open browser and go to Preferences > Privacy & Security > Security Devices (Firefox) or Settings > Privacy and Security > Manage Certificates (Chrome)."
  log "INFO" "3. Verify 'OpenSC-PKCS11' is listed. If not, load it with path $OPENSC_LIB."
  log "INFO" "To debug: pkcs11-tool --module $OPENSC_LIB --list-objects"
}

# --- Logging Functions ---
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

# --- Utility Functions ---
require_root() {
  log "INFO" "Checking root privileges..."
  [ "${EUID:-$(id -u)}" -ne 0 ] && log "ERROR" "Run as sudo."
}

get_user_home() {
  if [ -n "$SUDO_USER" ]; then
    echo "$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  else
    echo "$HOME"
  fi
}

user_confirm() {
  local prompt="$1"
  read -rp "$(echo -e "${RP_GOLD}${prompt} (y/N): ${RP_NC}")" reply
  [[ ! "$reply" =~ ^[Yy]$ ]] && log "ERROR" "Aborted by user."
}

install_packages() {
  local packages=("$@")
  log "INFO" "Installing packages: ${packages[*]}..."
  apt update >>"$LOG_FILE" 2>&1 || log "ERROR" "apt update failed"
  apt install -y "${packages[@]}" >>"$LOG_FILE" 2>&1 || log "ERROR" "Package install failed. See $LOG_FILE"
}

find_library() {
  find /usr/lib* -name "$1" 2>/dev/null | head -n1
}

# --- Firefox Functions ---
find_firefox_profile_dir() {
  local user_home=$(get_user_home)
  find "$user_home/.mozilla/firefox" -maxdepth 2 -name "*.default*" -type d 2>/dev/null | head -n1
}

setup_firefox() {
  log "INFO" "Setting up Firefox..."
  local ff_dir=$(find_firefox_profile_dir)

  if [ -z "$ff_dir" ]; then
    log "WARN" "No Firefox profile found."
    user_confirm "Continue without Firefox support?"
    ENABLE_FIREFOX=false
    return
  fi

  FF_DIR="$ff_dir" # Set the global variable

  # Only change ownership if the directory exists and we're running as root
  if [ -d "$FF_DIR" ] && [ "$(id -u)" = "0" ]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$FF_DIR"
  fi
}

# --- Chrome Functions ---
setup_chrome() {
  log "INFO" "Setting up Chrome..."
  local user_home=$(get_user_home)
  CHROME_DIR="$user_home/.pki/nssdb"

  if ! mkdir -p "$CHROME_DIR"; then
    log "WARN" "Failed to create Chrome NSS DB dir."
    user_confirm "Continue without Chrome support?"
    ENABLE_CHROME=false
    return
  fi

  # Only change ownership if the directory exists and we're running as root
  if [ -d "$CHROME_DIR" ] && [ "$(id -u)" = "0" ]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$CHROME_DIR"
  fi
}

# --- OpenSC Functions ---
check_and_install_opensc() {
  log "INFO" "Checking OpenSC..."
  OPENSC_LIB=$(find_library opensc-pkcs11.so)

  if [ -z "$OPENSC_LIB" ] || [ ! -f "$OPENSC_LIB" ]; then
    log "WARN" "OpenSC PKCS#11 library not found. Attempting to install..."
    if ! dpkg -s opensc >/dev/null 2>&1; then
      install_packages opensc opensc-pkcs11
    else
      log "INFO" "OpenSC already installed, checking for opensc-pkcs11..."
      install_packages opensc-pkcs11
    fi
    OPENSC_LIB=$(find_library opensc-pkcs11.so)
    if [ -z "$OPENSC_LIB" ] || [ ! -f "$OPENSC_LIB" ]; then
      log "ERROR" "OpenSC PKCS#11 library still not found after installation."
    fi
  fi

  pkcs11_check_result=$(pkcs11-tool --module "$OPENSC_LIB" --list-slots 2>&1)
  if [ $? -ne 0 ]; then
    log "WARN" "OpenSC detected but no slots available.  Ensure your CAC reader is connected, your CAC is inserted, and pcscd is running.  You may need to restart pcscd."
  else
    log "DEBUG" "pkcs11-tool output: $pkcs11_check_result"
  fi

  log "DEBUG" "OpenSC library: $OPENSC_LIB"
}

# --- NSS Database Functions ---
configure_nss_database() {
  local dir="$1"

  log "INFO" "Configuring NSS database for $dir..."

  log "INFO" "Cleaning existing NSS database for $dir..."
  rm -f "$dir"/{cert9.db,key4.db,pkcs11.txt}

  log "INFO" "Initializing NSS database for $dir..."
  certutil -d sql:"$dir" -N --empty-password >>"$LOG_FILE" 2>&1 || { log "ERROR" "Failed to initialize NSS database for $dir."; return 1; }

  log "INFO" "Adding PKCS#11 module for $dir..."
  modutil -dbdir sql:"$dir" -add "OpenSC-PKCS11" -libfile "$OPENSC_LIB" -force >>"$LOG_FILE" 2>&1 || { log "ERROR" "Failed to add PKCS#11 module for $dir"; return 1; }
  log "DEBUG" "modutil output for $dir: $(modutil -dbdir sql:"$dir" -list | grep -i OpenSC || echo 'No OpenSC module found')"

  return 0 # Success
}

import_dod_certs() {
  local dir="$1"

  log "INFO" "Importing DoD certificates for $dir..."

  for cert in /tmp/AllCerts/*.cer; do
    if [ -f "$cert" ]; then
      local cert_name="$(basename "$cert")"
      certutil -d sql:"$dir" -A -t "CT,," -n "$cert_name" -i "$cert" >>"$LOG_FILE" 2>&1 || { log "ERROR" "Failed to import certificate: $cert_name in $dir"; return 1; }
      log "DEBUG" "Imported certificate: $cert_name in $dir"
    fi
  done

  # Check if the certificates exist before trying to set trust
  for cert in "DoDRoot3.cer" "DoDRoot4.cer" "DoDRoot5.cer" "DoDRoot6.cer"; do
    if certutil -d sql:"$dir" -L | grep -q "$cert"; then
      certutil -d sql:"$dir" -M -t "CT,C,C" -n "$cert" >>"$LOG_FILE" 2>&1 || { log "ERROR" "Failed to set trust for $cert in $dir"; return 1; }
      log "DEBUG" "Set trust for $cert in $dir"
    else
      log "WARN" "Certificate $cert not found in $dir"
    fi
  done

  return 0 # Success
}

set_nss_permissions() {
  local dir="$1"

  log "INFO" "Setting permissions for $dir..."

  # Only set permissions if the directory exists
  if [ -d "$dir" ]; then
    chown "$SUDO_USER":"$SUDO_USER" "$dir"/{cert9.db,key4.db,pkcs11.txt} 2>/dev/null
    chmod 600 "$dir"/{cert9.db,key4.db,pkcs11.txt} 2>/dev/null
  fi
}

verify_nss_setup() {
  local dir="$1"

  log "INFO" "Verifying NSS database setup for $dir..."

  [ -f "$dir/cert9.db" ] || { log "ERROR" "$dir/cert9.db not created."; return 1; }
  log "DEBUG" "NSS files for $dir: $(ls -l "$dir"/{cert9.db,pkcs11.txt} 2>/dev/null || echo 'Files missing')"
  log "DEBUG" "Certs for $dir: $(certutil -d sql:"$dir" -L | grep -E 'DoDRoot[3-6]' || echo 'No DoD certs found')"
  log "DEBUG" "PKCS#11 module for $dir: $(certutil -d sql:"$dir" -U | grep -i OpenSC || echo 'No PKCS#11 module found')"

  return 0 # Success
}

process_nss_database() {
  local dir="$1"

  if configure_nss_database "$dir"; then
    if import_dod_certs "$dir"; then
      set_nss_permissions "$dir"
      verify_nss_setup "$dir"
    else
      log "ERROR" "Failed to import DoD certificates for $dir"
      return 1
    fi
  else
    log "ERROR" "Failed to configure NSS database for $dir"
    return 1
  fi

  return 0 # Success
}

# --- DoD Certificate Functions ---
download_dod_certs() {
  log "INFO" "Downloading DoD certs..."
  wget -qP /tmp "https://militarycac.com/maccerts/AllCerts.zip" >>"$LOG_FILE" 2>&1 || log "ERROR" "Failed to download AllCerts.zip"
  unzip -q /tmp/AllCerts.zip -d /tmp/AllCerts >>"$LOG_FILE" 2>&1 || log "ERROR" "Failed to unzip AllCerts.zip"
  [ -z "$(ls /tmp/AllCerts/*.cer 2>/dev/null)" ] && log "ERROR" "No .cer files found."
}

# --- pcscd Functions ---
start_pcscd() {
  log "INFO" "pcscd should automatically start when needed."
}

# --- Cleanup Functions ---
cleanup() {
  log "INFO" "Cleaning up..."
  rm -rf /tmp/AllCerts.zip /tmp/AllCerts
}

# --- Main Script ---

require_root

# Setup directories
setup_firefox
setup_chrome

# Check and install OpenSC
check_and_install_opensc

# Install core packages
install_packages pcscd libnss3-tools unzip wget

# Download DoD certificates
download_dod_certs

# Process NSS databases
if [ "$ENABLE_FIREFOX" = true ] && [ -n "$FF_DIR" ]; then
  process_nss_database "$FF_DIR" || log "ERROR" "Failed to process Firefox NSS database"
fi

if [ "$ENABLE_CHROME" = true ] && [ -n "$CHROME_DIR" ]; then
  process_nss_database "$CHROME_DIR" || log "ERROR" "Failed to process Chrome NSS database"
fi

# Start pcscd (if necessary)
start_pcscd

# Cleanup
cleanup

# Print instructions
print_instructions

exit 0
