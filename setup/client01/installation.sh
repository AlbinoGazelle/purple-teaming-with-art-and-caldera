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

# Function to display usage information
usage() {
    echo "Usage: $0 [-i <ServicePrincipalId>] [-s <ServicePrincipalClientSecret>]"
    echo "  -i : Service Principal ID (required for Azure Arc onboarding)"
    echo "  -s : Service Principal Client Secret (required for Azure Arc onboarding)"
    echo "  -h : Display this help message"
    exit 1
}

# Parse command line options
while getopts ":i:s:h" opt; do
    case $opt in
        i) ServicePrincipalId="$OPTARG"
        ;;
        s) ServicePrincipalClientSecret="$OPTARG"
        ;;
        h) usage
        ;;
        \?) echo "Invalid option -$OPTARG" >&2
            usage
        ;;
    esac
done

# Check for sudo privileges
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run with sudo privileges.\nPlease run the script as: sudo $0 [options]"
fi

# Install PowerShell prerequisites
log_message "$BLUE" "Installing PowerShell prerequisites..."
run_command "apt-get install -y wget apt-transport-https software-properties-common" "Failed to install PowerShell prerequisites"

# Download and install PowerShell
log_message "$BLUE" "Downloading and installing PowerShell..."
run_command "wget -q https://github.com/PowerShell/PowerShell/releases/download/v7.4.5/powershell_7.4.5-1.deb_amd64.deb" "Failed to download PowerShell package"
run_command "dpkg -i powershell_7.4.5-1.deb_amd64.deb" "Failed to install PowerShell package"
run_command "rm powershell_7.4.5-1.deb_amd64.deb" "Failed to remove PowerShell package file"
run_command "apt-get update" "Failed to update package list after PowerShell installation"
run_command "apt-get install -y powershell" "Failed to install PowerShell"

# Download and install Sysmon
log_message "$BLUE" "Downloading and installing Sysmon"
run_command "wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb" "Failed to download Microsoft packages. Do we have internet?"
run_command "dpkg -i packages-microsoft-prod.deb" "Failed to install Microsoft package"
run_command "apt-get update" "Failed to update packages after adding Microsoft"
run_command "apt-get install -y sysinternalsebpf" "Failed to install eBPF"
run_command "apt-get install -y sysmonforlinux" "Failed to install SysmonForLinux"

# Move syslog configuration file
# TODO: Fix this... not sure why bash is saying the file doesn't exist. Use Claude.
log_message "$BLUE" "Configuring rsyslog to only log Process Creation events"
run_as_user "cp ~/purple-teaming-with-art-and-caldera/setup/client01/01-sysmon.conf /tmp" "Failed to copy rsyslog configuration file"
run_command "cp /tmp/01-sysmon.conf /etc/rsyslog.d/" "Failed to copy rsyslog file from temp directory"
run_command "systemctl restart rsyslog.service" "Failed to start syslog service"

# Configure Sysmon
# TODO: Fix this.. same as syslog config file. How do we move this as a different user when we don't know their usernames?
log_message "$BLUE" "Configuring Sysmon"
run_as_user "cp ~/purple-teaming-with-art-and-caldera/setup/client01/sysmon_config.xml /tmp" "Failed to copy sysmon configuration file"
run_command "sysmon -i /tmp/sysmon_config.xml" "Failed to install sysmon configuration file"

# Azure Arc onboarding (if Service Principal ID and Secret are provided)
if [ -n "${ServicePrincipalId:-}" ] && [ -n "${ServicePrincipalClientSecret:-}" ]; then
    log_message "$BLUE" "Starting Azure Arc onboarding process..."

    # Azure Arc-specific variables
    export subscriptionId="9c55f9eb-176b-4155-b215-576517da817f"
    export resourceGroup="art-caledera-rg"
    export tenantId="a19a46fd-8dd6-4a6c-972a-f0edb1f5a9a7"
    export location="eastus"
    export authType="principal"
    export correlationId="c1eb1baa-082c-4115-9bcd-ed7e32ce107d"
    export cloud="AzureCloud"

    # Download the installation package
    log_message "$BLUE" "Downloading Azure Connected Machine agent..."
    output=$(wget https://gbl.his.arc.azure.com/azcmagent-linux -O /tmp/install_linux_azcmagent.sh 2>&1)
    if [ $? != 0 ]; then 
        wget -qO- --method=PUT --body-data="{\"subscriptionId\":\"$subscriptionId\",\"resourceGroup\":\"$resourceGroup\",\"tenantId\":\"$tenantId\",\"location\":\"$location\",\"correlationId\":\"$correlationId\",\"authType\":\"$authType\",\"operation\":\"onboarding\",\"messageType\":\"DownloadScriptFailed\",\"message\":\"$output\"}" "https://gbl.his.arc.azure.com/log" &> /dev/null || true
        error_exit "Failed to download installation script. Error: $output"
    fi
    log_message "$GREEN" "Download completed successfully."

    # Install the hybrid agent
    log_message "$BLUE" "Installing Azure Connected Machine agent..."
    bash /tmp/install_linux_azcmagent.sh
    if [ $? != 0 ]; then
        error_exit "Failed to install the Azure Connected Machine agent"
    fi
    log_message "$GREEN" "Installation completed successfully."

    # Run connect command
    log_message "$BLUE" "Connecting to Azure Arc..."
    sudo azcmagent connect \
        --service-principal-id "$ServicePrincipalId" \
        --service-principal-secret "$ServicePrincipalClientSecret" \
        --resource-group "$resourceGroup" \
        --tenant-id "$tenantId" \
        --location "$location" \
        --subscription-id "$subscriptionId" \
        --cloud "$cloud" \
        --tags "deathcon-caldera-onboard=true,ArcSQLServerExtensionDeployment=Disabled" \
        --correlation-id "$correlationId"

    if [ $? != 0 ]; then
        error_exit "Failed to connect to Azure Arc"
    fi

    log_message "$GREEN" "Successfully connected to Azure Arc"

    # TODO: Add Azure Monitor Agent installation here if needed
else
    log_message "$YELLOW" "Azure Arc onboarding skipped. To onboard, provide Service Principal ID and Secret using -i and -s options."
fi

log_message "$GREEN" "Script completed successfully"
log_message "$YELLOW" "Dropping you into a PowerShell prompt to install Invoke-AtomicRedTeam. To exit PowerShell and return to bash, type 'exit'."

# Drop into PowerShell prompt as the original user
sudo -u "$SUDO_USER" pwsh