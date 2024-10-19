#!/bin/bash

# Script to onboard an Azure Arc-enabled server

# Check for sudo privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run with sudo privileges." >&2
    echo "Please run the script as: sudo $0 [options]" >&2
    exit 1
fi


# Function to display usage information
usage() {
    echo "Usage: $0 -i <ServicePrincipalId> -s <ServicePrincipalClientSecret>"
    echo "  -i : Service Principal ID"
    echo "  -s : Service Principal Client Secret"
    exit 1
}

# Parse command line options
while getopts ":i:s:" opt; do
    case $opt in
        i) ServicePrincipalId="$OPTARG"
        ;;
        s) ServicePrincipalClientSecret="$OPTARG"
        ;;
        \?) echo "Invalid option -$OPTARG" >&2
            usage
        ;;
    esac
done

# Check if required arguments are provided
if [ -z "$ServicePrincipalId" ] || [ -z "$ServicePrincipalClientSecret" ]; then
    echo "Error: Both Service Principal ID and Secret are required."
    usage
fi

# TODO: All of this needs to be changed over for DEATHCon environment
export subscriptionId="b356e47c-f75a-4e14-ade0-b7d909a483ac"
export resourceGroup="deathcon-demo-rg"
export tenantId="03ec6af4-ef0c-43a9-8b0e-54d1ea670e48"
export location="westus2"
export authType="principal"
export correlationId="c1eb1baa-082c-4115-9bcd-ed7e32ce107d"
export cloud="AzureCloud"

# Download the installation package
echo "Downloading Azure Connected Machine agent..."
output=$(wget https://gbl.his.arc.azure.com/azcmagent-linux -O /tmp/install_linux_azcmagent.sh 2>&1)
if [ $? != 0 ]; then 
    wget -qO- --method=PUT --body-data="{\"subscriptionId\":\"$subscriptionId\",\"resourceGroup\":\"$resourceGroup\",\"tenantId\":\"$tenantId\",\"location\":\"$location\",\"correlationId\":\"$correlationId\",\"authType\":\"$authType\",\"operation\":\"onboarding\",\"messageType\":\"DownloadScriptFailed\",\"message\":\"$output\"}" "https://gbl.his.arc.azure.com/log" &> /dev/null || true
    echo "Failed to download installation script. Error: $output"
    exit 1
fi
echo "Download completed successfully."

# Install the hybrid agent
echo "Installing Azure Connected Machine agent..."
bash /tmp/install_linux_azcmagent.sh
if [ $? != 0 ]; then
    echo "Failed to install the Azure Connected Machine agent"
    exit 1
fi
echo "Installation completed successfully."

# Run connect command
echo "Connecting to Azure Arc..."
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
    echo "Failed to connect to Azure Arc"
    exit 1
fi

echo "Successfully connected to Azure Arc"

# TODO: Add Azure Monitor Agent installation here if needed

echo "Script completed successfully"