# GPU-Accelerated Image Generation - Complete Setup Guide

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Detailed Setup](#detailed-setup)
4. [Model Downloads](#model-downloads)
5. [ONNX Runtime Extensions](#onnx-runtime-extensions)
6. [Running the Application](#running-the-application)
7. [Azure Deployment](#azure-deployment)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software
- **Java 21 LTS** or newer (with `--enable-preview`)
- **Maven 3.9+**
- **Git**
- **cmake** (for building ONNX Runtime Extensions)
- **build-essential** (Linux) or **Xcode Command Line Tools** (macOS)

### Azure Resources (for deployment)
- Azure Container Apps with GPU workload profile (NC8as_T4_v3 or NC24ads_A100_v4)
- Azure Container Registry (optional, for custom images)

### Disk Space Requirements
- **~6GB** for Stable Diffusion models
- **~100MB** for build tools and dependencies
- **~1GB** for Maven dependencies

---

## Quick Start

```bash
# 1. Clone the repository
git clone <your-repo-url>
cd gpuonazure

# 2. Install build tools
sudo apt-get update
sudo apt-get install -y cmake build-essential git

# 3. Download Stable Diffusion models (~5.2GB)
./download-missing-models.sh

# 4. Build ONNX Runtime Extensions (~10 minutes)
./download-ortextensions.sh

# 5. Run the application
mvn spring-boot:run

# 6. Open browser
open http://localhost:8080
```

---

## Detailed Setup

### Step 1: Install Java 21

#### Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y openjdk-21-jdk
java -version  # Should show 21.x.x
```

#### macOS:
```bash
brew install openjdk@21
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
```

#### Verify:
```bash
java -version
mvn -version
```

### Step 2: Install Build Tools

#### Linux (Ubuntu/Debian):
```bash
sudo apt-get update
sudo apt-get install -y cmake build-essential git curl
```

#### macOS:
```bash
brew install cmake git
xcode-select --install
```

#### Verify:
```bash
cmake --version  # Should be 3.15+
git --version
```

---

## Model Downloads

### SD4J Model Structure

SD4J requires Stable Diffusion v1.5 models in **specific subdirectories**:

```
models/stable-diffusion/
├── text_encoder/
│   └── model.onnx          # CLIP text encoder (492MB)
├── unet/
│   ├── model.onnx          # U-Net architecture (1.7MB)
│   └── weights.pb          # U-Net weights (3.3GB)
├── vae_decoder/
│   └── model.onnx          # VAE decoder (198MB)
└── safety_checker/         # Optional NSFW filter
    └── model.onnx          # Safety checker (1.2GB)
```

### Download Option 1: Use the Script (Recommended)

If you already have the models but they're in the wrong structure:

```bash
./download-missing-models.sh
```

This will:
- Download missing models (text_encoder, vae_decoder)
- Reorganize existing U-Net files into subdirectories
- Skip safety_checker by default (saves 1.2GB)

**Download time:** ~3-5 minutes on fast connection

### Download Option 2: Manual Download

```bash
# Create directory structure
mkdir -p models/stable-diffusion/{text_encoder,unet,vae_decoder,safety_checker}

# Download from HuggingFace
BASE_URL="https://huggingface.co/onnx-community/stable-diffusion-v1-5-ONNX/resolve/main"

# Text Encoder (492MB)
curl -L "$BASE_URL/text_encoder/model.onnx" \
  -o models/stable-diffusion/text_encoder/model.onnx

# U-Net (1.7MB + 3.3GB)
curl -L "$BASE_URL/unet/model.onnx" \
  -o models/stable-diffusion/unet/model.onnx
curl -L "$BASE_URL/unet/weights.pb" \
  -o models/stable-diffusion/unet/weights.pb

# VAE Decoder (198MB)
curl -L "$BASE_URL/vae_decoder/model.onnx" \
  -o models/stable-diffusion/vae_decoder/model.onnx

# Safety Checker - Optional (1.2GB)
curl -L "$BASE_URL/safety_checker/model.onnx" \
  -o models/stable-diffusion/safety_checker/model.onnx
```

### Verify Model Structure

```bash
# Check all required files exist
ls -lh models/stable-diffusion/text_encoder/model.onnx  # 492MB
ls -lh models/stable-diffusion/unet/model.onnx          # 1.7MB
ls -lh models/stable-diffusion/unet/weights.pb          # 3.3GB
ls -lh models/stable-diffusion/vae_decoder/model.onnx   # 198MB
```

---

## ONNX Runtime Extensions

### Why is this needed?

SD4J uses a **custom CLIP tokenizer** (`custom_op_cliptok.onnx`) that requires ONNX Runtime Extensions. This library provides custom operators not available in standard ONNX Runtime.

**Without it, you'll see:**
```
ai.onnxruntime.OrtException: Failed to load library ./libortextensions.so
```

### Build ONNX Runtime Extensions

#### Automated Build (Recommended):

```bash
./download-ortextensions.sh
```

**What it does:**
1. Clones `microsoft/onnxruntime-extensions` (~100MB)
2. Builds the library using cmake (~5-10 minutes)
3. Copies `libortextensions.so` (~3MB) to project root
4. Cleans up temporary files

**Build time:** ~5-10 minutes on modern hardware

#### Manual Build:

```bash
# Clone the repo
git clone https://github.com/microsoft/onnxruntime-extensions.git /tmp/ortextensions
cd /tmp/ortextensions

# Build
./build_lib.sh --config Release --update --build --parallel

# Find and copy library
BUILT_LIB=$(find build -name "libortextensions.so*" -type f | head -1)
cp "$BUILT_LIB" /path/to/gpuonazure/libortextensions.so
```

#### Platform-Specific Libraries:

- **Linux**: `libortextensions.so`
- **macOS**: `libortextensions.dylib`
- **Windows**: `ortextensions.dll`

SD4J automatically detects your platform.

### Verify Installation

```bash
ls -lh libortextensions.so  # Should be ~3-10MB
ldd libortextensions.so     # Check dependencies (Linux)
```

---

## Running the Application

### Local Development (CPU Mode)

```bash
# Default: CPU mode
mvn spring-boot:run

# Access the application
open http://localhost:8080
```

**Expected performance (CPU):**
- First generation: ~60 seconds (model loading)
- Subsequent: ~30-45 seconds per image
- Memory: ~6GB RAM

### Local Development (GPU Mode - if CUDA available)

```bash
# Enable GPU in application.yml or via environment variable
export ENABLE_GPU=true
mvn spring-boot:run
```

**Expected performance (GPU):**
- First generation: ~10 seconds (model loading)
- Subsequent: ~3-5 seconds per image (T4) or ~1-2 seconds (A100)
- VRAM: ~4GB

### Build for Production

```bash
# Build JAR
mvn clean package

# Run JAR
java -jar target/gpu-langchain4j-demo-1.0.0.jar
```

### Docker Build

```bash
# Build image
docker build -t gpu-langchain4j-demo:latest .

# Run container (CPU)
docker run -p 8080:8080 gpu-langchain4j-demo:latest

# Run container (GPU)
docker run --gpus all -p 8080:8080 gpu-langchain4j-demo:latest
```

---

## Azure Deployment

### Prerequisites

1. **Azure Container Apps Environment** with GPU workload profile
2. **GPU SKU**: NC8as_T4_v3 (T4) or NC24ads_A100_v4 (A100)
3. **Container Registry** (optional, or use Docker Hub)

### Deployment Steps

```bash
# 1. Set variables
RESOURCE_GROUP="gpu-demo-rg"
LOCATION="eastus"
ENV_NAME="gpu-demo-env"
APP_NAME="gpu-langchain4j"
ACR_NAME="gpudemoacr"

# 2. Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# 3. Create Container Registry (optional)
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Premium

# 4. Build and push image
az acr build \
  --registry $ACR_NAME \
  --image gpu-langchain4j:latest \
  --file Dockerfile .

# 5. Create Container Apps environment with GPU
az containerapp env create \
  --name $ENV_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --enable-workload-profiles

# 6. Add GPU workload profile (T4)
az containerapp env workload-profile add \
  --name $ENV_NAME \
  --resource-group $RESOURCE_GROUP \
  --workload-profile-type NC8-A10 \
  --workload-profile-name gpu-profile \
  --min-nodes 1 \
  --max-nodes 3

# 7. Deploy container app
az containerapp create \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment $ENV_NAME \
  --workload-profile-name gpu-profile \
  --image $ACR_NAME.azurecr.io/gpu-langchain4j:latest \
  --cpu 4 \
  --memory 16Gi \
  --min-replicas 1 \
  --max-replicas 3 \
  --ingress external \
  --target-port 8080 \
  --env-vars ENABLE_GPU=true \
  --registry-server $ACR_NAME.azurecr.io
```

### Using the Deploy Script

```bash
# Edit deploy-aca.sh with your values
./deploy-aca.sh
```

---

## Troubleshooting

### Issue: Application won't start

**Error:** `Stable Diffusion model not found`

**Solution:**
```bash
# Verify model structure
ls -R models/stable-diffusion/

# Should show subdirectories: text_encoder, unet, vae_decoder
# Run model download script if missing
./download-missing-models.sh
```

---

### Issue: libortextensions.so not found

**Error:** `Failed to load library ./libortextensions.so`

**Solution:**
```bash
# Build the library
./download-ortextensions.sh

# Or manually copy if you have a prebuilt one
cp /path/to/libortextensions.so ./

# Verify it exists
ls -lh libortextensions.so  # Should be ~3-10MB
```

---

### Issue: Out of Memory

**Error:** `OutOfMemoryError` or slow performance

**Solution:**
```bash
# Increase JVM heap size
export JAVA_OPTS="-Xmx8g -XX:+UseZGC"
mvn spring-boot:run

# Or in production
java -Xmx8g -XX:+UseZGC -jar target/gpu-langchain4j-demo-1.0.0.jar
```

**Requirements:**
- CPU mode: 6-8GB RAM minimum
- GPU mode: 4GB VRAM + 4GB RAM minimum

---

### Issue: Slow Image Generation

**Expected Times:**
- **CPU**: 30-60 seconds per image (normal)
- **GPU T4**: 3-5 seconds (normal)
- **GPU A100**: 1-2 seconds (normal)
- **First generation**: Always slower (model loading)

**Optimization:**
```yaml
# application.yml - reduce steps for faster generation
gpu:
  langchain4j:
    inference-steps: 20  # Default 40, min 15
```

---

### Issue: CUDA not available

**Error:** `This binary was not compiled with CUDA support`

**Explanation:** The standard ONNX Runtime JAR doesn't include CUDA. For GPU support in production, use `onnxruntime_gpu`.

**Solution:**
```xml
<!-- pom.xml - Replace CPU version with GPU version -->
<dependency>
    <groupId>com.microsoft.onnxruntime</groupId>
    <artifactId>onnxruntime_gpu</artifactId>
    <version>1.16.3</version>
</dependency>
```

**Note:** This requires CUDA 12.2 and cuDNN installed on the system.

---

### Issue: Port 8080 already in use

**Solution:**
```bash
# Change port in application.yml
server:
  port: 8081

# Or via command line
mvn spring-boot:run -Dserver.port=8081
```

---

## Performance Benchmarks

### CPU Mode (Intel i7 6-core)
- Model loading: ~10 seconds
- First generation: ~60 seconds
- Subsequent: ~30-45 seconds
- Memory: ~6GB RAM

### GPU Mode (NVIDIA T4)
- Model loading: ~5 seconds
- First generation: ~10 seconds
- Subsequent: ~3-5 seconds ⚡
- VRAM: ~4GB

### GPU Mode (NVIDIA A100)
- Model loading: ~3 seconds
- First generation: ~5 seconds
- Subsequent: ~1-2 seconds 🚀
- VRAM: ~4GB

---

## Project Structure

```
gpuonazure/
├── src/main/
│   ├── java/com/azure/gpudemo/
│   │   ├── GpuLangchain4jDemoApplication.java
│   │   ├── config/
│   │   │   └── LangChain4jGpuConfiguration.java
│   │   ├── service/
│   │   │   ├── SD4JImageGenerationService.java      # SD4J wrapper
│   │   │   ├── LangChain4jGpuService.java          # Main service
│   │   │   └── ModelManagementService.java
│   │   └── controller/
│   │       └── ClippyController.java
│   ├── com/oracle/labs/mlrg/sd4j/                   # SD4J source (18 files)
│   │   ├── SD4J.java
│   │   ├── TextEmbedder.java
│   │   ├── UNet.java
│   │   ├── VAEDecoder.java
│   │   └── ...
│   └── resources/
│       ├── application.yml
│       └── static/
│           ├── index.html
│           ├── css/styles.css
│           └── js/app.js
├── models/
│   └── stable-diffusion/                            # ~5.2GB
│       ├── text_encoder/model.onnx
│       ├── unet/model.onnx + weights.pb
│       ├── vae_decoder/model.onnx
│       └── safety_checker/model.onnx (optional)
├── text_tokenizer/
│   └── custom_op_cliptok.onnx                       # 1.68MB
├── libortextensions.so                              # ~3MB (build this!)
├── pom.xml
├── Dockerfile
├── download-missing-models.sh                       # Model downloader
├── download-ortextensions.sh                        # Library builder
├── deploy-aca.sh                                    # Azure deployment
└── SETUP.md                                         # This file
```

---

## Additional Resources

- **SD4J GitHub**: https://github.com/oracle/sd4j
- **LangChain4j Docs**: https://docs.langchain4j.dev/
- **ONNX Runtime**: https://onnxruntime.ai/
- **ONNX Runtime Extensions**: https://github.com/microsoft/onnxruntime-extensions
- **Azure Container Apps**: https://learn.microsoft.com/azure/container-apps/
- **Stable Diffusion v1.5**: https://huggingface.co/runwayml/stable-diffusion-v1-5

---

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review logs: `tail -f logs/application.log`
3. Enable debug logging: `--debug` flag or `logging.level.root=DEBUG`
4. Check SD4J documentation: https://github.com/oracle/sd4j

---

## License

This project uses:
- **SD4J**: Universal Permissive License (UPL)
- **LangChain4j**: Apache License 2.0
- **ONNX Runtime**: MIT License
- **Stable Diffusion models**: Check individual model licenses on HuggingFace

---

**Last Updated**: September 30, 2025  
**Version**: 1.0.0  
**Java**: 21 LTS  
**Spring Boot**: 3.2.5  
**LangChain4j**: 0.34.0  
**ONNX Runtime**: 1.16.3  
**SD4J**: 1.1-1.14.0
