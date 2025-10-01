# Azure Deployment Checklist ✅

Use this checklist to ensure a smooth deployment to Azure Container Apps with GPU.

---

## Pre-Deployment Checklist

### Local Environment
- [ ] **Docker installed** and running
  ```bash
  docker --version  # Should be 20.10+ or later
  ```
- [ ] **Azure CLI installed** (version 2.50.0+)
  ```bash
  az --version
  ```
- [ ] **Git repository** cloned
  ```bash
  cd /path/to/gpuonazure
  ```

### Models
- [ ] **Models downloaded** (~2.5GB)
  ```bash
  ls -lh models/stable-diffusion/
  ls -lh models/all-MiniLM-L6-v2/
  ```
- [ ] **Text tokenizer** present
  ```bash
  ls text_tokenizer/
  ```
- [ ] **libortextensions.so** present
  ```bash
  ls -lh libortextensions.so
  ```

### Azure Account
- [ ] **Logged into Azure**
  ```bash
  az login
  ```
- [ ] **Subscription selected**
  ```bash
  az account show
  ```
- [ ] **GPU quota available**
  - Check: Azure Portal → Quotas → Compute → NC-series
  - Required: At least 8 vCPU for NC8as_T4_v3

### Local Testing (Recommended)
- [ ] **Build succeeds**
  ```bash
  docker build -f Dockerfile.ubuntu24 -t test:local .
  ```
- [ ] **Container runs**
  ```bash
  docker run --gpus all -p 8080:8080 test:local
  ```
- [ ] **GPU acceleration working**
  ```bash
  # Check logs for: "✓ CUDA execution provider configured successfully"
  docker logs <container-id> | grep CUDA
  ```
- [ ] **Image generation works**
  ```bash
  curl -X POST http://localhost:8080/api/langchain4j/image \
    -H "Content-Type: application/json" \
    -d '{"prompt": "test", "style": "CLASSIC"}' \
    --output test-local.png
  ```

---

## Deployment Checklist

### Configuration
- [ ] **Resource names chosen**
  ```bash
  export RESOURCE_GROUP="gpu-demo-rg"
  export ACR_NAME="gpudemoregistry"  # Must be globally unique!
  export LOCATION="eastus"
  export GPU_PROFILE="NC8as_T4_v3"  # or NC24ads_A100_v4
  ```
- [ ] **ACR name is unique**
  ```bash
  az acr check-name --name $ACR_NAME
  # Should return: "nameAvailable": true
  ```

### Deployment Script
- [ ] **Script is executable**
  ```bash
  chmod +x deploy-azure-aca.sh
  ```
- [ ] **Run deployment**
  ```bash
  ./deploy-azure-aca.sh
  ```
- [ ] **Monitor progress** (15-20 minutes)
  - Creating resource group
  - Creating Azure Container Registry
  - Building Docker image (5-10 min)
  - Pushing to ACR (2-5 min)
  - Creating Container Apps environment
  - Deploying application

### Expected Output
- [ ] **All steps complete**
  ```
  ✓ Created resource group
  ✓ Created ACR
  ✓ Image pushed
  ✓ Environment created
  ✓ GPU workload profile configured
  ✓ Container app deployed
  ```
- [ ] **Application URL received**
  ```
  Application URL: https://gpu-langchain4j-demo.<random>.eastus.azurecontainerapps.io
  ```

---

## Post-Deployment Checklist

### Verification
- [ ] **Health check passes** (wait 60-90s for cold start)
  ```bash
  APP_URL="<your-app-url>"
  curl https://$APP_URL/actuator/health
  # Expected: {"status":"UP"}
  ```
- [ ] **Web UI accessible**
  ```bash
  open https://$APP_URL  # or visit in browser
  ```
- [ ] **Image generation works**
  ```bash
  curl -X POST https://$APP_URL/api/langchain4j/image \
    -H "Content-Type: application/json" \
    -d '{"prompt": "sunset over mountains", "style": "CLASSIC"}' \
    --output test-azure.png \
    -w "\nTime: %{time_total}s\n"
  # Expected: 60-120s (first request), 15-60s (subsequent)
  ```
- [ ] **Check logs for GPU**
  ```bash
  az containerapp logs show \
    --name gpu-langchain4j-demo \
    --resource-group $RESOURCE_GROUP \
    --tail 50 | grep -E "CUDA|GPU|Execution"
  # Expected: "✓ CUDA execution provider configured successfully"
  #           "Execution provider: CUDA"
  ```

### Performance
- [ ] **Generation time acceptable**
  - First request: 60-120 seconds (includes model loading)
  - Subsequent: 15-60 seconds (T4) or 10-30 seconds (A100)
  - CPU fallback: 180-240 seconds (indicates problem!)
- [ ] **No warnings about CPU fallback**
  ```bash
  az containerapp logs show --name gpu-langchain4j-demo --resource-group $RESOURCE_GROUP | grep "CPU fallback"
  # Should return nothing (or very old entries)
  ```

### Cost Optimization
- [ ] **Scale-to-zero enabled** (optional but recommended)
  ```bash
  az containerapp show \
    --name gpu-langchain4j-demo \
    --resource-group $RESOURCE_GROUP \
    --query "properties.template.scale.minReplicas"
  # Should return: 0 (for scale-to-zero)
  ```
- [ ] **Set up budget alerts** (recommended)
  - Azure Portal → Cost Management → Budgets
  - Create alert for your resource group

---

## Monitoring Checklist

### Initial Setup
- [ ] **View real-time logs**
  ```bash
  az containerapp logs show \
    --name gpu-langchain4j-demo \
    --resource-group $RESOURCE_GROUP \
    --follow
  ```
- [ ] **Check metrics**
  ```bash
  RESOURCE_ID=$(az containerapp show \
    --name gpu-langchain4j-demo \
    --resource-group $RESOURCE_GROUP \
    --query id -o tsv)
  
  az monitor metrics list \
    --resource $RESOURCE_ID \
    --metric "CpuPercentage"
  ```

### Application Insights (Optional)
- [ ] **Create Application Insights**
  ```bash
  az monitor app-insights component create \
    --app gpu-demo-insights \
    --location $LOCATION \
    --resource-group $RESOURCE_GROUP
  ```
- [ ] **Connect to container app**
  ```bash
  APPINSIGHTS_KEY=$(az monitor app-insights component show \
    --app gpu-demo-insights \
    --resource-group $RESOURCE_GROUP \
    --query instrumentationKey -o tsv)
  
  az containerapp update \
    --name gpu-langchain4j-demo \
    --resource-group $RESOURCE_GROUP \
    --set-env-vars \
      APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=$APPINSIGHTS_KEY"
  ```

---

## Troubleshooting Checklist

### Issue: Container fails to start
- [ ] Check logs for errors
  ```bash
  az containerapp logs show --name gpu-langchain4j-demo --resource-group $RESOURCE_GROUP --tail 100
  ```
- [ ] Verify image exists in ACR
  ```bash
  az acr repository show --name $ACR_NAME --repository gpu-langchain4j-demo
  ```
- [ ] Check GPU workload profile
  ```bash
  az containerapp env workload-profile list \
    --name gpu-demo-env \
    --resource-group $RESOURCE_GROUP
  ```

### Issue: GPU not working
- [ ] Verify CUDA in logs
  ```bash
  az containerapp logs show --name gpu-langchain4j-demo --resource-group $RESOURCE_GROUP | grep "CUDA"
  ```
- [ ] Check for cuDNN errors
  ```bash
  az containerapp logs show --name gpu-langchain4j-demo --resource-group $RESOURCE_GROUP | grep "cudnn"
  ```
- [ ] Verify ONNX Runtime version
  ```bash
  az containerapp logs show --name gpu-langchain4j-demo --resource-group $RESOURCE_GROUP | grep "ONNX Runtime version"
  # Expected: 1.18.0
  ```

### Issue: Slow performance
- [ ] Check generation time
  - GPU: 15-60 seconds
  - CPU fallback: 180-240 seconds
- [ ] Verify not using CPU fallback
  ```bash
  az containerapp logs show --name gpu-langchain4j-demo --resource-group $RESOURCE_GROUP | grep "Config provider"
  # Expected: "Config provider: CUDA" (NOT "CPU")
  ```
- [ ] Consider upgrading to A100
  ```bash
  export GPU_PROFILE="NC24ads_A100_v4"
  ./deploy-azure-aca.sh
  ```

---

## Cleanup Checklist

### Temporary Cleanup (Keep Infrastructure)
- [ ] **Stop container app**
  ```bash
  az containerapp update \
    --name gpu-langchain4j-demo \
    --resource-group $RESOURCE_GROUP \
    --min-replicas 0 \
    --max-replicas 0
  ```

### Full Cleanup (Delete Everything)
- [ ] **Delete resource group**
  ```bash
  az group delete --name $RESOURCE_GROUP --yes --no-wait
  ```
- [ ] **Verify deletion**
  ```bash
  az group exists --name $RESOURCE_GROUP
  # Should return: false
  ```
- [ ] **Check for orphaned resources**
  ```bash
  az resource list --query "[?contains(name, 'gpu')]" --output table
  ```

---

## Success Criteria ✅

Your deployment is successful when:

1. ✅ **Health check returns UP**
2. ✅ **Web UI loads in browser**
3. ✅ **Image generation completes in 15-60 seconds**
4. ✅ **Logs show "Execution provider: CUDA"**
5. ✅ **No CPU fallback warnings**
6. ✅ **Generated images look good (not blurry/corrupted)**
7. ✅ **Costs are as expected (check Azure Cost Management)**

---

## Next Steps After Success

- [ ] **Test concurrent requests**
- [ ] **Set up monitoring alerts**
- [ ] **Configure custom domain** (optional)
- [ ] **Enable HTTPS certificate** (auto-enabled)
- [ ] **Set up CI/CD pipeline** (GitHub Actions)
- [ ] **Document your specific use case**
- [ ] **Share feedback/improvements**

---

## Reference

- **Quick Start**: `./deploy-azure-aca.sh`
- **Complete Guide**: `AZURE-DEPLOYMENT-GUIDE.md`
- **Quick Reference**: `AZURE-QUICK-REFERENCE.md`
- **Performance Testing**: `./test-gpu-performance.sh`
- **GPU Success Story**: `GPU-SUCCESS-SUMMARY.md`

---

**Estimated Total Time**: 20-30 minutes (including verification)

**Good luck with your deployment! 🚀**
