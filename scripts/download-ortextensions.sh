#!/bin/bash

# Build ONNX Runtime Extensions library for SD4J CLIP tokenizer
# SD4J requires this for the custom CLIP tokenizer operator

set -e

echo "� Building ONNX Runtime Extensions for SD4J..."
echo ""

# Detect OS
OS=$(uname -s)
ARCH=$(uname -m)

if [[ "$OS" == "Linux" ]]; then
    LIB_NAME="libortextensions.so"
elif [[ "$OS" == "Darwin" ]]; then
    LIB_NAME="libortextensions.dylib"
else
    echo "❌ Unsupported OS: $OS (Windows users: see instructions below)"
    exit 1
fi

echo "Target: $OS $ARCH"
echo "Library: $LIB_NAME"
echo ""

# Check if library already exists
if [[ -f "./$LIB_NAME" ]]; then
    echo "✅ Library already exists: ./$LIB_NAME"
    ls -lh "./$LIB_NAME"
    echo ""
    echo "Delete it and re-run this script to rebuild."
    exit 0
fi

# Check dependencies
echo "Checking dependencies..."
if ! command -v cmake &> /dev/null; then
    echo "❌ cmake not found. Install with:"
    echo "   Ubuntu/Debian: sudo apt-get install cmake build-essential"
    echo "   macOS: brew install cmake"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "❌ git not found. Please install git."
    exit 1
fi

echo "✓ cmake found: $(cmake --version | head -1)"
echo "✓ git found"
echo ""

# Clone onnxruntime-extensions
TEMP_DIR=$(mktemp -d)
echo "Cloning onnxruntime-extensions to: $TEMP_DIR"
cd "$TEMP_DIR"

git clone https://github.com/microsoft/onnxruntime-extensions.git
cd onnxruntime-extensions

echo ""
echo "Building onnxruntime-extensions (this may take 5-10 minutes)..."
./build_lib.sh --config Release --update --build --parallel

# Find the built library (may have version suffix like .so.0.15.0)
if [[ "$OS" == "Linux" ]]; then
    BUILT_LIB=$(find build -name "libortextensions.so*" -type f | head -1)
elif [[ "$OS" == "Darwin" ]]; then
    BUILT_LIB=$(find build -name "libortextensions.dylib*" -type f | head -1)
fi

if [[ -z "$BUILT_LIB" ]]; then
    echo "❌ Build succeeded but library not found!"
    echo "Looking for library..."
    find build -name "*ortextensions*" -type f
    exit 1
fi

echo ""
echo "✅ Build successful!"
echo "Built library: $BUILT_LIB"

# Copy to project root
OLDPWD=$(dirs -l +1)
cp "$BUILT_LIB" "$OLDPWD/$LIB_NAME"

# Cleanup
cd "$OLDPWD"
rm -rf "$TEMP_DIR"

echo ""
echo "✅ Installed: ./$LIB_NAME"
ls -lh "./$LIB_NAME"

if [[ "$OS" == "Linux" ]]; then
    chmod +x "./$LIB_NAME"
    echo ""
    echo "Library dependencies:"
    ldd "./$LIB_NAME" 2>&1 | head -20 || echo "(Unable to check dependencies)"
fi

echo ""
echo "🎉 Done! You can now run:"
echo "   mvn spring-boot:run"
