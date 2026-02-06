#!/bin/bash
# LTX-2 RTX 5090 Complete Setup Script for Vast.ai ComfyUI instances
# Combines: RTX 5090 flags + Model downloads + Custom nodes

set -e

echo "=============================================="
echo "LTX-2 + RTX 5090 Complete Provisioning Script"
echo "=============================================="

# ============================================
# PART 1: RTX 5090 CONFIGURATION FLAGS
# ============================================
echo ""
echo "--- Configuring RTX 5090 Flags ---"

# Update /etc/environment to add memory management flags
if grep -q "COMFYUI_ARGS=" /etc/environment; then
    if ! grep -q "disable-xformers" /etc/environment; then
        sed -i 's/COMFYUI_ARGS="\([^"]*\)"/COMFYUI_ARGS="\1 --disable-xformers --disable-smart-memory"/' /etc/environment
        echo "Updated /etc/environment with RTX 5090 flags"
    else
        echo "/etc/environment already configured"
    fi
fi

# Also update the default in comfyui.sh for persistence
if [ -f /opt/supervisor-scripts/comfyui.sh ]; then
    if ! grep -q "disable-xformers" /opt/supervisor-scripts/comfyui.sh; then
        sed -i 's/--enable-cors-header}/--enable-cors-header --disable-xformers --disable-smart-memory}/' /opt/supervisor-scripts/comfyui.sh
        echo "Updated comfyui.sh defaults"
    fi
fi

# ============================================
# PART 2: SYSTEM SETUP & FOLDER DETECTION
# ============================================
echo ""
echo "--- System Setup ---"

cd /workspace
# Detect if folder is 'ComfyUI' or 'comfyui' and enter it
if [ -d "ComfyUI" ]; then 
    COMFY_DIR="ComfyUI"
else 
    COMFY_DIR="comfyui"
fi
cd "$COMFY_DIR"
echo "Installing in: $(pwd)"

# Install Git LFS (Essential for large model downloads)
apt-get update && apt-get install -y git-lfs
git lfs install

# Install Python libraries specifically for 4-bit LTX models (Crucial Fix)
pip install bitsandbytes accelerate

# ============================================
# PART 3: INSTALL LTX-VIDEO CUSTOM NODES
# ============================================
echo ""
echo "--- Setting up LTX-Video Custom Nodes ---"

cd custom_nodes

# LTX-Video Custom Node
if [ ! -d "ComfyUI-LTXVideo" ]; then
    git clone https://github.com/Lightricks/ComfyUI-LTXVideo.git
    cd ComfyUI-LTXVideo
    pip install -r requirements.txt
    cd ..
else
    echo "ComfyUI-LTXVideo already installed"
fi

# ComfyMath Custom Node
if [ ! -d "ComfyMath" ]; then
    echo "Installing ComfyMath..."
    git clone https://github.com/evanspearman/ComfyMath.git
    cd ComfyMath
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    fi
    cd ..
else
    echo "ComfyMath already installed"
fi

# ComfyUI-Impact-Pack Custom Node
if [ ! -d "ComfyUI-Impact-Pack" ]; then
    echo "Installing ComfyUI-Impact-Pack..."
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
    cd ComfyUI-Impact-Pack
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    fi
    # Impact Pack has an install script
    if [ -f "install.py" ]; then
        python install.py
    fi
    cd ..
else
    echo "ComfyUI-Impact-Pack already installed"
fi

cd ..

# ============================================
# PART 4: DOWNLOAD LTX-VIDEO MODELS
# ============================================
echo ""
echo "--- Downloading LTX-Video Models ---"

# A. LTX-2 Checkpoint (~27GB)
cd models/checkpoints
if [ ! -f "ltx-2-19b-distilled-fp8.safetensors" ]; then
    echo "Downloading LTX-2 Checkpoint..."
    wget -O ltx-2-19b-distilled-fp8.safetensors "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-distilled-fp8.safetensors?download=true"
else
    echo "LTX-2 Checkpoint already exists"
fi

# B. LTX Upscaler
mkdir -p ../latent_upscale_models
cd ../latent_upscale_models
if [ ! -f "ltx-2-spatial-upscaler-x2-1.0.safetensors" ]; then
    echo "Downloading LTX Upscaler..."
    wget -O ltx-2-spatial-upscaler-x2-1.0.safetensors "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-spatial-upscaler-x2-1.0.safetensors?download=true"
else
    echo "LTX Upscaler already exists"
fi

# C. Gemma 3 Text Encoder (Folder Structure)
mkdir -p ../text_encoders
cd ../text_encoders
if [ ! -d "gemma-3-12b-it-bnb-4bit" ]; then
    echo "Downloading Gemma 3..."
    git clone https://huggingface.co/unsloth/gemma-3-12b-it-bnb-4bit
else
    echo "Gemma 3 already exists"
fi

# ============================================
# PART 5: DOWNLOAD Z-IMAGE-TURBO (SPLIT FILES)
# ============================================
echo ""
echo "--- Setting up Z-Image-Turbo ---"

cd /workspace/$COMFY_DIR/models

# A. Text Encoder (Qwen) -> models/clip
mkdir -p clip
cd clip
if [ ! -f "qwen_3_4b.safetensors" ]; then
    echo "Downloading Qwen Text Encoder..."
    wget -O qwen_3_4b.safetensors "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
else
    echo "Qwen Text Encoder already exists"
fi
cd ..

# B. Diffusion Model (UNet) -> models/unet
mkdir -p unet
cd unet
if [ ! -f "z_image_turbo_bf16.safetensors" ]; then
    echo "Downloading Z-Image UNet..."
    wget -O z_image_turbo_bf16.safetensors "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
else
    echo "Z-Image UNet already exists"
fi
cd ..

# C. VAE -> models/vae
mkdir -p vae
cd vae
if [ ! -f "z_image_turbo_ae.safetensors" ]; then
    echo "Downloading Z-Image VAE..."
    wget -O z_image_turbo_ae.safetensors "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
else
    echo "Z-Image VAE already exists"
fi
cd ..

# ============================================
# PART 6: ADDITIONAL LORAS (if needed)
# ============================================
echo ""
echo "--- LoRA Section (Skipped - No LoRAs configured) ---"

# ============================================
# PART 7: RESTART COMFYUI
# ============================================
echo ""
echo "=============================================="
echo "ALL DONE! Restarting ComfyUI..."
echo "=============================================="

if command -v supervisorctl &> /dev/null; then
    supervisorctl restart comfyui
    echo "ComfyUI restarted with RTX 5090 optimizations + all models loaded!"
else
    echo "Please restart ComfyUI manually."
fi
