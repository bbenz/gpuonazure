#!/bin/bash
set -e

echo "🧪 GPU-Accelerated Image Generator Test Script"
echo "================================================"
echo ""

# Stop and remove old container
echo "🧹 Cleaning up old container..."
docker stop gpu-langchain4j 2>/dev/null || true
docker rm gpu-langchain4j 2>/dev/null || true

# Run container with CUDA 11.8
echo ""
echo "🚀 Starting container with CUDA 11.8 + cuDNN 8..."
docker run -d --gpus all -p 8080:8080 \
  -v /mnt/c/githublocal/gpuonazure/models:/app/models \
  -v /mnt/c/githublocal/gpuonazure/text_tokenizer:/app/text_tokenizer \
  --name gpu-langchain4j \
  gpu-langchain4j-demo:cudnn-slim

echo ""
echo "⏳ Waiting for application startup (15 seconds)..."
sleep 15

echo ""
echo "📊 Step 1: Verify cuDNN 8 is available"
echo "========================================"
docker exec gpu-langchain4j bash -c "ldconfig -p | grep -i cudnn"

echo ""
echo "📊 Step 2: Check ONNX Runtime CUDA provider dependencies"
echo "========================================================"
echo "Looking for 'not found' errors (should be none):"
docker exec gpu-langchain4j bash -c "ldd /tmp/onnxruntime-java*/libonnxruntime_providers_cuda.so 2>&1 | grep 'not found'" || echo "✅ All dependencies found!"

echo ""
echo "📊 Step 3: Check application logs for CUDA initialization"
echo "=========================================================="
docker logs gpu-langchain4j 2>&1 | grep -i "cuda provider"

echo ""
echo "📊 Step 4: Test health endpoint"
echo "================================"
curl -s http://localhost:8080/actuator/health | jq '.'

echo ""
echo "📊 Step 5: Monitor GPU during image generation"
echo "==============================================="
echo "Open a second terminal and run: watch -n 1 nvidia-smi"
echo ""
echo "Generating test image in 5 seconds..."
sleep 5

echo ""
echo "🎨 Generating image..."
START_TIME=$(date +%s)

curl -X POST http://localhost:8080/api/langchain4j/image \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "A futuristic robot artist painting on a canvas in a cyberpunk studio",
    "style": "EXCITED"
  }' \
  --output test-robot.png \
  --progress-bar

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "✅ Image generated in ${DURATION} seconds!"
echo "📁 Saved as: test-robot.png"
echo ""

echo "📊 Step 6: Check GPU utilization during generation"
echo "==================================================="
docker exec gpu-langchain4j nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total --format=csv

echo ""
echo "🎉 Test Complete!"
echo ""
echo "Expected results with GPU:"
echo "  - Generation time: 15-60 seconds (vs 3-4 minutes on CPU)"
echo "  - GPU utilization: 90-100% during generation"
echo "  - GPU memory: 3-8GB used"
echo "  - Logs should show: '✓ CUDA provider configured successfully'"
echo ""
echo "To view logs: docker logs gpu-langchain4j"
echo "To stop: docker stop gpu-langchain4j"
