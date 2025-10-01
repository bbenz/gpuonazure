#!/bin/bash

###############################################################################
# Download missing text_tokenizer for Stable Diffusion
###############################################################################

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MODEL_DIR="${1:-./models/stable-diffusion}"

echo -e "${YELLOW}→ Downloading text_tokenizer directory...${NC}"

mkdir -p "$MODEL_DIR/text_tokenizer"

# Download the custom CLIP tokenizer ONNX model
echo "Downloading custom_op_cliptok.onnx..."
curl -L "https://huggingface.co/onnx-community/stable-diffusion-v1-5-onnx/resolve/main/text_tokenizer/custom_op_cliptok.onnx" \
  -o "$MODEL_DIR/text_tokenizer/custom_op_cliptok.onnx"

# Download tokenizer configuration files
echo "Downloading tokenizer_config.json..."
curl -L "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer/tokenizer_config.json" \
  -o "$MODEL_DIR/text_tokenizer/tokenizer_config.json"

echo "Downloading vocab.json..."
curl -L "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer/vocab.json" \
  -o "$MODEL_DIR/text_tokenizer/vocab.json"

echo "Downloading merges.txt..."
curl -L "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer/merges.txt" \
  -o "$MODEL_DIR/text_tokenizer/merges.txt"

echo "Downloading special_tokens_map.json..."
curl -L "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer/special_tokens_map.json" \
  -o "$MODEL_DIR/text_tokenizer/special_tokens_map.json"

echo -e "${GREEN}✓ text_tokenizer downloaded successfully!${NC}"
echo ""
echo "Files in $MODEL_DIR/text_tokenizer:"
ls -lh "$MODEL_DIR/text_tokenizer"
