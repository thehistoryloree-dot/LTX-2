#!/bin/bash
# =============================================================================
# LTX-2 + Z-Image-Turbo + RTX 5090 Provisioning Script for Vast.ai
# =============================================================================
# This script automates the complete setup of ComfyUI with LTX-2 video
# generation and Z-Image-Turbo on RTX 5090 GPUs (Blackwell architecture).
#
# Optimized for maximum performance with automatic VRAM overflow to system RAM.
#
# Usage: Set this script URL as your "On-start Script" when creating a
#        Vast.ai instance, or run manually with:
#        curl -s https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/ltx2-5090-provisioning.sh | bash
# =============================================================================

set -e  # Exit on error

echo "=============================================="
echo "LTX-2 + Z-Image-Turbo + RTX 5090 Provisioning"
echo "=============================================="

# --- Configuration ---
WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_DIR=""

# =============================================================================
# 0. Wait for Vast.ai Base Provisioning to Complete
# =============================================================================
echo ""
echo "--- Waiting for Vast.ai Base Provisioning ---"

# Wait for provisioning lock file to be removed (Vast.ai standard)
MAX_WAIT=600  # 10 minutes max wait
WAITED=0
while [ -f "/.provisioning" ]; do
    echo "Waiting for base provisioning to complete... (${WAITED}s/${MAX_WAIT}s)"
    sleep 10
    WAITED=$((WAITED + 10))
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo "WARNING: Timed out waiting for /.provisioning to be removed"
        break
    fi
done

# Wait for ComfyUI directory to exist
MAX_WAIT=300  # 5 minutes max wait for ComfyUI
WAITED=0
while true; do
    if [ -d "${WORKSPACE}/ComfyUI" ]; then
        COMFYUI_DIR="${WORKSPACE}/ComfyUI"
        break
    elif [ -d "${WORKSPACE}/comfyui" ]; then
        COMFYUI_DIR="${WORKSPACE}/comfyui"
        break
    fi

    echo "Waiting for ComfyUI to be installed... (${WAITED}s/${MAX_WAIT}s)"
    sleep 10
    WAITED=$((WAITED + 10))

    if [ $WAITED -ge $MAX_WAIT ]; then
        echo "ERROR: ComfyUI directory not found after ${MAX_WAIT}s"
        echo "Expected: ${WORKSPACE}/ComfyUI or ${WORKSPACE}/comfyui"
        echo "Please ensure you're using a ComfyUI template on Vast.ai"
        exit 1
    fi
done

echo "ComfyUI directory found: ${COMFYUI_DIR}"

# Wait a bit more for ComfyUI to fully initialize
sleep 5

# =============================================================================
# 1. RTX 5090 (Blackwell) Compatibility & Performance Fixes
# =============================================================================
echo ""
echo "--- Applying RTX 5090 Fixes & Performance Optimizations ---"

# -----------------------------------------------------------------------------
# Performance-optimized COMFYUI_ARGS for RTX 5090:
#
#   --disable-xformers          : xformers doesn't support compute capability 12.0
#   --use-pytorch-cross-attention: Use PyTorch's native SDPA (has Flash Attention)
#   --fast                      : Enable FP8 matrix mult, cuBLAS ops, autotune
#   --bf16-vae                  : Use BF16 for VAE (native Blackwell support)
#   --cuda-malloc               : Use cudaMallocAsync for better memory management
#   --reserve-vram 2048         : Keep 2GB headroom to prevent OOM crashes
#   --force-channels-last       : Better memory layout for modern GPUs
#
# NOTE: We do NOT use --highvram because:
#   - LTX-2 19B model can exceed 32GB VRAM during generation
#   - Default NORMAL_VRAM mode automatically offloads to system RAM when needed
#   - This prevents crashes while maintaining good performance
# -----------------------------------------------------------------------------

OPTIMIZED_ARGS="--disable-auto-launch --port 18188 --enable-cors-header --disable-xformers --use-pytorch-cross-attention --fast --bf16-vae --cuda-malloc --reserve-vram 2048 --force-channels-last"

# Fix /etc/environment
if [ -f /etc/environment ]; then
    # Remove old COMFYUI_ARGS and add optimized version
    if grep -q "COMFYUI_ARGS" /etc/environment; then
        sed -i '/^COMFYUI_ARGS=/d' /etc/environment
    fi
    echo "COMFYUI_ARGS=\"${OPTIMIZED_ARGS}\"" >> /etc/environment
    echo "Updated COMFYUI_ARGS with RTX 5090 optimizations"

    # Add xformers disabled flag
    if ! grep -q "XFORMERS_DISABLED" /etc/environment; then
        echo 'XFORMERS_DISABLED="1"' >> /etc/environment
    fi

    # Add PyTorch performance environment variables
    if ! grep -q "PYTORCH_CUDA_ALLOC_CONF" /etc/environment; then
        echo 'PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True"' >> /etc/environment
        echo "Added PYTORCH_CUDA_ALLOC_CONF for better memory management"
    fi

    if ! grep -q "CUDA_MODULE_LOADING" /etc/environment; then
        echo 'CUDA_MODULE_LOADING="LAZY"' >> /etc/environment
        echo "Added CUDA_MODULE_LOADING=LAZY for faster startup"
    fi

    if ! grep -q "TORCH_CUDNN_V8_API_ENABLED" /etc/environment; then
        echo 'TORCH_CUDNN_V8_API_ENABLED="1"' >> /etc/environment
        echo "Added cuDNN v8 API optimization"
    fi
fi

# Fix startup script if it exists
STARTUP_SCRIPT="/opt/supervisor-scripts/comfyui.sh"
if [ -f "${STARTUP_SCRIPT}" ]; then
    # Update the default args in the script
    if grep -q "COMFYUI_ARGS=\${COMFYUI_ARGS:-" "${STARTUP_SCRIPT}"; then
        sed -i "s|COMFYUI_ARGS=\${COMFYUI_ARGS:-[^}]*}|COMFYUI_ARGS=\${COMFYUI_ARGS:-${OPTIMIZED_ARGS}}|" "${STARTUP_SCRIPT}"
        echo "Updated startup script with optimized args"
    fi

    # Add environment exports if not present
    if ! grep -q "XFORMERS_DISABLED" "${STARTUP_SCRIPT}"; then
        sed -i '/# Launch ComfyUI/a export XFORMERS_DISABLED=1' "${STARTUP_SCRIPT}"
    fi

    if ! grep -q "PYTORCH_CUDA_ALLOC_CONF" "${STARTUP_SCRIPT}"; then
        sed -i '/# Launch ComfyUI/a export PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True"' "${STARTUP_SCRIPT}"
    fi

    if ! grep -q "CUDA_MODULE_LOADING" "${STARTUP_SCRIPT}"; then
        sed -i '/# Launch ComfyUI/a export CUDA_MODULE_LOADING=LAZY' "${STARTUP_SCRIPT}"
    fi
fi

# Set environment variables for current session
export XFORMERS_DISABLED=1
export PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True"
export CUDA_MODULE_LOADING=LAZY
export TORCH_CUDNN_V8_API_ENABLED=1

echo "RTX 5090 performance optimizations applied"

# =============================================================================
# 2. System Dependencies
# =============================================================================
echo ""
echo "--- Installing System Dependencies ---"

apt-get update -qq
apt-get install -y -qq git-lfs
git lfs install

echo "System dependencies installed"

# =============================================================================
# 3. Python Dependencies for LTX-2
# =============================================================================
echo ""
echo "--- Installing Python Dependencies ---"

# Activate venv if it exists (Vast.ai standard setup)
if [ -f /venv/main/bin/activate ]; then
    source /venv/main/bin/activate
fi

pip install -q bitsandbytes accelerate

echo "Python dependencies installed"
# =============================================================================
# 5. LTX-2 Model Downloads
# =============================================================================
echo ""
echo "--- Downloading LTX-2 Models ---"

# Function to download a file if it doesn't exist
download_model() {
    local url=$1
    local output_path=$2
    local description=$3

    if [ -f "${output_path}" ]; then
        echo "  [SKIP] ${description} already exists"
    else
        echo "  [DOWNLOAD] ${description}"
        mkdir -p "$(dirname "${output_path}")"
        wget -q --show-progress -O "${output_path}" "${url}"
    fi
}

# A. LTX-2 Checkpoint (~27GB)
download_model \
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-distilled-fp8.safetensors?download=true" \
    "${COMFYUI_DIR}/models/checkpoints/ltx-2-19b-distilled-fp8.safetensors" \
    "LTX-2 Checkpoint (27GB)"

# B. LTX Spatial Upscaler
download_model \
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-spatial-upscaler-x2-1.0.safetensors?download=true" \
    "${COMFYUI_DIR}/models/latent_upscale_models/ltx-2-spatial-upscaler-x2-1.0.safetensors" \
    "LTX-2 Spatial Upscaler"

# C. Gemma 3 Text Encoder (4-bit quantized)
GEMMA_DIR="${COMFYUI_DIR}/models/text_encoders/gemma-3-12b-it-bnb-4bit"
if [ -d "${GEMMA_DIR}" ]; then
    echo "  [SKIP] Gemma 3 Text Encoder already exists"
else
    echo "  [DOWNLOAD] Gemma 3 Text Encoder (4-bit)"
    mkdir -p "${COMFYUI_DIR}/models/text_encoders"
    cd "${COMFYUI_DIR}/models/text_encoders"
    git clone --depth 1 -q https://huggingface.co/unsloth/gemma-3-12b-it-bnb-4bit
fi

echo "LTX-2 models downloaded"

# =============================================================================
# 6. Z-Image-Turbo Model Downloads
# =============================================================================
echo ""
echo "--- Downloading Z-Image-Turbo Models ---"

# A. Text Encoder (Qwen) -> models/clip
download_model \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" \
    "${COMFYUI_DIR}/models/clip/qwen_3_4b.safetensors" \
    "Z-Image-Turbo Text Encoder (Qwen 3 4B)"

# B. Diffusion Model (UNet) -> models/unet
download_model \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors" \
    "${COMFYUI_DIR}/models/unet/z_image_turbo_bf16.safetensors" \
    "Z-Image-Turbo Diffusion Model"

# C. VAE -> models/vae
download_model \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" \
    "${COMFYUI_DIR}/models/vae/z_image_turbo_ae.safetensors" \
    "Z-Image-Turbo VAE"

echo "Z-Image-Turbo models downloaded"

# =============================================================================
# 7. Restart ComfyUI (if supervisor is available)
# =============================================================================
echo ""
echo "--- Restarting ComfyUI ---"

if command -v supervisorctl &> /dev/null; then
    supervisorctl restart comfyui 2>/dev/null || echo "Could not restart via supervisor"
    echo "ComfyUI restarted"
else
    echo "Supervisor not found - please restart ComfyUI manually"
fi

# =============================================================================
# Done!
# =============================================================================
echo ""
echo "=============================================="
echo "Provisioning Complete!"
echo "=============================================="
echo ""
echo "RTX 5090 Performance Optimizations Applied:"
echo "  - xformers disabled (using PyTorch Flash SDPA)"
echo "  - FP8 matrix multiplication enabled"
echo "  - cuBLAS optimizations enabled"
echo "  - PyTorch autotuning enabled"
echo "  - BF16 VAE (native Blackwell support)"
echo "  - Channels-last memory format"
echo "  - 2GB VRAM reserved for headroom"
echo "  - Automatic VRAM->RAM overflow enabled"
echo "  - Expandable memory segments enabled"
echo ""
echo "Models Installed:"
echo "  LTX-2 Video Generation:"
echo "    - LTX-2 19B Distilled FP8 checkpoint"
echo "    - LTX-2 Spatial Upscaler 2x"
echo "    - Gemma 3 12B 4-bit Text Encoder"
echo ""
echo "  Z-Image-Turbo Image Generation:"
echo "    - Qwen 3 4B Text Encoder"
echo "    - Z-Image-Turbo BF16 Diffusion Model"
echo "    - Z-Image-Turbo VAE"
echo ""
echo "Custom Nodes (7):"
echo "  ComfyUI-Manager, LTXVideo, Impact-Pack,"
echo "  rgthree, KJNodes, TTP_Toolset, ComfyMath"
echo ""
echo "Access ComfyUI at: http://localhost:18188"
echo "=============================================="
