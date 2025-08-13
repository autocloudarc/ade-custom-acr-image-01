#!/bin/bash

# Azure Deployment Environments (ADE) - DEPLOYMENT Script
# This script creates Azure resources using Terraform and integrates with ADE
# It handles authentication, deployment, and output formatting for ADE consumption

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Exit immediately if any command fails (prevents partial deployments)
set -e # exit on error

# Define file paths for Terraform state and configuration
# These paths are provided by the ADE environment
EnvironmentState="$ADE_STORAGE/environment.tfstate"  # Where Terraform tracks deployed resources
EnvironmentPlan="/environment.tfplan"                # Temporary file for the deployment plan
EnvironmentVars="/environment.tfvars.json"          # Variables file with deployment parameters

# Write the operation parameters from ADE to a JSON file that Terraform can read
# This contains user inputs and environment-specific settings
echo "$ADE_OPERATION_PARAMETERS" > $EnvironmentVars

# Configure Terraform to authenticate with Azure using Managed Service Identity (MSI)
# This avoids needing to store credentials in the container - more secure approach
export ARM_USE_MSI=true                    # Tell Terraform to use managed identity
export ARM_CLIENT_ID=$ADE_CLIENT_ID        # Azure service principal client ID
export ARM_TENANT_ID=$ADE_TENANT_ID        # Azure tenant (directory) ID
export ARM_SUBSCRIPTION_ID=$ADE_SUBSCRIPTION_ID  # Azure subscription ID

echo -e "\n>>> Terraform Info...\n"
terraform -version  # Show which version of Terraform is being used for debugging

echo -e "\n>>> Initializing Terraform...\n"
# Download required providers and modules, prepare the working directory
terraform init -no-color

echo -e "\n>>> Creating Terraform Plan...\n"
# Set up environment variables that Terraform configurations can use as input variables
# These are standard ADE variables that most Terraform configs expect
export TF_VAR_resource_group_name=$ADE_RESOURCE_GROUP_NAME     # Target resource group name
export TF_VAR_ade_env_name=$ADE_ENVIRONMENT_NAME               # Environment name
export TF_VAR_env_name=$ADE_ENVIRONMENT_NAME                   # Alternative env name variable
export TF_VAR_ade_subscription=$ADE_SUBSCRIPTION_ID            # Azure subscription ID
export TF_VAR_ade_location=$ADE_ENVIRONMENT_LOCATION           # Azure region (eastus, westus, etc.)
export TF_VAR_ade_environment_type=$ADE_ENVIRONMENT_TYPE       # Environment type (dev/test/prod)

# Create an execution plan showing what resources will be created/modified
# -refresh=true ensures Terraform checks current state of existing resources
# -lock=true prevents concurrent modifications
terraform plan -no-color -compact-warnings -refresh=true -lock=true -state=$EnvironmentState -out=$EnvironmentPlan -var-file="$EnvironmentVars"

echo -e "\n>>> Applying Terraform Plan...\n"
# Execute the plan to actually create/modify the Azure resources
# -auto-approve skips the manual confirmation prompt (safe in automation)
terraform apply -no-color -compact-warnings -auto-approve -lock=true -state=$EnvironmentState $EnvironmentPlan

# === OUTPUT PROCESSING SECTION ===
# ADE needs outputs in a specific format, but Terraform uses different data type names
# This section converts between the two formats so ADE can consume the results

# Outputs must be written to a specific file location.
# ADE expects data types array, boolean, number, object and string.
# Terraform outputs list, bool, number, map, set, string and null
# In addition, Terraform has type constraints, which allow for specifying the types of nested properties.
echo -e "\n>>> Generating outputs for ADE...\n"

# Extract all Terraform outputs in JSON format
tfout="$(terraform output -state=$EnvironmentState -json)"

# Convert Terraform output format to our internal format.
# This complex jq command walks through the JSON and converts data type names:
# - bool → boolean (ADE naming convention)
# - list → array (ADE naming convention)
# - map → object (ADE naming convention)  
# - set → array (sets become arrays in ADE)
# - tuple → array (complex type conversion)
# - nested object types are handled recursively
tfout=$(jq 'walk(if type == "object" then 
            if .type == "bool" then .type = "boolean" 
            elif .type == "list" then .type = "array" 
            elif .type == "map" then .type = "object" 
            elif .type == "set" then .type = "array" 
            elif (.type | type) == "array" then 
                if .type[0] == "tuple" then .type = "array" 
                elif .type[0] == "object" then .type = "object" 
                elif .type[0] == "set" then .type = "array" 
                else . 
                end 
            else . 
            end 
        else . 
        end)' <<< "$tfout")

# Write the converted outputs to the location ADE expects
# ADE will read this file to get deployment results (like resource URLs, names, etc.)
echo "{\"outputs\": $tfout}" > $ADE_OUTPUTS
echo "Outputs successfully generated for ADE"