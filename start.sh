#!/bin/bash
set -e

echo "[startup] OpenClaw Railway starting..."

# Join Tailscale network if auth key is provided
if [ -n "$TAILSCALE_AUTH_KEY" ]; then
  echo "[startup] Tailscale auth key detected, joining network..."
  
  # Start tailscaled in background (needs root, so we use sudo if available)
  if command -v sudo &> /dev/null; then
    sudo tailscaled --state=/data/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
  else
    # If no sudo, user must run container with --privileged or appropriate capabilities
    echo "[startup] WARNING: sudo not available, tailscale may not work properly"
  fi
  
  sleep 2
  
  # Connect to network
  if command -v sudo &> /dev/null; then
    sudo tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname="${TAILSCALE_HOSTNAME:-openclaw-railway}" --accept-routes
  else
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname="${TAILSCALE_HOSTNAME:-openclaw-railway}" --accept-routes
  fi
  
  echo "[startup] Tailscale connected successfully"
else
  echo "[startup] No Tailscale auth key provided, skipping Tailscale setup"
fi

# Start the wrapper server
echo "[startup] Starting OpenClaw wrapper server..."
exec node src/server.js
