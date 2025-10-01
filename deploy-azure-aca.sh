#!/bin/bash
# Deploy GPU LangChain4j Demo to Azure Container Apps with GPU workload profile

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-gpu-demo-rg}"
LOCATION="${LOCATION:-australiaeast}"
ACR_NAME="${ACR_NAME:-gpudemoregistry}"
CONTAINER_APP_ENV="${CONTAINER_APP_ENV:-gpu-demo-env}"
CONTAINER_APP_NAME="${CONTAINER_APP_NAME:-gpu-langchain4j-demo}"
IMAGE_NAME="${IMAGE_NAME:-gpu-langchain4j-demo}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
GPU_PROFILE="${GPU_PROFILE:-NC8as_T4_v3}"  # Options: NC8as_T4_v3, NC24ads_A100_v4
WORKLOAD_PROFILE_NAME="${WORKLOAD_PROFILE_NAME:-gpu-t4}"

echo -e "${BLUE}=========================================="
echo "Azure Container Apps GPU Deployment"
echo -e "==========================================${NC}"
echo ""
echo "Configuration:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  ACR Name: $ACR_NAME"
echo "  Environment: $CONTAINER_APP_ENV"
echo "  App Name: $CONTAINER_APP_NAME"
echo "  GPU Profile: $GPU_PROFILE"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}ERROR: Azure CLI is not installed${NC}"
    echo "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
echo -e "${YELLOW}Checking Azure login status...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Not logged in. Please login to Azure...${NC}"
    az login
fi

SUBSCRIPTION=$(az account show --query name -o tsv)
echo -e "${GREEN}✓ Logged in to subscription: $SUBSCRIPTION${NC}"
echo ""

# Step 1: Create Resource Group
echo -e "${YELLOW}Step 1: Creating resource group...${NC}"
if az group show --name $RESOURCE_GROUP &> /dev/null; then
    echo -e "${GREEN}✓ Resource group $RESOURCE_GROUP already exists${NC}"
else
    az group create --name $RESOURCE_GROUP --location $LOCATION
    echo -e "${GREEN}✓ Created resource group $RESOURCE_GROUP${NC}"
fi
echo ""

# Step 2: Create Azure Container Registry
echo -e "${YELLOW}Step 2: Creating Azure Container Registry...${NC}"
if az acr show --name $ACR_NAME &> /dev/null; then
    echo -e "${GREEN}✓ ACR $ACR_NAME already exists${NC}"
else
    echo "Creating ACR (this may take a few minutes)..."
    az acr create \
        --resource-group $RESOURCE_GROUP \
        --name $ACR_NAME \
        --sku Premium \
        --admin-enabled true \
        --location $LOCATION
    echo -e "${GREEN}✓ Created ACR $ACR_NAME${NC}"
fi
echo ""

# Step 3: Build and Push Docker Image
echo -e "${YELLOW}Step 3: Building and pushing Docker image...${NC}"
echo "This will take several minutes (~5-10 min) as it downloads cuDNN 8..."
echo ""

# Login to ACR
az acr login --name $ACR_NAME

# Build and push image
FULL_IMAGE_NAME="$ACR_NAME.azurecr.io/$IMAGE_NAME:$IMAGE_TAG"

if command -v docker buildx &> /dev/null; then
    echo "Using docker buildx for multi-platform build..."
    docker buildx build \
        --platform linux/amd64 \
        -t $FULL_IMAGE_NAME \
        --push \
        .
else
    echo "Using standard docker build..."
    docker build -t $FULL_IMAGE_NAME .
    docker push $FULL_IMAGE_NAME
fi

echo -e "${GREEN}✓ Image pushed to $FULL_IMAGE_NAME${NC}"
echo ""

# Step 4: Create Container Apps Environment with GPU workload profile
echo -e "${YELLOW}Step 4: Creating Container Apps Environment...${NC}"
if az containerapp env show --name $CONTAINER_APP_ENV --resource-group $RESOURCE_GROUP &> /dev/null; then
    echo -e "${GREEN}✓ Environment $CONTAINER_APP_ENV already exists${NC}"
else
    echo "Creating Container Apps environment (this may take a few minutes)..."
    az containerapp env create \
        --name $CONTAINER_APP_ENV \
        --resource-group $RESOURCE_GROUP \
        --location $LOCATION \
        --enable-workload-profiles
    echo -e "${GREEN}✓ Created environment $CONTAINER_APP_ENV${NC}"
fi
echo ""

# Step 5: Add GPU workload profile to environment
echo -e "${YELLOW}Step 5: Configuring GPU workload profile...${NC}"
echo "GPU Profile: $GPU_PROFILE"
echo "Workload Profile Name: $WORKLOAD_PROFILE_NAME"

# Check if profile exists
if az containerapp env workload-profile show \
    --name $CONTAINER_APP_ENV \
    --resource-group $RESOURCE_GROUP \
    --workload-profile-name $WORKLOAD_PROFILE_NAME &> /dev/null; then
    echo -e "${YELLOW}Workload profile $WORKLOAD_PROFILE_NAME already exists, updating...${NC}"
fi

az containerapp env workload-profile set \
    --name $CONTAINER_APP_ENV \
    --resource-group $RESOURCE_GROUP \
    --workload-profile-name $WORKLOAD_PROFILE_NAME \
    --workload-profile-type $GPU_PROFILE \
    --min-nodes 0 \
    --max-nodes 3

echo -e "${GREEN}✓ GPU workload profile configured${NC}"
echo ""

# Step 6: Get ACR credentials
echo -e "${YELLOW}Step 6: Getting ACR credentials...${NC}"
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv)
echo -e "${GREEN}✓ Retrieved ACR credentials${NC}"
echo ""

# Step 7: Deploy Container App
echo -e "${YELLOW}Step 7: Deploying Container App...${NC}"
echo "This will take a few minutes..."
echo ""

# Set Java memory based on GPU profile
if [[ "$GPU_PROFILE" == "NC24ads_A100_v4" ]]; then
    JAVA_MEMORY="32g"
    CPU_CORES="12"
    MEMORY_SIZE="80Gi"
elif [[ "$GPU_PROFILE" == "NC8as_T4_v3" ]]; then
    JAVA_MEMORY="12g"
    CPU_CORES="4"
    MEMORY_SIZE="16Gi"
else
    JAVA_MEMORY="12g"
    CPU_CORES="4"
    MEMORY_SIZE="16Gi"
fi

# Check if app exists
if az containerapp show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP &> /dev/null; then
    echo -e "${YELLOW}Container app exists, updating...${NC}"
    az containerapp update \
        --name $CONTAINER_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --image $FULL_IMAGE_NAME \
        --set-env-vars \
            JAVA_OPTS="-Xmx${JAVA_MEMORY} -XX:+UseZGC -XX:+ZGenerational --enable-preview" \
            SPRING_PROFILES_ACTIVE="production" \
            GPU_LANGCHAIN4J_GPU_ENABLED="true" \
            GPU_LANGCHAIN4J_GPU_DEVICE_ID="0"
else
    echo -e "${YELLOW}Creating new container app...${NC}"
    az containerapp create \
        --name $CONTAINER_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --environment $CONTAINER_APP_ENV \
        --image $FULL_IMAGE_NAME \
        --registry-server "$ACR_NAME.azurecr.io" \
        --registry-username $ACR_USERNAME \
        --registry-password $ACR_PASSWORD \
        --target-port 8080 \
        --ingress external \
        --cpu $CPU_CORES \
        --memory $MEMORY_SIZE \
        --workload-profile-name $WORKLOAD_PROFILE_NAME \
        --min-replicas 0 \
        --max-replicas 3 \
        --env-vars \
            JAVA_OPTS="-Xmx${JAVA_MEMORY} -XX:+UseZGC -XX:+ZGenerational --enable-preview" \
            SPRING_PROFILES_ACTIVE="production" \
            GPU_LANGCHAIN4J_GPU_ENABLED="true" \
            GPU_LANGCHAIN4J_GPU_DEVICE_ID="0"
fi

echo -e "${GREEN}✓ Container app deployed successfully${NC}"
echo ""

# Step 8: Get application URL
echo -e "${YELLOW}Step 8: Retrieving application URL...${NC}"
APP_URL=$(az containerapp show \
    --name $CONTAINER_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query properties.configuration.ingress.fqdn -o tsv)

echo ""
echo -e "${GREEN}=========================================="
echo "🎉 Deployment Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Application URL: https://$APP_URL"
echo "Test endpoint: https://$APP_URL/actuator/health"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Wait 2-3 minutes for app to start (cold start with model loading)"
echo "2. Check health: curl https://$APP_URL/actuator/health"
echo "3. Open in browser: https://$APP_URL"
echo "4. Generate test image:"
echo "   curl -X POST https://$APP_URL/api/langchain4j/image \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"prompt\": \"sunset over mountains\", \"style\": \"CLASSIC\"}' \\"
echo "     --output test.png"
echo ""
echo -e "${BLUE}Monitor:${NC}"
echo "  Logs: az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow"
echo "  Metrics: az monitor metrics list --resource \$(az containerapp show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)"
echo ""
echo -e "${BLUE}Cost Optimization:${NC}"
echo "  - Set min-replicas=0 for scale-to-zero (no cost when idle)"
echo "  - Use T4 GPU (\$0.526/hour) for dev/test"
echo "  - Use A100 GPU (\$3.672/hour) for production"
echo ""
echo -e "${YELLOW}Note: First request may take 60-90 seconds due to cold start${NC}"
echo ""
