#!/bin/bash
# GPU Image Generation Performance Test
# Created: September 30, 2025
# Tests GPU vs CPU performance and monitors GPU utilization

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "======================================================================"
echo "GPU Image Generation Performance Test"
echo "======================================================================"
echo ""

# Test prompts
PROMPTS=(
    '{"prompt": "A happy robot reading a book in a library", "style": "HAPPY"}'
    '{"prompt": "A futuristic cityscape at sunset", "style": "CINEMATIC"}'
    '{"prompt": "A cute cat wearing glasses", "style": "HAPPY"}'
)

PROMPT_NAMES=(
    "robot-library"
    "city-sunset"
    "cat-glasses"
)

echo "Test Configuration:"
echo "- Number of test images: ${#PROMPTS[@]}"
echo "- Container: gpu-langchain4j"
echo "- Endpoint: http://localhost:8080/api/langchain4j/image"
echo ""

# Create test output directory
mkdir -p test-outputs
cd test-outputs

echo "======================================================================"
echo "Starting GPU Performance Tests"
echo "======================================================================"
echo ""

for i in "${!PROMPTS[@]}"; do
    PROMPT="${PROMPTS[$i]}"
    NAME="${PROMPT_NAMES[$i]}"
    OUTPUT="test-${i}-${NAME}.png"
    
    echo "----------------------------------------------------------------------"
    echo "Test $((i+1))/${#PROMPTS[@]}: Generating '$NAME'"
    echo "----------------------------------------------------------------------"
    
    # Show GPU status before generation
    echo "GPU status before generation:"
    nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits
    echo ""
    
    # Start GPU monitoring in background
    echo "Starting GPU monitor (will run for 120 seconds)..."
    nvidia-smi --query-gpu=timestamp,utilization.gpu,memory.used --format=csv,noheader > "gpu-log-${NAME}.csv" &
    MONITOR_PID=$!
    
    # Record start time
    START_TIME=$(date +%s)
    
    echo "Sending generation request..."
    HTTP_CODE=$(curl -X POST http://localhost:8080/api/langchain4j/image \
        -H "Content-Type: application/json" \
        -d "$PROMPT" \
        --output "$OUTPUT" \
        --write-out "%{http_code}" \
        --max-time 300 \
        -s)
    
    # Record end time
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Stop GPU monitoring
    kill $MONITOR_PID 2>/dev/null || true
    wait $MONITOR_PID 2>/dev/null || true
    
    # Check result
    if [ "$HTTP_CODE" -eq 200 ] && [ -f "$OUTPUT" ]; then
        FILE_SIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')
        echo -e "${GREEN}✓${NC} Generation successful!"
        echo "   - Duration: ${DURATION} seconds"
        echo "   - Output file: $OUTPUT ($FILE_SIZE)"
        
        # Analyze GPU utilization
        if [ -f "gpu-log-${NAME}.csv" ]; then
            AVG_GPU=$(awk -F',' '{sum+=$2; count++} END {print sum/count}' "gpu-log-${NAME}.csv")
            MAX_GPU=$(awk -F',' '{if($2>max) max=$2} END {print max}' "gpu-log-${NAME}.csv")
            echo "   - Average GPU utilization: ${AVG_GPU}%"
            echo "   - Peak GPU utilization: ${MAX_GPU}%"
            
            # Check if GPU was actually used (>10% utilization)
            if (( $(echo "$AVG_GPU > 10" | bc -l) )); then
                echo -e "   ${GREEN}✓ GPU was actively used${NC}"
            else
                echo -e "   ${YELLOW}⚠ GPU utilization low - may be running on CPU${NC}"
            fi
        fi
    else
        echo -e "${RED}✗${NC} Generation failed (HTTP $HTTP_CODE)"
        echo "   Check container logs: docker logs gpu-langchain4j"
    fi
    
    echo ""
    sleep 5  # Cool down between tests
done

echo "======================================================================"
echo "Test Summary"
echo "======================================================================"
echo ""
echo "Generated images:"
ls -lh test-*.png 2>/dev/null || echo "No images generated"
echo ""

echo "GPU utilization logs:"
ls -lh gpu-log-*.csv 2>/dev/null || echo "No GPU logs"
echo ""

echo "View images:"
for img in test-*.png; do
    if [ -f "$img" ]; then
        echo "  - $img"
    fi
done
echo ""

echo "======================================================================"
echo "Performance Analysis"
echo "======================================================================"
echo ""

# Calculate average generation time
if ls test-*.png >/dev/null 2>&1; then
    TOTAL_IMAGES=$(ls test-*.png | wc -l)
    echo "Successfully generated: $TOTAL_IMAGES images"
    echo ""
    
    # Check container logs for actual generation times
    echo "Checking container logs for generation times..."
    docker logs gpu-langchain4j 2>&1 | grep -E "Generation time|Generated image" | tail -$((TOTAL_IMAGES * 2))
    echo ""
    
    echo "Expected performance:"
    echo "  - GPU mode: 15-60 seconds per image"
    echo "  - CPU mode: 180-240 seconds per image"
    echo ""
    
    # Analyze if GPU was used
    if ls gpu-log-*.csv >/dev/null 2>&1; then
        OVERALL_AVG=$(cat gpu-log-*.csv | awk -F',' '{sum+=$2; count++} END {print sum/count}')
        if (( $(echo "$OVERALL_AVG > 50" | bc -l) )); then
            echo -e "${GREEN}✓ GPU was heavily utilized (${OVERALL_AVG}% average)${NC}"
            echo "  This indicates successful GPU acceleration!"
        elif (( $(echo "$OVERALL_AVG > 10" | bc -l) )); then
            echo -e "${YELLOW}⚠ GPU was partially utilized (${OVERALL_AVG}% average)${NC}"
            echo "  GPU may be used but not optimally"
        else
            echo -e "${RED}✗ GPU was barely used (${OVERALL_AVG}% average)${NC}"
            echo "  Application likely fell back to CPU mode"
            echo ""
            echo "Check container logs for errors:"
            echo "  docker logs gpu-langchain4j 2>&1 | grep -E 'CUDA|GPU|fallback'"
        fi
    fi
else
    echo "No images were generated. Check for errors:"
    echo "  docker logs gpu-langchain4j | tail -50"
fi

echo ""
echo "======================================================================"
echo "Next Steps:"
echo "======================================================================"
echo ""
echo "1. View generated images in: $(pwd)"
echo ""
echo "2. Analyze GPU logs:"
echo "   for log in gpu-log-*.csv; do"
echo "     echo \"\\n=== \$log ===\";"
echo "     cat \"\$log\" | column -t -s ',';"
echo "   done"
echo ""
echo "3. Check application logs:"
echo "   docker logs gpu-langchain4j | grep -E 'Execution provider|GPU'"
echo ""
echo "4. If GPU wasn't used, check for errors:"
echo "   docker logs gpu-langchain4j 2>&1 | grep -i error"
echo ""
echo "======================================================================"
