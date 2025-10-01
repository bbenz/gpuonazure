#!/bin/bash

# Download missing SD4J models (text_encoder and vae_decoder)
# You already have the U-Net model, so we'll just download what's missing

set -e

BASE_URL="https://huggingface.co/onnx-community/stable-diffusion-v1-5-ONNX/resolve/main"
MODEL_DIR="models/stable-diffusion"

echo "🔍 Downloading missing Stable Diffusion models..."
echo "You already have: U-Net (model.onnx + weights.pb)"
echo "Downloading: Text Encoder + VAE Decoder"
echo ""

# Text Encoder (~492MB)
echo "📥 Downloading Text Encoder (492MB)..."
mkdir -p "$MODEL_DIR/text_encoder"
curl -L "$BASE_URL/text_encoder/model.onnx" -o "$MODEL_DIR/text_encoder/model.onnx"
echo "✅ Text Encoder downloaded"

# VAE Decoder (~198MB)
echo "📥 Downloading VAE Decoder (198MB)..."
mkdir -p "$MODEL_DIR/vae_decoder"
curl -L "$BASE_URL/vae_decoder/model.onnx" -o "$MODEL_DIR/vae_decoder/model.onnx"
echo "✅ VAE Decoder downloaded"

# Safety Checker (~1.2GB, optional)
read -p "Download Safety Checker? (~1.2GB, optional NSFW filter) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📥 Downloading Safety Checker (1.2GB)..."
    mkdir -p "$MODEL_DIR/safety_checker"
    curl -L "$BASE_URL/safety_checker/model.onnx" -o "$MODEL_DIR/safety_checker/model.onnx"
    echo "✅ Safety Checker downloaded"
else
    echo "⏭️  Skipping Safety Checker"
fi

# Move existing U-Net files to proper location
echo ""
echo "📁 Organizing existing U-Net model..."
mv "$MODEL_DIR/model.onnx" "$MODEL_DIR/unet/model.onnx"
mv "$MODEL_DIR/weights.pb" "$MODEL_DIR/unet/weights.pb"
rm -f "$MODEL_DIR/model_with_weights.onnx"  # Remove empty file
echo "✅ U-Net moved to unet/ subdirectory"

echo ""
echo "🎉 Model setup complete!"
echo ""
echo "Final structure:"
tree -L 2 "$MODEL_DIR" 2>/dev/null || find "$MODEL_DIR" -type f -name "*.onnx" -o -name "*.pb"

echo ""
echo "✨ Ready to test! Run:"
echo "   mvn spring-boot:run"
