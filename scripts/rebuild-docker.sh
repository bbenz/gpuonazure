#!/bin/bash
set -e

echo "🔧 Fixing GLIBC compatibility issue..."
echo "   Rebuilding with Ubuntu 24.04 (GLIBC 2.39)"
echo ""

cd /mnt/c/githublocal/gpuonazure

# Clean up old containers and images
echo "🧹 Cleaning up old containers..."
docker stop gpu-langchain4j 2>/dev/null || true
docker rm gpu-langchain4j 2>/dev/null || true

echo "🧹 Removing old image to free space..."
docker rmi gpu-langchain4j-demo:latest 2>/dev/null || true

# Choose build method
echo ""
echo "Choose Docker image type:"
echo "1) Slim version (~1.5GB, requires volume mount) - RECOMMENDED"
echo "2) Full version (~14GB, models baked in)"
echo ""
read -p "Enter choice (1 or 2): " choice

if [ "$choice" == "1" ]; then
    echo ""
    echo "🐳 Building SLIM version with Ubuntu 24.04..."
    docker build -f Dockerfile.slim -t gpu-langchain4j-demo:slim .
    
    echo ""
    echo "📊 Image size:"
    docker images gpu-langchain4j-demo:slim
    
    echo ""
    echo "🚀 Starting container with volume mount..."
    docker run -d --gpus all -p 8080:8080 \
      -v /mnt/c/githublocal/gpuonazure/models:/app/models \
      --name gpu-langchain4j \
      gpu-langchain4j-demo:slim
    
    IMAGE_NAME="gpu-langchain4j-demo:slim"
else
    echo ""
    echo "🐳 Building FULL version with Ubuntu 24.04..."
    echo "⚠️  This will create a ~14GB image and may take 10-15 minutes"
    docker build -t gpu-langchain4j-demo:latest .
    
    echo ""
    echo "📊 Image size:"
    docker images gpu-langchain4j-demo:latest
    
    echo ""
    echo "🚀 Starting container (models baked in)..."
    docker run -d --gpus all -p 8080:8080 \
      --name gpu-langchain4j \
      gpu-langchain4j-demo:latest
    
    IMAGE_NAME="gpu-langchain4j-demo:latest"
fi

echo ""
echo "⏳ Waiting for startup (20 seconds)..."
sleep 20

echo ""
echo "📋 Checking logs for GLIBC errors..."
docker logs gpu-langchain4j 2>&1 | grep -i "glibc\|glibcxx" || echo "✅ No GLIBC errors found!"

echo ""
echo "🔍 Verifying library compatibility..."
docker exec gpu-langchain4j bash -c "ldd /app/libortextensions.so | head -10"

echo ""
echo "✅ Testing health endpoint..."
sleep 10
curl -s http://localhost:8080/actuator/health | head -3 || echo "⚠️  App may still be starting..."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Container is running!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Image: $IMAGE_NAME"
echo "Web UI: http://localhost:8080"
echo "Logs: docker logs -f gpu-langchain4j"
echo ""
echo "Test command:"
echo "curl -X POST http://localhost:8080/api/langchain4j/image \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"prompt\": \"A happy robot\", \"style\": \"HAPPY\"}' \\"
echo "  --output test.png"
echo ""
