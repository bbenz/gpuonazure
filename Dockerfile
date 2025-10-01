# Multi-stage Dockerfile for GPU LangChain4j Demo
# Stage 1: Build application with Maven
# Stage 2: Runtime with CUDA support

###############################################################################
# Stage 1: Build
###############################################################################
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /build

# Copy Maven configuration
COPY pom.xml .

# Download dependencies (cached layer)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build application
RUN mvn clean package -DskipTests -B

###############################################################################
# Stage 2: Runtime with CUDA 12.6 + cuDNN 8
###############################################################################
# SUCCESS: ONNX Runtime 1.18.0 + CUDA 12.6 + cuDNN 8 + Ubuntu 24.04 (GLIBC 2.39)
# This configuration has been tested and GPU acceleration is working!
FROM nvidia/cuda:12.6.0-cudnn-runtime-ubuntu24.04

# Set CUDA environment variables
ENV CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Install Java 21 and required tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openjdk-21-jre-headless \
        curl \
        ca-certificates \
        wget \
        gnupg2 \
        xz-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# CRITICAL: Install cuDNN 8 (ONNX Runtime 1.18.0 requires cuDNN 8, base image has cuDNN 9)
# Download cuDNN 8.9.7 for CUDA 12.x from NVIDIA and install to multiple paths
RUN wget https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz && \
    tar -xf cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz && \
    # Install to /usr/local/cuda/lib64 (CUDA default location)
    cp -P cudnn-linux-x86_64-8.9.7.29_cuda12-archive/lib/libcudnn* /usr/local/cuda/lib64/ && \
    cp -P cudnn-linux-x86_64-8.9.7.29_cuda12-archive/include/cudnn* /usr/local/cuda/include/ && \
    # ALSO install to /lib/x86_64-linux-gnu (where ONNX Runtime looks for it)
    cp -P cudnn-linux-x86_64-8.9.7.29_cuda12-archive/lib/libcudnn.so.8* /lib/x86_64-linux-gnu/ && \
    cp -P cudnn-linux-x86_64-8.9.7.29_cuda12-archive/lib/libcudnn_*.so.8* /lib/x86_64-linux-gnu/ && \
    rm -rf cudnn-linux-x86_64-8.9.7.29_cuda12-archive* && \
    ldconfig && \
    echo "✓ cuDNN 8 installed successfully"

# Create application directory
WORKDIR /app

# Create models directory
RUN mkdir -p /app/models/stable-diffusion && \
    mkdir -p /app/models/all-MiniLM-L6-v2

# Copy built JAR from build stage
COPY --from=build /build/target/*.jar /app/app.jar

# Copy ONNX Runtime Extensions library (required for SD4J CLIP tokenizer)
# This is compatible with Ubuntu 24.04 (GLIBC 2.39)
COPY libortextensions.so /app/libortextensions.so

# Copy text_tokenizer directory (SD4J looks for this relative to working directory)
COPY text_tokenizer /app/text_tokenizer

# AZURE DEPLOYMENT: Bake models into image for faster cold starts
# Note: This increases image size from ~600MB to ~5GB but eliminates:
#   - Need for Azure File Share mounting
#   - Cold start delays from model downloads
#   - Complexity of persistent storage configuration
COPY models/stable-diffusion /app/models/stable-diffusion
COPY models/all-MiniLM-L6-v2 /app/models/all-MiniLM-L6-v2

# Environment variables
ENV JAVA_OPTS="-Xmx8g -XX:+UseZGC -XX:+ZGenerational --enable-preview" \
    SPRING_PROFILES_ACTIVE="production" \
    GPU_LANGCHAIN4J_MODEL_DIR="/app/models" \
    GPU_LANGCHAIN4J_GPU_ENABLED="true" \
    GPU_LANGCHAIN4J_GPU_DEVICE_ID="0" \
    CUDA_VISIBLE_DEVICES="0"

# Expose application port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

# Models are now baked into the image (no need to download or mount)
# Note: This makes the image self-contained but increases size significantly

# Start application
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]

###############################################################################
# Build and Deployment Instructions:
# 
# LOCAL TESTING:
# 1. Build the image:
#    docker build -t gpu-langchain4j-demo:latest .
#
# 2. Run locally with GPU (models are baked in):
#    docker run --gpus all -p 8080:8080 \
#      -e JAVA_OPTS="-Xmx8g -XX:+UseZGC" \
#      gpu-langchain4j-demo:latest
#
# AZURE DEPLOYMENT:
# 1. Create Azure Container Registry (if not exists):
#    az acr create --resource-group <rg-name> --name <acr-name> --sku Premium
#
# 2. Login to ACR:
#    az acr login --name <acr-name>
#
# 3. Build and push to ACR (multi-platform build for Azure):
#    docker buildx build --platform linux/amd64 \
#      -t <acr-name>.azurecr.io/gpu-langchain4j-demo:latest \
#      --push .
#
# 4. Create GPU workload profile (T4 or A100):
#    az containerapp env workload-profile set \
#      --name <env-name> --resource-group <rg-name> \
#      --workload-profile-name gpu-t4 \
#      --workload-profile-type NC8as_T4_v3 \
#      --min-nodes 1 --max-nodes 3
#
# 5. Deploy to Azure Container Apps:
#    az containerapp create \
#      --name gpu-langchain4j-demo \
#      --resource-group <rg-name> \
#      --environment <env-name> \
#      --image <acr-name>.azurecr.io/gpu-langchain4j-demo:latest \
#      --registry-server <acr-name>.azurecr.io \
#      --target-port 8080 \
#      --ingress external \
#      --cpu 4 --memory 16Gi \
#      --workload-profile-name gpu-t4 \
#      --min-replicas 1 --max-replicas 3 \
#      --env-vars \
#        JAVA_OPTS="-Xmx12g -XX:+UseZGC -XX:+ZGenerational --enable-preview" \
#        SPRING_PROFILES_ACTIVE="production" \
#        GPU_LANGCHAIN4J_GPU_ENABLED="true"
#
# ARCHITECTURE:
# - Base: Ubuntu 24.04 (GLIBC 2.39)
# - CUDA: 12.6.0
# - cuDNN: 8.9.7 (custom install)
# - ONNX Runtime: 1.18.0 GPU
# - Java: 21 LTS
# - Models: Baked into image (~5GB total)
#
# GPU PROFILES:
# - NC8as_T4_v3: NVIDIA T4 (16GB), 8 vCPU, 56GB RAM
# - NC24ads_A100_v4: NVIDIA A100 (80GB), 24 vCPU, 220GB RAM
###############################################################################
