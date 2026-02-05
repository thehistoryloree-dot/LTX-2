 #!/bin/bash
 # LTX-2 RTX 5090 Setup Script for Vast.ai ComfyUI instances

 set -e

 echo "Configuring ComfyUI for RTX 5090 + LTX-2..."

 # Update /etc/environment to add memory management flags
 if grep -q "COMFYUI_ARGS=" /etc/environment; then
     # Check if flags already present
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

 # Restart ComfyUI
 if command -v supervisorctl &> /dev/null; then
     echo "Restarting ComfyUI..."
     supervisorctl restart comfyui
     echo "Done! ComfyUI restarted with RTX 5090 optimizations."
 else
     echo "Done! Please restart ComfyUI manually."
 fi
