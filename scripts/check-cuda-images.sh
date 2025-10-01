# Testing if NVIDIA has Ubuntu 24.04 with CUDA 11.8
# If this works, it's the best solution!

# Try pulling various CUDA 11.8 images
docker pull nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu24.04 2>&1 | head -5 || echo "❌ Not available"
docker pull nvidia/cuda:11.8.0-runtime-ubuntu24.04 2>&1 | head -5 || echo "❌ Not available"

# Check what Ubuntu versions are available for CUDA 11.8
echo ""
echo "Checking Docker Hub for CUDA 11.8 Ubuntu 24.04 images..."
curl -s "https://registry.hub.docker.com/v2/repositories/nvidia/cuda/tags?page_size=100&name=11.8" | \
  jq -r '.results[].name' | grep ubuntu24 || echo "❌ No Ubuntu 24.04 images found for CUDA 11.8"
