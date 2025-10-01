#!/bin/bash
# GPU LangChain4j Monitoring Dashboard
# Usage: ./monitor.sh [build|run|gpu|all]

MODE=${1:-all}

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear

case $MODE in
  build)
    echo -e "${BLUE}=== Docker Build Monitor ===${NC}"
    echo ""
    if [ -f docker-build-ubuntu24-v2.log ]; then
      echo "Last 30 lines of build log:"
      tail -30 docker-build-ubuntu24-v2.log
      echo ""
      echo -e "${YELLOW}Press Ctrl+C to exit, watching build log...${NC}"
      tail -f docker-build-ubuntu24-v2.log
    else
      echo "No build log found. Start build with:"
      echo "  docker build -f Dockerfile.ubuntu24 -t gpu-langchain4j-demo:ubuntu24-v2 . 2>&1 | tee docker-build-ubuntu24-v2.log"
    fi
    ;;
    
  run)
    echo -e "${BLUE}=== Container Logs Monitor ===${NC}"
    echo ""
    if docker ps | grep -q gpu-langchain4j; then
      echo -e "${GREEN}✓ Container is running${NC}"
      echo ""
      echo "Recent logs:"
      docker logs --tail 50 gpu-langchain4j
      echo ""
      echo -e "${YELLOW}Following logs... Press Ctrl+C to exit${NC}"
      echo ""
      docker logs -f gpu-langchain4j
    else
      echo "Container not running. Start with:"
      echo "  docker run -d --gpus all -p 8080:8080 \\"
      echo "    -v \$(pwd)/models:/app/models \\"
      echo "    -v \$(pwd)/text_tokenizer:/app/text_tokenizer \\"
      echo "    -e ENABLE_GPU=true \\"
      echo "    --name gpu-langchain4j \\"
      echo "    gpu-langchain4j-demo:ubuntu24-v2"
    fi
    ;;
    
  gpu)
    echo -e "${BLUE}=== GPU Utilization Monitor ===${NC}"
    echo ""
    echo "GPU Status:"
    nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader
    echo ""
    echo -e "${YELLOW}Monitoring GPU every 2 seconds... Press Ctrl+C to exit${NC}"
    echo ""
    watch -n 2 nvidia-smi
    ;;
    
  all)
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   GPU LangChain4j Status Dashboard${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Docker Images
    echo -e "${GREEN}=== Docker Images ===${NC}"
    docker images | grep -E "REPOSITORY|gpu-langchain4j"
    echo ""
    
    # Container Status
    echo -e "${GREEN}=== Container Status ===${NC}"
    if docker ps | grep -q gpu-langchain4j; then
      echo -e "${GREEN}✓ Container is running${NC}"
      docker ps | grep -E "CONTAINER|gpu-langchain4j"
    else
      echo -e "${YELLOW}⚠ Container is not running${NC}"
    fi
    echo ""
    
    # GPU Status
    echo -e "${GREEN}=== GPU Status ===${NC}"
    nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader
    echo ""
    
    # Application Status
    if docker ps | grep -q gpu-langchain4j; then
      echo -e "${GREEN}=== Application Status ===${NC}"
      
      # Check if started
      if docker logs gpu-langchain4j 2>&1 | grep -q "Started GpuLangchain4jDemoApplication"; then
        echo -e "${GREEN}✓ Application started${NC}"
      else
        echo -e "${YELLOW}⚠ Application still starting...${NC}"
      fi
      
      # Check ONNX Runtime providers
      echo ""
      echo "ONNX Runtime Providers:"
      docker logs gpu-langchain4j 2>&1 | grep "Available ONNX Runtime providers" | tail -1
      
      # Check SD4J status
      echo ""
      echo "SD4J Status:"
      docker logs gpu-langchain4j 2>&1 | grep -E "SD4J initialized|Execution provider" | tail -2
      
      # Check for errors
      echo ""
      ERROR_COUNT=$(docker logs gpu-langchain4j 2>&1 | grep -i "error" | wc -l)
      if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "${YELLOW}⚠ $ERROR_COUNT errors found in logs${NC}"
        echo "Recent errors:"
        docker logs gpu-langchain4j 2>&1 | grep -i "error" | tail -3
      else
        echo -e "${GREEN}✓ No errors in logs${NC}"
      fi
    fi
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo "Quick commands:"
    echo "  ./monitor.sh build  - Monitor Docker build"
    echo "  ./monitor.sh run    - Follow container logs"
    echo "  ./monitor.sh gpu    - Monitor GPU utilization"
    echo "  ./monitor.sh all    - Show this dashboard (default)"
    echo ""
    echo "Test endpoints:"
    echo "  curl http://localhost:8080/actuator/health"
    echo "  curl http://localhost:8080/api/langchain4j/metrics"
    ;;
    
  *)
    echo "Usage: $0 [build|run|gpu|all]"
    exit 1
    ;;
esac
