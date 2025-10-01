#!/bin/bash
# Test script for GPU-enabled Docker build with custom libortextensions.so
# Created: September 30, 2025
# Purpose: Verify GLIBC 2.35 compatibility and GPU initialization

set -e

echo "======================================================================"
echo "GPU Docker Build Test Suite"
echo "======================================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="gpu-langchain4j-demo:ubuntu24"
CONTAINER_NAME="gpu-langchain4j"
MODELS_PATH="$(pwd)/models"
TOKENIZER_PATH="$(pwd)/text_tokenizer"

echo "Step 1: Check if Docker build completed successfully"
echo "----------------------------------------------------------------------"
if docker images gpu-langchain4j-demo:ubuntu24 --format "{{.Repository}}:{{.Tag}}" | grep -q "ubuntu24"; then
    echo -e "${GREEN}✓${NC} Docker image found: $IMAGE_NAME"
    docker images gpu-langchain4j-demo
else
    echo -e "${RED}✗${NC} Docker image not found. Build may still be running."
    echo "   Check: tail -f docker-build.log"
    exit 1
fi
echo ""

echo "Step 2: Stop and remove any existing container"
echo "----------------------------------------------------------------------"
if docker ps -a | grep -q "$CONTAINER_NAME"; then
    echo "Stopping existing container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Old container removed"
else
    echo -e "${GREEN}✓${NC} No existing container to remove"
fi
echo ""

echo "Step 3: Verify model files exist"
echo "----------------------------------------------------------------------"
if [ -d "$MODELS_PATH/stable-diffusion" ]; then
    echo -e "${GREEN}✓${NC} Stable Diffusion models found"
    ls -lh "$MODELS_PATH/stable-diffusion" | head -5
else
    echo -e "${RED}✗${NC} Stable Diffusion models not found at: $MODELS_PATH/stable-diffusion"
    exit 1
fi

if [ -d "$TOKENIZER_PATH" ]; then
    echo -e "${GREEN}✓${NC} Text tokenizer found"
    ls -lh "$TOKENIZER_PATH" | head -5
else
    echo -e "${RED}✗${NC} Text tokenizer not found at: $TOKENIZER_PATH"
    exit 1
fi
echo ""

echo "Step 4: Start container with GPU support"
echo "----------------------------------------------------------------------"
docker run -d --gpus all \
    -p 8080:8080 \
    -v "$MODELS_PATH:/app/models" \
    -v "$TOKENIZER_PATH:/app/text_tokenizer" \
    -e ENABLE_GPU=true \
    -e JAVA_OPTS="-Xmx8g -XX:+UseZGC -XX:+ZGenerational --enable-preview" \
    --name "$CONTAINER_NAME" \
    "$IMAGE_NAME"

echo -e "${GREEN}✓${NC} Container started: $CONTAINER_NAME"
echo ""

echo "Step 5: Wait for application to start (60 seconds)"
echo "----------------------------------------------------------------------"
for i in {1..60}; do
    if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "Started GpuLangchain4jDemoApplication"; then
        echo -e "${GREEN}✓${NC} Application started successfully!"
        break
    fi
    echo -n "."
    sleep 1
done
echo ""
echo ""

echo "Step 6: Verify GLIBC compatibility"
echo "----------------------------------------------------------------------"
echo "Checking libortextensions.so dependencies..."
docker exec "$CONTAINER_NAME" ldd /app/libortextensions.so | grep -E "libc.so|not found"

if docker exec "$CONTAINER_NAME" ldd /app/libortextensions.so | grep -q "not found"; then
    echo -e "${RED}✗${NC} Missing dependencies detected!"
    exit 1
else
    echo -e "${GREEN}✓${NC} All dependencies resolved"
fi
echo ""

echo "Step 7: Check ONNX Runtime providers"
echo "----------------------------------------------------------------------"
docker logs "$CONTAINER_NAME" 2>&1 | grep -i "available.*provider" || echo "(No provider logs found yet)"
echo ""

echo "Step 8: Check SD4J initialization"
echo "----------------------------------------------------------------------"
docker logs "$CONTAINER_NAME" 2>&1 | grep -E "SD4J|Execution provider|GPU" | tail -10
echo ""

echo "Step 9: Verify GPU is accessible"
echo "----------------------------------------------------------------------"
docker exec "$CONTAINER_NAME" nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
echo ""

echo "Step 10: Test health endpoint"
echo "----------------------------------------------------------------------"
sleep 5
curl -s http://localhost:8080/actuator/health | jq . || echo "Health check failed"
echo ""

echo "Step 11: Test metrics endpoint"
echo "----------------------------------------------------------------------"
curl -s http://localhost:8080/api/langchain4j/metrics | jq . || echo "Metrics check failed"
echo ""

echo "======================================================================"
echo "Basic Tests Complete!"
echo "======================================================================"
echo ""
echo "Next Steps:"
echo ""
echo "1. Generate a test image:"
echo "   curl -X POST http://localhost:8080/api/langchain4j/image \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"prompt\": \"A robot reading a book\", \"style\": \"HAPPY\"}' \\"
echo "     --output test-robot.png"
echo ""
echo "2. Monitor GPU usage during generation:"
echo "   watch -n 1 nvidia-smi"
echo ""
echo "3. Check container logs:"
echo "   docker logs -f $CONTAINER_NAME"
echo ""
echo "4. Expected GPU behavior:"
echo "   - GPU utilization: 90-100% during inference"
echo "   - Generation time: 15-60 seconds (vs 3-4 minutes CPU)"
echo "   - No 'CPU fallback' warnings in logs"
echo ""
echo "======================================================================"
