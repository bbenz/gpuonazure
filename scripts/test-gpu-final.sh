#!/bin/bash
set -e

echo "🚀 Testing GPU-Accelerated Image Generation"
echo "==========================================="
echo ""

# Start container
echo "Starting container..."
docker run -d --gpus all -p 8080:8080 \
  -v /mnt/c/githublocal/gpuonazure/models:/app/models \
  -v /mnt/c/githublocal/gpuonazure/text_tokenizer:/app/text_tokenizer \
  -e ENABLE_GPU=true \
  --name gpu-langchain4j \
  gpu-langchain4j-demo:gpu-fixed

echo "Waiting 20 seconds for startup..."
sleep 20

echo ""
echo "📊 Checking GPU configuration..."
docker logs gpu-langchain4j 2>&1 | grep -i "gpu enabled"

echo ""
echo "📊 Checking SD4J initialization..."
docker logs gpu-langchain4j 2>&1 | grep -i "execution provider"

echo ""
echo "🎨 Generating test image (this will take 15-60 seconds on GPU)..."
time curl -X POST http://localhost:8080/api/langchain4j/image \
  -H "Content-Type: application/json" \
  -d '{"prompt": "A friendly robot assistant", "style": "HAPPY"}' \
  --output test-gpu-image.png

echo ""
echo "✅ Image saved as test-gpu-image.png"
echo ""
echo "📊 GPU utilization during generation:"
docker exec gpu-langchain4j nvidia-smi --query-gpu=name,utilization.gpu,memory.used --format=csv,noheader

echo ""
echo "🎉 Test complete! Check the logs above for 'CUDA' execution provider."
