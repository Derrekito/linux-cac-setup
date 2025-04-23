# CAC Setup Scripts for Linux (Pop!_OS & Arch)

This repository contains automated Bash scripts to configure Common Access Card (CAC) support on **Pop!_OS** and **Arch Linux** systems using OpenSC and the DoD certificate bundle. The scripts are styled with [Rosé Pine Moon](https://rosepinetheme.com/) ANSI colors for consistent terminal aesthetics.

## Features

- Installs required middleware: `opensc`, `pcscd`, `ccid`, `nss`, and related tools.
- Initializes NSS databases for Firefox and Chrome/Chromium.
- Downloads and imports DoD root and intermediate certificates.
- Adds the OpenSC PKCS#11 module to the browser certificate store.
- Logs key setup steps and errors with color-coded messages.

## Included Scripts

- `PopOS_cac_setup.sh` – tailored for Debian-based Pop!_OS systems
- `Arch_cac_setup.sh` – tailored for Arch Linux systems using `pacman`

## Prerequisites

- A CAC reader (e.g., SCM SCR3500)
- Administrative privileges (`sudo`)
- Firefox and/or Chrome/Chromium installed

## Usage

### Pop!_OS

```bash
sudo ./PopOS_cac_setup.sh
Arch Linux
bash
Copy
Edit
sudo ./Arch_cac_setup.sh
```

⚠️ You may be prompted to confirm continuation if Firefox/Chrome profiles aren't found.

## Verification

After running the script:

1. Insert your CAC and open Firefox or Chrome.
2. Navigate to:
   - **Firefox**: `Preferences > Privacy & Security > Security Devices`
   - **Chrome**: `Settings > Privacy and Security > Manage Certificates`
3. Confirm that `OpenSC-PKCS11` is listed.
4. Test in terminal with:

   ```bash
   pkcs11-tool --module /usr/lib/opensc-pkcs11.so --list-objects
   ```


# Disclaimer
This script is provided as-is with no guarantee. Use at your own risk and validate security compliance per your organization's policy.

