#!/bin/bash

###############################################################################
# Azure Container Apps Deployment Script
# Deploys GPU LangChain4j Demo to Azure Container Apps with GPU support
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# Configuration - Customize these values
###############################################################################

# Azure Configuration
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-bbenz-gpu-langchain4j-rg}"
LOCATION="${LOCATION:-australiaeast}"

# Container Registry
ACR_NAME="${ACR_NAME:-bbenz-gpulangchain4jacr}"
IMAGE_NAME="gpu-langchain4j-demo"
IMAGE_TAG="${IMAGE_TAG:-australiaeast}"

# Container Apps
ACA_ENVIRONMENT="${ACA_ENVIRONMENT:-bbenzgpu-langchain4j-env}"
ACA_APP_NAME="${ACA_APP_NAME:-bbenz-gpu-langchain4j-app}"

# GPU Configuration
GPU_TYPE="${GPU_TYPE:-T4}"  # Options: T4, A100

# Application Configuration
MODEL_DIR="/app/models"
JAVA_OPTS="-Xmx8g -XX:+UseZGC -XX:+ZGenerational"

###############################################################################
# Helper Functions
###############################################################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

check_az_cli() {
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI not found. Please install it first."
        echo "Visit: https://docs.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    fi
    print_success "Azure CLI found"
}

check_login() {
    print_info "Checking Azure login status..."
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    print_success "Logged in to Azure"
}

select_subscription() {
    if [ -z "$SUBSCRIPTION_ID" ]; then
        print_info "No subscription specified. Using current subscription."
        SUBSCRIPTION_ID=$(az account show --query id -o tsv | tr -d '\r')
        SUBSCRIPTION_NAME=$(az account show --query name -o tsv | tr -d '\r')
    else
        print_info "Setting subscription to: $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
        # Get subscription name for display
        SUBSCRIPTION_NAME=$(az account show --query name -o tsv | tr -d '\r')
    fi
    print_success "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
}

###############################################################################
# Deployment Functions
###############################################################################

create_resource_group() {
    print_header "Creating Resource Group"
    
    if az group exists --name "$RESOURCE_GROUP" | grep -q "true"; then
        print_info "Resource group '$RESOURCE_GROUP' already exists"
    else
        print_info "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --output none
        print_success "Resource group created"
    fi
}

create_container_registry() {
    print_header "Creating Azure Container Registry"
    
    if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        print_info "Container registry '$ACR_NAME' already exists"
    else
        print_info "Creating container registry '$ACR_NAME'..."
        az acr create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$ACR_NAME" \
            --sku Premium \
            --location "$LOCATION" \
            --admin-enabled true \
            --output none
        print_success "Container registry created"
    fi
    
    # Get ACR credentials (strip carriage returns from Windows Azure CLI output)
    ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query username -o tsv | tr -d '\r')
    ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv | tr -d '\r')
    ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv | tr -d '\r')
    
    print_success "ACR login server: $ACR_LOGIN_SERVER"
}

build_and_push_image() {
    print_header "Building and Pushing Docker Image"
    
    print_info "Logging in to ACR..."
    echo "$ACR_PASSWORD" | docker login "$ACR_LOGIN_SERVER" -u "$ACR_USERNAME" --password-stdin
    
    FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"
    
    print_info "Building Docker image: $FULL_IMAGE_NAME"
    docker build -t "$FULL_IMAGE_NAME" .
    
    print_info "Pushing image to ACR..."
    docker push "$FULL_IMAGE_NAME"
    
    print_success "Image pushed: $FULL_IMAGE_NAME"
}

create_aca_environment() {
    print_header "Creating Container Apps Environment"
    
    # Ensure Container Apps extension is installed
    print_info "Checking Container Apps extension..."
    az extension add --upgrade --name containerapp --only-show-errors --output none 2>/dev/null || true
    
    if az containerapp env show --name "$ACA_ENVIRONMENT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        print_info "Container Apps environment '$ACA_ENVIRONMENT' already exists"
    else
        print_info "Creating Container Apps environment with GPU support..."
        az containerapp env create \
            --name "$ACA_ENVIRONMENT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --output none
        print_success "Container Apps environment created"
    fi
    
    # Add GPU workload profile
    print_info "Adding GPU workload profile..."
    
    if [ "$GPU_TYPE" == "T4" ]; then
        WORKLOAD_PROFILE_NAME="NC8as-T4"
        WORKLOAD_PROFILE_TYPE="Consumption-GPU-NC8as-T4"
    elif [ "$GPU_TYPE" == "A100" ]; then
        WORKLOAD_PROFILE_NAME="NC24-A100"
        WORKLOAD_PROFILE_TYPE="Consumption-GPU-NC24-A100"
    else
        print_error "Invalid GPU type: $GPU_TYPE. Use T4 or A100."
        exit 1
    fi
    
    # Set GPU workload profile (idempotent operation)
    print_info "Setting GPU workload profile: $WORKLOAD_PROFILE_TYPE..."
    az containerapp env workload-profile set \
        --name "$ACA_ENVIRONMENT" \
        --resource-group "$RESOURCE_GROUP" \
        --workload-profile-name "$WORKLOAD_PROFILE_NAME" \
        --workload-profile-type "$WORKLOAD_PROFILE_TYPE" \
        --output none
    print_success "GPU workload profile configured: $WORKLOAD_PROFILE_TYPE"
}

deploy_container_app() {
    print_header "Deploying Container App"
    
    FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"
    
    print_info "Deploying application: $ACA_APP_NAME"
    
    # Check if app exists
    if az containerapp show --name "$ACA_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        print_info "Updating existing Container App..."
        
        az containerapp update \
            --name "$ACA_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --image "$FULL_IMAGE_NAME" \
            --output none
    else
        print_info "Creating new Container App..."
        
        az containerapp create \
            --name "$ACA_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --environment "$ACA_ENVIRONMENT" \
            --image "$FULL_IMAGE_NAME" \
            --workload-profile-name "$WORKLOAD_PROFILE_NAME" \
            --registry-server "$ACR_LOGIN_SERVER" \
            --registry-username "$ACR_USERNAME" \
            --registry-password "$ACR_PASSWORD" \
            --target-port 8080 \
            --ingress external \
            --cpu 4 \
            --memory 16Gi \
            --min-replicas 1 \
            --max-replicas 3 \
            --env-vars \
                "SPRING_PROFILES_ACTIVE=production" \
                "JAVA_OPTS=$JAVA_OPTS" \
                "GPU_LANGCHAIN4J_MODEL_DIR=$MODEL_DIR" \
                "GPU_LANGCHAIN4J_GPU_ENABLED=true" \
                "GPU_LANGCHAIN4J_GPU_DEVICE_ID=0" \
            --output none
    fi
    
    print_success "Container App deployed"
    
    # Get app URL
    APP_URL=$(az containerapp show \
        --name "$ACA_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.configuration.ingress.fqdn -o tsv | tr -d '\r')
    
    print_success "Application URL: https://$APP_URL"
}

show_logs() {
    print_header "Fetching Application Logs"
    
    print_info "Streaming logs from Container App..."
    echo ""
    
    az containerapp logs show \
        --name "$ACA_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --follow
}

###############################################################################
# Main Deployment
###############################################################################

main() {
    print_header "Azure Container Apps GPU Deployment"
    
    # Pre-flight checks
    check_az_cli
    check_login
    select_subscription
    
    # Display configuration
    echo ""
    print_info "Deployment Configuration:"
    echo "  Resource Group:        $RESOURCE_GROUP"
    echo "  Location:              $LOCATION"
    echo "  ACR Name:              $ACR_NAME"
    echo "  Image:                 $IMAGE_NAME:$IMAGE_TAG"
    echo "  Environment:           $ACA_ENVIRONMENT"
    echo "  App Name:              $ACA_APP_NAME"
    echo "  GPU Type:              $GPU_TYPE"
    echo ""
    
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Execute deployment steps
    create_resource_group
    create_container_registry
    build_and_push_image
    create_aca_environment
    deploy_container_app
    
    # Summary
    print_header "Deployment Complete!"
    echo ""
    print_success "Your GPU-accelerated LangChain4j application is now deployed!"
    echo ""
    echo "Application URL: https://$APP_URL"
    echo ""
    print_info "To view logs, run:"
    echo "  ./deploy-aca.sh --logs"
    echo ""
    print_info "To delete all resources, run:"
    echo "  az group delete --name $RESOURCE_GROUP"
    echo ""
}

# Command-line options
case "${1:-}" in
    --logs)
        check_az_cli
        check_login
        show_logs
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Deploy GPU LangChain4j Demo to Azure Container Apps"
        echo ""
        echo "Options:"
        echo "  --logs          Show application logs"
        echo "  --help, -h      Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  AZURE_SUBSCRIPTION_ID    Azure subscription ID"
        echo "  RESOURCE_GROUP           Resource group name (default: gpu-langchain4j-rg)"
        echo "  LOCATION                 Azure region (default: eastus)"
        echo "  ACR_NAME                 Container registry name (default: gpulangchain4jacr)"
        echo "  IMAGE_TAG                Docker image tag (default: latest)"
        echo "  GPU_TYPE                 GPU type: T4 or A100 (default: T4)"
        echo ""
        exit 0
        ;;
    *)
        main
        ;;
esac
