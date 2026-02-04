#!/bin/bash
# =============================================================================
# LTX-2 + Z-Image-Turbo + RTX 5090 Provisioning Script for Vast.ai
# =============================================================================
# This script automates the complete setup of ComfyUI with LTX-2 video
# generation and Z-Image-Turbo on RTX 5090 GPUs (Blackwell architecture).
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

# Detect ComfyUI directory (handles both 'ComfyUI' and 'comfyui')
if [ -d "${WORKSPACE}/ComfyUI" ]; then
    COMFYUI_DIR="${WORKSPACE}/ComfyUI"
elif [ -d "${WORKSPACE}/comfyui" ]; then
    COMFYUI_DIR="${WORKSPACE}/comfyui"
else
    echo "ERROR: ComfyUI directory not found in ${WORKSPACE}"
    exit 1
fi

echo "ComfyUI directory: ${COMFYUI_DIR}"

# =============================================================================
# 1. RTX 5090 (Blackwell) Compatibility Fixes
# =============================================================================
echo ""
echo "--- Applying RTX 5090 Fixes ---"

# Fix /etc/environment if it exists and has COMFYUI_ARGS
if [ -f /etc/environment ]; then
    if grep -q "COMFYUI_ARGS" /etc/environment; then
        if ! grep -q "disable-xformers" /etc/environment; then
            sed -i 's/COMFYUI_ARGS="\([^"]*\)"/COMFYUI_ARGS="\1 --disable-xformers"/' /etc/environment
            echo "Added --disable-xformers to /etc/environment"
        fi
    fi

    if ! grep -q "XFORMERS_DISABLED" /etc/environment; then
        echo 'XFORMERS_DISABLED="1"' >> /etc/environment
        echo "Added XFORMERS_DISABLED to /etc/environment"
    fi
fi

# Fix startup script if it exists
STARTUP_SCRIPT="/opt/supervisor-scripts/comfyui.sh"
if [ -f "${STARTUP_SCRIPT}" ]; then
    if ! grep -q "disable-xformers" "${STARTUP_SCRIPT}"; then
        sed -i 's/--enable-cors-header}/--enable-cors-header --disable-xformers}/' "${STARTUP_SCRIPT}"
        echo "Added --disable-xformers to startup script"
    fi

    if ! grep -q "XFORMERS_DISABLED" "${STARTUP_SCRIPT}"; then
        sed -i '/# Launch ComfyUI/a export XFORMERS_DISABLED=1' "${STARTUP_SCRIPT}"
        echo "Added XFORMERS_DISABLED export to startup script"
    fi
fi

# Set environment variable for current session
export XFORMERS_DISABLED=1

echo "RTX 5090 fixes applied"

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
# 4. Custom Nodes Installation
# =============================================================================
echo ""
echo "--- Installing Custom Nodes ---"

CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
cd "${CUSTOM_NODES_DIR}"

# Function to install a custom node
install_node() {
    local repo_url=$1
    local node_name=$(basename "$repo_url" .git)

    if [ -d "${node_name}" ]; then
        echo "  [SKIP] ${node_name} already exists"
    else
        echo "  [INSTALL] ${node_name}"
        git clone --depth 1 -q "${repo_url}"

        # Install requirements if they exist
        if [ -f "${node_name}/requirements.txt" ]; then
            pip install -q -r "${node_name}/requirements.txt"
        fi
    fi
}

# Install all required custom nodes
install_node "https://github.com/Comfy-Org/ComfyUI-Manager.git"
install_node "https://github.com/Lightricks/ComfyUI-LTXVideo.git"
install_node "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
install_node "https://github.com/rgthree/rgthree-comfy.git"
install_node "https://github.com/kijai/ComfyUI-KJNodes.git"
install_node "https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git"
install_node "https://github.com/evanspearman/ComfyMath.git"

echo "Custom nodes installed"

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
echo "Your ComfyUI instance is ready with:"
echo ""
echo "  RTX 5090 Compatibility:"
echo "    - xformers disabled (using PyTorch SDPA)"
echo ""
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
echo "  Custom Nodes:"
echo "    - ComfyUI-Manager"
echo "    - ComfyUI-LTXVideo"
echo "    - ComfyUI-Impact-Pack"
echo "    - rgthree-comfy"
echo "    - ComfyUI-KJNodes"
echo "    - Comfyui_TTP_Toolset"
echo "    - ComfyMath"
echo ""
echo "Access ComfyUI at: http://localhost:18188"
echo "=============================================="
