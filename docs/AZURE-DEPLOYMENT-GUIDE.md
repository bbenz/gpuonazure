# Azure Container Apps Deployment Guide

Complete guide for deploying the GPU LangChain4j Demo to Azure Container Apps with GPU acceleration.

---

## Prerequisites

### 1. Azure Subscription
- Active Azure subscription with access to GPU resources
- Sufficient quota for GPU VMs (NC-series)
- Request quota increase if needed: [Azure Portal → Quotas](https://portal.azure.com/#view/Microsoft_Azure_Capacity/QuotaMenuBlade/~/myQuotas)

### 2. Local Development Environment
- **Docker**: For building container images
- **Azure CLI**: Version 2.50.0 or later
  ```bash
  az --version
  # If needed: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  ```
- **Git**: For cloning the repository

### 3. Models Downloaded
Ensure models are in the `models/` directory:
```bash
ls -lh models/
# Should show:
#   stable-diffusion/    (~2.5 GB)
#   all-MiniLM-L6-v2/    (~50 MB)
```

If models are missing, run:
```bash
./download-models.sh
```

---

## Quick Start (Automated Deployment)

### Option 1: Use Deployment Script (Recommended)

```bash
# Set configuration (optional - defaults are provided)
export RESOURCE_GROUP="gpu-demo-rg"
export LOCATION="eastus"
export ACR_NAME="gpudemoregistry"
export CONTAINER_APP_ENV="gpu-demo-env"
export CONTAINER_APP_NAME="gpu-langchain4j-demo"
export GPU_PROFILE="NC8as_T4_v3"  # or NC24ads_A100_v4

# Run deployment
./deploy-azure-aca.sh
```

The script will:
1. ✅ Create resource group
2. ✅ Create Azure Container Registry (Premium tier)
3. ✅ Build and push Docker image (~5GB, takes 5-10 min)
4. ✅ Create Container Apps Environment
5. ✅ Configure GPU workload profile
6. ✅ Deploy container app
7. ✅ Output application URL

**Total time**: 15-20 minutes

---

## Manual Deployment (Step-by-Step)

### Step 1: Login to Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### Step 2: Create Resource Group

```bash
RESOURCE_GROUP="gpu-demo-rg"
LOCATION="eastus"

az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION
```

**Available GPU regions**:
- `eastus` - East US (NC8as_T4_v3, NC24ads_A100_v4)
- `westus2` - West US 2 (NC8as_T4_v3, NC24ads_A100_v4)
- `westeurope` - West Europe (NC8as_T4_v3)
- `japaneast` - Japan East (NC8as_T4_v3)

Check availability: [Azure Products by Region](https://azure.microsoft.com/global-infrastructure/services/?products=container-apps)

### Step 3: Create Azure Container Registry

```bash
ACR_NAME="gpudemoregistry"  # Must be globally unique

az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Premium \
  --admin-enabled true \
  --location $LOCATION
```

**Why Premium SKU?**
- Required for large images (our image is ~5GB)
- Better performance and reliability
- Geo-replication support

### Step 4: Build and Push Docker Image

```bash
# Login to ACR
az acr login --name $ACR_NAME

# Build and push (takes 5-10 minutes)
docker build -t $ACR_NAME.azurecr.io/gpu-langchain4j-demo:latest .
docker push $ACR_NAME.azurecr.io/gpu-langchain4j-demo:latest
```

**Build progress**:
- Stage 1 (Maven build): ~3-5 minutes
- Stage 2 (cuDNN download): ~2-3 minutes
- Stage 2 (Model copy): ~1-2 minutes
- Push to ACR: ~2-3 minutes

### Step 5: Create Container Apps Environment

```bash
CONTAINER_APP_ENV="gpu-demo-env"

az containerapp env create \
  --name $CONTAINER_APP_ENV \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --enable-workload-profiles
```

**Note**: `--enable-workload-profiles` is required for GPU support.

### Step 6: Add GPU Workload Profile

```bash
WORKLOAD_PROFILE_NAME="gpu-t4"
GPU_PROFILE="NC8as_T4_v3"  # Options: NC8as_T4_v3, NC24ads_A100_v4

az containerapp env workload-profile set \
  --name $CONTAINER_APP_ENV \
  --resource-group $RESOURCE_GROUP \
  --workload-profile-name $WORKLOAD_PROFILE_NAME \
  --workload-profile-type $GPU_PROFILE \
  --min-nodes 0 \
  --max-nodes 3
```

**GPU Profile Options**:

| Profile | GPU | vCPU | Memory | Cost/hour* |
|---------|-----|------|--------|-----------|
| NC8as_T4_v3 | NVIDIA T4 (16GB) | 8 | 56GB | $0.526 |
| NC24ads_A100_v4 | NVIDIA A100 (80GB) | 24 | 220GB | $3.672 |

*Pricing as of Oct 2025, subject to change

**Recommendation**: Use T4 for dev/test, A100 for production.

### Step 7: Get ACR Credentials

```bash
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv)
```

### Step 8: Deploy Container App

```bash
CONTAINER_APP_NAME="gpu-langchain4j-demo"

az containerapp create \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment $CONTAINER_APP_ENV \
  --image $ACR_NAME.azurecr.io/gpu-langchain4j-demo:latest \
  --registry-server "$ACR_NAME.azurecr.io" \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --target-port 8080 \
  --ingress external \
  --cpu 4 \
  --memory 16Gi \
  --workload-profile-name $WORKLOAD_PROFILE_NAME \
  --min-replicas 0 \
  --max-replicas 3 \
  --env-vars \
    JAVA_OPTS="-Xmx12g -XX:+UseZGC -XX:+ZGenerational --enable-preview" \
    SPRING_PROFILES_ACTIVE="production" \
    GPU_LANGCHAIN4J_GPU_ENABLED="true" \
    GPU_LANGCHAIN4J_GPU_DEVICE_ID="0"
```

**Configuration notes**:
- `--min-replicas 0`: Scale to zero when idle (cost optimization)
- `--max-replicas 3`: Max concurrent instances
- `--cpu 4 --memory 16Gi`: For T4 GPU (adjust for A100)
- `JAVA_OPTS -Xmx12g`: Leave 4GB for OS and GPU

### Step 9: Get Application URL

```bash
APP_URL=$(az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn -o tsv)

echo "Application URL: https://$APP_URL"
```

---

## Testing Deployment

### 1. Health Check

```bash
curl https://$APP_URL/actuator/health
```

**Expected response**:
```json
{
  "status": "UP",
  "groups": ["liveness", "readiness"]
}
```

**Note**: First request may take 60-90 seconds due to cold start.

### 2. Test Image Generation

```bash
curl -X POST https://$APP_URL/api/langchain4j/image \
  -H "Content-Type: application/json" \
  -d '{"prompt": "mountain sunset", "style": "CLASSIC"}' \
  --output test-azure.png \
  -w "\nHTTP Status: %{http_code}\nTime: %{time_total}s\n"
```

**Expected**:
- HTTP Status: 200
- Time: 60-120 seconds (first request includes model loading)
- Time: 15-60 seconds (subsequent requests)
- File: `test-azure.png` downloaded

### 3. View Application Logs

```bash
az containerapp logs show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --follow
```

**Look for**:
```
✓ CUDA execution provider configured successfully
Execution provider: CUDA
Generated images
```

### 4. Monitor Metrics

```bash
# Get resource ID
RESOURCE_ID=$(az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv)

# View CPU usage
az monitor metrics list \
  --resource $RESOURCE_ID \
  --metric "CpuPercentage" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M

# View memory usage
az monitor metrics list \
  --resource $RESOURCE_ID \
  --metric "MemoryPercentage" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M
```

---

## Scaling Configuration

### Scale Rules

**CPU-based scaling**:
```bash
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --scale-rule-name cpu-rule \
  --scale-rule-type cpu \
  --scale-rule-metadata type=Utilization value=70
```

**HTTP-based scaling**:
```bash
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --scale-rule-name http-rule \
  --scale-rule-type http \
  --scale-rule-metadata concurrentRequests=5
```

### Recommended Settings

**Development/Testing**:
```yaml
min-replicas: 0        # Scale to zero when idle
max-replicas: 1        # Single instance
gpu-profile: NC8as_T4_v3
```

**Production**:
```yaml
min-replicas: 1        # Always one instance running
max-replicas: 3        # Up to 3 concurrent instances
gpu-profile: NC24ads_A100_v4  # Faster generation
```

---

## Cost Optimization

### 1. Scale to Zero
Set `min-replicas: 0` to eliminate costs when idle:
```bash
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --min-replicas 0
```

**Trade-off**: 60-90 second cold start penalty

### 2. GPU Profile Selection

| Scenario | GPU Profile | Cost/hour | Image Gen Time |
|----------|-------------|-----------|----------------|
| Development | T4 | $0.526 | 60-120s |
| Production (low volume) | T4 | $0.526 | 60-120s |
| Production (high volume) | A100 | $3.672 | 15-30s |

### 3. Request Batching
Process multiple requests per instance to amortize cold start costs.

### 4. Schedule-based Scaling
Use Azure Automation to scale down during off-hours:
```bash
# Scale down at night (example)
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --min-replicas 0
```

---

## Updating the Application

### Update Container Image

```bash
# Rebuild and push
docker build -t $ACR_NAME.azurecr.io/gpu-langchain4j-demo:v2 .
docker push $ACR_NAME.azurecr.io/gpu-langchain4j-demo:v2

# Update container app
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --image $ACR_NAME.azurecr.io/gpu-langchain4j-demo:v2
```

### Update Environment Variables

```bash
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    JAVA_OPTS="-Xmx14g -XX:+UseZGC" \
    NEW_VAR="value"
```

### Update Scaling Settings

```bash
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --min-replicas 1 \
  --max-replicas 5
```

---

## Troubleshooting

### Issue: Container fails to start

**Check logs**:
```bash
az containerapp logs show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --tail 100
```

**Common causes**:
- Insufficient memory (increase `--memory` to 20Gi)
- GPU not available (check workload profile)
- Image pull error (verify ACR credentials)

### Issue: GPU not detected

**Check logs for**:
```
⚠ Failed to configure CUDA provider
```

**Solutions**:
1. Verify GPU workload profile is assigned
2. Check `CUDA_VISIBLE_DEVICES` environment variable
3. Restart container app

### Issue: Slow performance

**Check**:
1. GPU utilization (should be 90-100% during generation)
2. Image generation time (15-60s for GPU, 180-240s for CPU)
3. Memory usage (should use ~8GB GPU memory)

**If using CPU fallback**:
- Check logs for CUDA errors
- Verify cuDNN 8 installation
- Check ONNX Runtime version (must be 1.18.0)

### Issue: High costs

**Check**:
1. Number of running replicas: `az containerapp replica list`
2. Scale-to-zero enabled: `--min-replicas 0`
3. GPU profile: T4 vs A100

**Optimize**:
- Set aggressive scale-down rules
- Use reserved capacity for predictable workloads
- Consider Azure Spot VMs for batch processing

---

## Monitoring and Observability

### Application Insights Integration

```bash
# Create Application Insights
APPINSIGHTS_NAME="gpu-demo-insights"

az monitor app-insights component create \
  --app $APPINSIGHTS_NAME \
  --location $LOCATION \
  --resource-group $RESOURCE_GROUP

# Get instrumentation key
APPINSIGHTS_KEY=$(az monitor app-insights component show \
  --app $APPINSIGHTS_NAME \
  --resource-group $RESOURCE_GROUP \
  --query instrumentationKey -o tsv)

# Update container app
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=$APPINSIGHTS_KEY"
```

### Custom Metrics

Monitor:
- Image generation time
- GPU utilization
- Model loading time
- Request queue depth

---

## Security Best Practices

### 1. Managed Identity
Use managed identity instead of admin credentials:
```bash
# Enable managed identity
az containerapp identity assign \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --system-assigned

# Grant ACR pull access
az acr update --name $ACR_NAME --admin-enabled false
```

### 2. Private Networking
Deploy to VNet for secure communication:
```bash
# Create VNet
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name gpu-demo-vnet \
  --address-prefix 10.0.0.0/16

# Create Container Apps environment in VNet
az containerapp env create \
  --name $CONTAINER_APP_ENV \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --enable-workload-profiles \
  --infrastructure-subnet-resource-id <subnet-id>
```

### 3. HTTPS Only
Enforce HTTPS (enabled by default in Container Apps).

---

## Cleanup

### Delete Everything

```bash
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### Delete Individual Resources

```bash
# Delete container app
az containerapp delete \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --yes

# Delete environment
az containerapp env delete \
  --name $CONTAINER_APP_ENV \
  --resource-group $RESOURCE_GROUP \
  --yes

# Delete ACR
az acr delete \
  --name $ACR_NAME \
  --resource-group $RESOURCE_GROUP \
  --yes
```

---

## FAQ

### Q: Can I use my own models?

**A**: Yes! Replace the `COPY models/` lines in the Dockerfile with your own model paths.

### Q: How do I reduce image size?

**A**: Don't bake models into the image. Instead:
1. Remove `COPY models/` from Dockerfile
2. Mount Azure Files as persistent storage
3. Download models on first startup

**Trade-off**: Slower cold starts, more complex setup.

### Q: Can I use multiple GPUs?

**A**: Container Apps currently supports 1 GPU per instance. For multi-GPU, use Azure Kubernetes Service (AKS) instead.

### Q: What's the cold start time?

**A**: With models baked in: 60-90 seconds
**A**: Without models (mount): 3-5 minutes (includes model download)

### Q: How do I monitor GPU utilization?

**A**: GPU metrics are not directly exposed in Container Apps. Use:
1. Application logs (ONNX Runtime warnings)
2. Generation time (fast = GPU, slow = CPU)
3. Enable custom metrics in your app

---

## Support

- **Documentation**: [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- **GPU Support**: [GPU Workload Profiles](https://learn.microsoft.com/azure/container-apps/workload-profiles-overview)
- **Pricing**: [Azure Container Apps Pricing](https://azure.microsoft.com/pricing/details/container-apps/)
- **Issues**: Create issue in this repository

---

**Last Updated**: October 1, 2025  
**Tested With**: Azure CLI 2.53.0, Docker 24.0.6, CUDA 12.6, ONNX Runtime 1.18.0
