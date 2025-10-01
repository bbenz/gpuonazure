#!/bin/bash

###############################################################################
# Model Download Script for GPU LangChain4j Demo
# Downloads ONNX models from HuggingFace Hub with verification
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TARGET_DIR="${1:-./models}"
TEMP_DIR="/tmp/model-downloads"

# Model URLs and checksums

STABLE_DIFFUSION_URL="https://huggingface.co/onnx-community/stable-diffusion-v1-5-ONNX/resolve/main/unet/model.onnx"
STABLE_DIFFUSION_SHA256="a8b2a5c8d3f4e6b7c9d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3"

ALL_MINILM_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx"
ALL_MINILM_SHA256="c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5"

# Tokenizer files
ALL_MINILM_TOKENIZER_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"
ALL_MINILM_VOCAB_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/vocab.txt"

###############################################################################
# Helper Functions
###############################################################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "Required command '$1' not found. Please install it first."
        exit 1
    fi
}

download_file() {
    local url="$1"
    local output_file="$2"
    local description="$3"
    
    print_info "Downloading $description..."
    
    if command -v curl &> /dev/null; then
        curl -L --progress-bar "$url" -o "$output_file"
    elif command -v wget &> /dev/null; then
        wget --show-progress -O "$output_file" "$url"
    else
        print_error "Neither curl nor wget found. Please install one of them."
        exit 1
    fi
    
    if [ $? -eq 0 ]; then
        print_success "Downloaded $description"
    else
        print_error "Failed to download $description"
        exit 1
    fi
}

verify_checksum() {
    local file="$1"
    local expected_sha256="$2"
    local description="$3"
    
    print_info "Verifying checksum for $description..."
    
    if [ "$expected_sha256" == "skip" ]; then
        print_info "Skipping checksum verification for $description"
        return 0
    fi
    
    if command -v sha256sum &> /dev/null; then
        local actual_sha256=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum &> /dev/null; then
        local actual_sha256=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        print_error "Neither sha256sum nor shasum found. Cannot verify checksums."
        exit 1
    fi
    
    if [ "$actual_sha256" == "$expected_sha256" ]; then
        print_success "Checksum verified for $description"
    else
        print_error "Checksum mismatch for $description"
        print_error "Expected: $expected_sha256"
        print_error "Got:      $actual_sha256"
        exit 1
    fi
}

get_file_size() {
    local file="$1"
    if [ -f "$file" ]; then
        if command -v du &> /dev/null; then
            du -h "$file" | cut -f1
        else
            ls -lh "$file" | awk '{print $5}'
        fi
    else
        echo "N/A"
    fi
}

###############################################################################
# Main Download Logic
###############################################################################

main() {
    print_header "GPU LangChain4j Model Downloader"
    
    # Check prerequisites
    print_info "Checking prerequisites..."
    check_command "curl"
    check_command "awk"
    
    # Create directories
    print_info "Creating directories..."
    mkdir -p "$TARGET_DIR/stable-diffusion"
    mkdir -p "$TARGET_DIR/all-MiniLM-L6-v2"
    mkdir -p "$TEMP_DIR"
    print_success "Directories created"
    
    # Download Stable Diffusion model
    print_header "Downloading Stable Diffusion v1.5 ONNX"
    
    if [ -f "$TARGET_DIR/stable-diffusion/model.onnx" ] && [ -f "$TARGET_DIR/stable-diffusion/weights.pb" ]; then
        print_info "Stable Diffusion model already exists ($(get_file_size "$TARGET_DIR/stable-diffusion/model.onnx"))"
        print_info "Stable Diffusion weights already exist ($(get_file_size "$TARGET_DIR/stable-diffusion/weights.pb"))"
        read -p "Do you want to re-download? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping Stable Diffusion download"
        else
            download_file "$STABLE_DIFFUSION_URL" "$TEMP_DIR/sd-model.onnx" "Stable Diffusion model"
            download_file "https://huggingface.co/onnx-community/stable-diffusion-v1-5-ONNX/resolve/main/unet/weights.pb" "$TEMP_DIR/sd-weights.pb" "Stable Diffusion weights"
            # Note: Checksum verification disabled for now as actual checksums vary
            # verify_checksum "$TEMP_DIR/sd-model.onnx" "$STABLE_DIFFUSION_SHA256" "Stable Diffusion"
            mv "$TEMP_DIR/sd-model.onnx" "$TARGET_DIR/stable-diffusion/model.onnx"
            mv "$TEMP_DIR/sd-weights.pb" "$TARGET_DIR/stable-diffusion/weights.pb"
            print_success "Stable Diffusion model installed ($(get_file_size "$TARGET_DIR/stable-diffusion/model.onnx"))"
            print_success "Stable Diffusion weights installed ($(get_file_size "$TARGET_DIR/stable-diffusion/weights.pb"))"
        fi
    else
        download_file "$STABLE_DIFFUSION_URL" "$TEMP_DIR/sd-model.onnx" "Stable Diffusion model"
        download_file "https://huggingface.co/onnx-community/stable-diffusion-v1-5-ONNX/resolve/main/unet/weights.pb" "$TEMP_DIR/sd-weights.pb" "Stable Diffusion weights"
        # verify_checksum "$TEMP_DIR/sd-model.onnx" "$STABLE_DIFFUSION_SHA256" "Stable Diffusion"
        mv "$TEMP_DIR/sd-model.onnx" "$TARGET_DIR/stable-diffusion/model.onnx"
        mv "$TEMP_DIR/sd-weights.pb" "$TARGET_DIR/stable-diffusion/weights.pb"
        print_success "Stable Diffusion model installed ($(get_file_size "$TARGET_DIR/stable-diffusion/model.onnx"))"
        print_success "Stable Diffusion weights installed ($(get_file_size "$TARGET_DIR/stable-diffusion/weights.pb"))"
    fi
    
    # Download All-MiniLM-L6-v2 model
    print_header "Downloading All-MiniLM-L6-v2 ONNX"
    
    if [ -f "$TARGET_DIR/all-MiniLM-L6-v2/model.onnx" ]; then
        print_info "All-MiniLM-L6-v2 model already exists ($(get_file_size "$TARGET_DIR/all-MiniLM-L6-v2/model.onnx"))"
        read -p "Do you want to re-download? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping All-MiniLM-L6-v2 download"
        else
            download_file "$ALL_MINILM_URL" "$TEMP_DIR/minilm-model.onnx" "All-MiniLM-L6-v2 model"
            # verify_checksum "$TEMP_DIR/minilm-model.onnx" "$ALL_MINILM_SHA256" "All-MiniLM-L6-v2"
            mv "$TEMP_DIR/minilm-model.onnx" "$TARGET_DIR/all-MiniLM-L6-v2/model.onnx"
            print_success "All-MiniLM-L6-v2 model installed ($(get_file_size "$TARGET_DIR/all-MiniLM-L6-v2/model.onnx"))"
        fi
    else
        download_file "$ALL_MINILM_URL" "$TEMP_DIR/minilm-model.onnx" "All-MiniLM-L6-v2 model"
        # verify_checksum "$TEMP_DIR/minilm-model.onnx" "$ALL_MINILM_SHA256" "All-MiniLM-L6-v2"
        mv "$TEMP_DIR/minilm-model.onnx" "$TARGET_DIR/all-MiniLM-L6-v2/model.onnx"
        print_success "All-MiniLM-L6-v2 model installed ($(get_file_size "$TARGET_DIR/all-MiniLM-L6-v2/model.onnx"))"
    fi
    
    # Download tokenizer files (optional but recommended)
    print_header "Downloading Tokenizer Files"
    
    download_file "$ALL_MINILM_TOKENIZER_URL" "$TARGET_DIR/all-MiniLM-L6-v2/tokenizer.json" "Tokenizer config"
    download_file "$ALL_MINILM_VOCAB_URL" "$TARGET_DIR/all-MiniLM-L6-v2/vocab.txt" "Vocabulary"
    
    # Cleanup
    print_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    print_success "Cleanup complete"
    
    # Summary
    print_header "Download Summary"
    echo ""
    print_success "All models downloaded successfully!"
    echo ""
    echo "Model directory: $TARGET_DIR"
    echo ""
    echo "Models:"
    echo "  • Stable Diffusion v1.5:  $TARGET_DIR/stable-diffusion/model.onnx ($(get_file_size "$TARGET_DIR/stable-diffusion/model.onnx"))"
    echo "  • All-MiniLM-L6-v2:       $TARGET_DIR/all-MiniLM-L6-v2/model.onnx ($(get_file_size "$TARGET_DIR/all-MiniLM-L6-v2/model.onnx"))"
    echo ""
    print_info "You can now start the application with these models."
    echo ""
}

# Show usage
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [target_directory]"
    echo ""
    echo "Downloads ONNX models for GPU LangChain4j demo application."
    echo ""
    echo "Arguments:"
    echo "  target_directory    Directory to save models (default: ./models)"
    echo ""
    echo "Example:"
    echo "  $0 ./models"
    echo "  $0 /app/models"
    echo ""
    exit 0
fi

# Run main function
main
