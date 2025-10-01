#!/bin/bash
# Test GPU performance during image generation

echo "=========================================="
echo "GPU Performance Test"
echo "=========================================="
echo ""

# Start GPU monitoring in background
echo "Starting GPU monitoring..."
docker exec gpu-langchain4j nvidia-smi dmon -s u -c 120 > gpu-monitor.log 2>&1 &
MONITOR_PID=$!

sleep 2

# Generate test image
echo ""
echo "Generating test image (watercolor sunset)..."
echo "Expected: 60-120 seconds with GPU, 180-240 seconds with CPU"
echo ""

START_TIME=$(date +%s)

curl -X POST http://localhost:8080/api/langchain4j/image \
  -H "Content-Type: application/json" \
  -d '{"prompt": "watercolor sunset over mountains", "style": "CLASSIC"}' \
  --output test-sunset.png \
  -w "\nHTTP Status: %{http_code}\n" \
  2>&1

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Results:"
echo "=========================================="
echo "Generation time: ${DURATION} seconds"
echo "Image saved to: test-sunset.png"
echo ""

# Stop monitoring
kill $MONITOR_PID 2>/dev/null

# Analyze GPU usage
if [ -f gpu-monitor.log ]; then
    echo "GPU Utilization Summary:"
    echo "----------------------------------------"
    
    # Show average GPU utilization (excluding header lines)
    AVG_GPU=$(grep -v "#" gpu-monitor.log | awk '{sum+=$2; count++} END {if(count>0) print sum/count; else print 0}')
    MAX_GPU=$(grep -v "#" gpu-monitor.log | awk '{max=0} {if($2>max) max=$2} END {print max}')
    
    echo "Average GPU Utilization: ${AVG_GPU}%"
    echo "Peak GPU Utilization: ${MAX_GPU}%"
    echo ""
    
    if (( $(echo "$AVG_GPU > 50" | bc -l) )); then
        echo "✓ GPU is being utilized effectively!"
    else
        echo "⚠ GPU utilization is lower than expected"
    fi
fi

echo ""
echo "Performance Comparison:"
echo "  GPU target: 15-60 seconds"
echo "  CPU fallback: 180-240 seconds"
echo "  Your time: ${DURATION} seconds"
echo ""

if [ $DURATION -lt 90 ]; then
    echo "✓ Performance indicates GPU acceleration is working!"
elif [ $DURATION -lt 150 ]; then
    echo "⚠ Performance is between GPU and CPU - check GPU utilization"
else
    echo "✗ Performance suggests CPU fallback - GPU may not be working"
fi

echo ""
echo "Check docker logs for CUDA initialization:"
docker logs gpu-langchain4j 2>&1 | grep -E "(CUDA|GPU|Execution provider)" | tail -10
