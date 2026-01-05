#!/bin/bash

# Script to install whisper.cpp CLI for Linux STT support
# This builds whisper.cpp from source with CPU-only support (no GPU)

set -e  # Exit on error

echo "================================================"
echo "Installing whisper.cpp CLI for Linux STT"
echo "================================================"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "❌ Error: Please do NOT run this script with sudo"
    echo ""
    echo "This script will ask for sudo password when needed for system packages."
    echo "Run it as your regular user:"
    echo "  ./install_whisper_cpp.sh"
    exit 1
fi

# Check if script is run from Flutter project directory
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: pubspec.yaml not found"
    echo "Please run this script from your Flutter project root directory"
    exit 1
fi

echo "✅ Flutter project detected"
echo ""

# Check system dependencies
echo "Checking system dependencies..."
echo ""

MISSING_PACKAGES=()

# Check for pulseaudio-utils
if ! dpkg -l | grep -q "pulseaudio-utils"; then
    echo "⚠️  pulseaudio-utils is not installed (required for audio recording)"
    MISSING_PACKAGES+=("pulseaudio-utils")
else
    echo "✅ pulseaudio-utils is installed"
fi

# whisper.cpp CLI doesn't need libmpv - only basic build tools

# If packages are missing, offer to install them
if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo ""
    echo "================================================"
    echo "Missing System Dependencies"
    echo "================================================"
    echo ""
    echo "The following packages need to be installed:"
    for pkg in "${MISSING_PACKAGES[@]}"; do
        echo "  - $pkg"
    done
    echo ""

    # Check if we can ask for input
    if [ -t 0 ]; then
        read -p "Would you like to install them now? (requires sudo password) [y/n]: " install_choice < /dev/tty
    else
        echo "Running in non-interactive mode. Please install packages manually:"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install ${MISSING_PACKAGES[*]}"
        exit 1
    fi

    if [[ "$install_choice" == "y" || "$install_choice" == "Y" ]]; then
        echo ""
        echo "Installing system packages (you may be prompted for sudo password)..."
        sudo apt-get update
        sudo apt-get install -y ${MISSING_PACKAGES[*]}

        echo ""
        echo "✅ System packages installed successfully"
    else
        echo ""
        echo "Setup cancelled. Please install the required packages manually:"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install ${MISSING_PACKAGES[*]}"
        echo ""
        echo "Then run this script again."
        exit 1
    fi
fi

echo ""
echo "================================================"
echo "Building whisper.cpp from source"
echo "================================================"
echo ""

# Set installation directory
INSTALL_DIR="/tmp/whisper.cpp"

# Remove existing installation if present
if [ -d "$INSTALL_DIR" ]; then
    echo "🗑️  Removing existing whisper.cpp installation..."
    rm -rf "$INSTALL_DIR"
fi

# Clone whisper.cpp repository
echo "📥 Cloning whisper.cpp repository..."
git clone https://github.com/ggerganov/whisper.cpp.git "$INSTALL_DIR"

# Navigate to the directory
cd "$INSTALL_DIR"

echo ""
echo "🔨 Building whisper.cpp (CPU-only, no GPU)..."
echo "This may take a few minutes..."
echo ""

# Create build directory
mkdir -p build
cd build

# Configure with cmake (explicitly disable GPU support)
echo "⚙️  Configuring build with cmake (CPU-only mode)..."
cmake .. -DGGML_CUDA=OFF -DGGML_VULKAN=OFF -DGGML_METAL=OFF -DGGML_OPENCL=OFF

# Build the project
echo "🔧 Compiling..."
cmake --build . --config Release

echo ""
echo "✅ Build completed successfully!"
echo ""

# Verify the executable exists
WHISPER_CLI="$INSTALL_DIR/build/bin/whisper-cli"
if [ ! -f "$WHISPER_CLI" ]; then
    echo "❌ Error: whisper-cli executable not found"
    echo "Build may have failed. Check the output above for errors."
    exit 1
fi

echo "✅ whisper-cli executable found at: $WHISPER_CLI"
echo ""

echo "================================================"
echo "Whisper Model Setup"
echo "================================================"
echo ""

# Create model directory
MODEL_DIR="$HOME/Dokumente/whisper_models"
mkdir -p "$MODEL_DIR"

echo "Model directory: $MODEL_DIR"
echo ""

# Check if any model already exists
EXISTING_MODELS=($(find "$MODEL_DIR" -name "ggml-*.bin" 2>/dev/null))

if [ ${#EXISTING_MODELS[@]} -gt 0 ]; then
    echo "✅ Found existing Whisper model(s):"
    for model in "${EXISTING_MODELS[@]}"; do
        file_size=$(du -h "$model" | cut -f1)
        echo "   - $(basename $model) ($file_size)"
    done
    echo ""
    read -p "Would you like to download an additional model? (y/n): " download_choice

    if [[ "$download_choice" != "y" && "$download_choice" != "Y" ]]; then
        echo ""
        echo "Skipping model download."
        echo ""
        echo "================================================"
        echo "🎉 Setup complete!"
        echo "================================================"
        echo ""
        echo "You can now run the Flutter app with:"
        echo "  flutter run -d linux"
        echo ""
        exit 0
    fi
fi

echo "Available models:"
echo "  1) tiny   (~75 MB)  - Fastest, lowest quality"
echo "  2) base   (~150 MB) - Good balance (recommended)"
echo "  3) small  (~500 MB) - Better quality, slower"
echo "  4) medium (~1.5 GB) - High quality, slow"
echo "  5) large  (~3 GB)   - Best quality, very slow"
echo ""

# Use read with explicit input redirection to handle non-interactive environments
if [ -t 0 ]; then
    read -p "Enter number [1-5] (default: 2 for base): " model_choice < /dev/tty
else
    echo "Running in non-interactive mode, using default (base) model"
    model_choice=2
fi

# Set default to base if no input
model_choice=${model_choice:-2}

# Map choice to model name
case $model_choice in
    1)
        MODEL_NAME="tiny"
        MODEL_FILE="ggml-tiny.bin"
        ;;
    2)
        MODEL_NAME="base"
        MODEL_FILE="ggml-base.bin"
        ;;
    3)
        MODEL_NAME="small"
        MODEL_FILE="ggml-small.bin"
        ;;
    4)
        MODEL_NAME="medium"
        MODEL_FILE="ggml-medium.bin"
        ;;
    5)
        MODEL_NAME="large"
        MODEL_FILE="ggml-large-v3.bin"
        ;;
    *)
        echo "Invalid choice. Using 'base' model."
        MODEL_NAME="base"
        MODEL_FILE="ggml-base.bin"
        ;;
esac

echo ""
echo "Selected model: $MODEL_NAME"
echo ""

MODEL_PATH="$MODEL_DIR/$MODEL_FILE"

# Check if this specific model already exists
if [ -f "$MODEL_PATH" ]; then
    echo "✅ Model already exists at: $MODEL_PATH"
    file_size=$(du -h "$MODEL_PATH" | cut -f1)
    echo "   Size: $file_size"
else
    echo "📥 Downloading $MODEL_NAME model..."
    echo "This may take a while depending on your internet connection..."
    echo ""

    # Download model directly from Hugging Face
    MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_FILE"

    echo "Downloading from: $MODEL_URL"

    if command -v wget &> /dev/null; then
        wget -O "$MODEL_PATH" "$MODEL_URL"
    elif command -v curl &> /dev/null; then
        curl -L -o "$MODEL_PATH" "$MODEL_URL"
    else
        echo "❌ Error: Neither wget nor curl is installed"
        echo "Please install wget or curl:"
        echo "  sudo apt-get install wget"
        exit 1
    fi

    if [ -f "$MODEL_PATH" ]; then
        echo ""
        echo "✅ Model downloaded successfully to: $MODEL_PATH"
        file_size=$(du -h "$MODEL_PATH" | cut -f1)
        echo "   Size: $file_size"
    else
        echo "❌ Error: Model download failed"
        echo "You can download it manually from:"
        echo "https://huggingface.co/ggerganov/whisper.cpp"
        exit 1
    fi
fi

echo ""
echo "================================================"
echo "🎉 Installation complete!"
echo "================================================"
echo ""
echo "System dependencies:"
echo "  - pulseaudio-utils (for audio recording)"
echo ""
echo "Whisper.cpp:"
echo "  - CLI tool: /tmp/whisper.cpp/build/bin/whisper-cli"
echo "  - Built with CPU-only support (no GPU)"
echo ""
echo "Model: $MODEL_PATH"
echo ""
echo "You can now run the Flutter app with:"
echo "  flutter run -d linux"
echo ""
