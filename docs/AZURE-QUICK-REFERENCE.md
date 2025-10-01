# Azure Deployment Quick Reference

## 🚀 Quick Deploy (5 minutes to start)

```bash
./deploy-azure-aca.sh
```

---

## 📋 Manual Commands

### Build & Push
```bash
ACR_NAME="gpudemoregistry"
az acr login --name $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/gpu-langchain4j-demo:latest .
docker push $ACR_NAME.azurecr.io/gpu-langchain4j-demo:latest
```

### Deploy
```bash
az containerapp create \
  --name gpu-langchain4j-demo \
  --resource-group gpu-demo-rg \
  --environment gpu-demo-env \
  --image $ACR_NAME.azurecr.io/gpu-langchain4j-demo:latest \
  --target-port 8080 \
  --ingress external \
  --cpu 4 --memory 16Gi \
  --workload-profile-name gpu-t4 \
  --min-replicas 0 --max-replicas 3
```

---

## 🔍 Quick Test

```bash
# Get URL
APP_URL=$(az containerapp show --name gpu-langchain4j-demo --resource-group gpu-demo-rg --query properties.configuration.ingress.fqdn -o tsv)

# Health check
curl https://$APP_URL/actuator/health

# Generate image
curl -X POST https://$APP_URL/api/langchain4j/image \
  -H "Content-Type: application/json" \
  -d '{"prompt": "sunset", "style": "CLASSIC"}' \
  --output test.png
```

---

## 💰 GPU Profiles

| Profile | GPU | vCPU | Memory | $/hour |
|---------|-----|------|--------|--------|
| NC8as_T4_v3 | T4 (16GB) | 8 | 56GB | $0.526 |
| NC24ads_A100_v4 | A100 (80GB) | 24 | 220GB | $3.672 |

---

## 📊 Monitor

```bash
# Logs
az containerapp logs show --name gpu-langchain4j-demo --resource-group gpu-demo-rg --follow

# Metrics
az monitor metrics list --resource $(az containerapp show --name gpu-langchain4j-demo --resource-group gpu-demo-rg --query id -o tsv) --metric "CpuPercentage"
```

---

## 🔄 Update

```bash
# New image
docker build -t $ACR_NAME.azurecr.io/gpu-langchain4j-demo:v2 .
docker push $ACR_NAME.azurecr.io/gpu-langchain4j-demo:v2
az containerapp update --name gpu-langchain4j-demo --resource-group gpu-demo-rg --image $ACR_NAME.azurecr.io/gpu-langchain4j-demo:v2

# Scale
az containerapp update --name gpu-langchain4j-demo --resource-group gpu-demo-rg --min-replicas 1 --max-replicas 5
```

---

## 🧹 Cleanup

```bash
az group delete --name gpu-demo-rg --yes
```

---

## ⚙️ Environment Variables

```bash
JAVA_OPTS="-Xmx12g -XX:+UseZGC -XX:+ZGenerational --enable-preview"
SPRING_PROFILES_ACTIVE="production"
GPU_LANGCHAIN4J_GPU_ENABLED="true"
GPU_LANGCHAIN4J_GPU_DEVICE_ID="0"
```

---

## 🎯 Success Indicators

**Logs show**:
```
✓ CUDA execution provider configured successfully
Execution provider: CUDA
Generated images
```

**Performance**:
- Generation time: 15-60s (GPU) vs 180-240s (CPU)
- GPU memory: ~8GB utilized
- Cold start: 60-90 seconds

---

## 📚 Full Documentation

See [AZURE-DEPLOYMENT-GUIDE.md](./AZURE-DEPLOYMENT-GUIDE.md) for complete instructions.
