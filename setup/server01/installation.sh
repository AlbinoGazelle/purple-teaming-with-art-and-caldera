#!/bin/bash
set -euo pipefail

# ANSI color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Function to display colored messages
log_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to display error messages and exit
error_exit() {
    log_message "$RED" "ERROR: $1" >&2
    exit 1
}

# Function to run command with error checking
run_command() {
    local cmd="$1"
    local error_message="$2"
    
    log_message "$YELLOW" "Executing: $cmd"
    if ! eval "$cmd"; then
        error_exit "$error_message"
    fi
}

# Function to run command as the original user
run_as_user() {
    local cmd="$1"
    local error_message="$2"
    
    log_message "$YELLOW" "Executing as user: $cmd"
    if ! sudo -u "$SUDO_USER" bash -c "$cmd"; then
        error_exit "$error_message"
    fi
}



# Check for sudo privileges
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run with sudo privileges.\nPlease run the script as: sudo $0"
fi

# Download prerequisites
log_message "$BLUE" "Download & Installing Caldera Prerequisites"
run_command "sudo apt install -y python3-pip" "Failed to install pip3, do we have internet?"
run_command "sudo apt install -y nodejs" "Failed to install nodejs, do we have internet?"
run_command "sudo apt install -y npm" "Failed to install npm, do we have internet?"

# Download and install MITRE Caldera
log_message "$BLUE" "Download & Installing MITRE Caldera"
run_as_user "cd ~;git clone https://github.com/mitre/caldera.git --recursive" "Failed to download Caldera Git repository. Do we have internet?"
run_as_user "pip3 install -r caldera/requirements.txt" "Failed to install Caldera requirements. Do we have pip3 installed?"
run_as_user "cd caldera;python3 server.py --build" "Failed to start Caldera. Investigate any error messages produced by the Caldera server."
