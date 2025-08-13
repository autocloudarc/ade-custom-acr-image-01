#!/bin/bash

# Azure Deployment Environments (ADE) - DELETE/DESTROY Script
# This script safely removes all Azure resources that were created by the deployment
# It uses Terraform's destroy functionality to clean up infrastructure

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Exit immediately if any command fails (prevents partial cleanup)
set -e # exit on error

# Define file paths for Terraform state and configuration
# These paths are provided by the ADE environment
EnvironmentState="$ADE_STORAGE/environment.tfstate"  # Where Terraform tracks what resources exist
EnvironmentPlan="/environment.tfplan"                # Temporary file for the destruction plan
EnvironmentVars="/environment.tfvars.json"          # Variables file with deployment parameters

# Write the operation parameters to a JSON file that Terraform can read
echo "$ADE_OPERATION_PARAMETERS" > $EnvironmentVars

# Configure Terraform to authenticate with Azure using Managed Service Identity (MSI)
# This avoids needing to store credentials in the container
export ARM_USE_MSI=true                    # Tell Terraform to use managed identity
export ARM_CLIENT_ID=$ADE_CLIENT_ID        # Azure service principal client ID
export ARM_TENANT_ID=$ADE_TENANT_ID        # Azure tenant (directory) ID
export ARM_SUBSCRIPTION_ID=$ADE_SUBSCRIPTION_ID  # Azure subscription ID

# Safety check: if no state file exists, there's nothing to delete
if ! test -f $EnvironmentState; then
    echo "No state file present. Delete succeeded."
    exit 0  # Exit successfully since there's nothing to clean up
fi

# Begin the Terraform destruction process
echo -e "\n>>> Terraform...\n"
echo -e "\n>>> Terraform Info...\n"
terraform -version  # Show which version of Terraform is being used

echo -e "\n>>> Initializing Terraform...\n"
# Download providers and prepare Terraform working directory
terraform init -no-color

echo -e "\n>>> Creating Terraform Plan...\n"
# Set up environment variables that Terraform can use as input variables
export TF_VAR_resource_group_name=$ADE_RESOURCE_GROUP_NAME     # Target resource group
export TF_VAR_ade_env_name=$ADE_ENVIRONMENT_NAME               # Environment name
export TF_VAR_env_name=$ADE_ENVIRONMENT_NAME                   # Alternative env name variable
export TF_VAR_ade_subscription=$ADE_SUBSCRIPTION_ID            # Azure subscription
export TF_VAR_ade_location=$ADE_ENVIRONMENT_LOCATION           # Azure region
export TF_VAR_ade_environment_type=$ADE_ENVIRONMENT_TYPE       # Environment type (dev/test/prod)

# Create a destruction plan showing what resources will be deleted
# -destroy flag tells Terraform to plan resource removal instead of creation
terraform plan -no-color -compact-warnings -destroy -refresh=true -lock=true -state=$EnvironmentState -out=$EnvironmentPlan -var-file="$EnvironmentVars"

echo -e "\n>>> Applying Terraform Plan...\n"
# Execute the destruction plan to actually delete the Azure resources
# -auto-approve skips the manual confirmation prompt
terraform apply -no-color -compact-warnings -auto-approve -lock=true -state=$EnvironmentState $EnvironmentPlan
