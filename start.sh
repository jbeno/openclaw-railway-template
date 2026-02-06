#!/bin/bash
set -e

echo "[startup] OpenClaw Railway starting..."

# Join Tailscale network if auth key is provided
# NOTE: This must run as root, then we'll switch to openclaw user for the app
if [ -n "$TAILSCALE_AUTH_KEY" ]; then
  echo "[startup] Tailscale auth key detected, joining network..."
  
  # Ensure tailscale state directory exists
  mkdir -p /data/tailscale
  chown openclaw:openclaw /data/tailscale
  
  # Start tailscaled as root (required)
  echo "[startup] Starting tailscaled daemon..."
  tailscaled --state=/data/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
  TAILSCALED_PID=$!
  
  # Wait for tailscaled to be ready
  echo "[startup] Waiting for tailscaled to start..."
  sleep 3
  
  # Connect to Tailscale network
  echo "[startup] Connecting to Tailscale network..."
  tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname="${TAILSCALE_HOSTNAME:-openclaw-railway}" --accept-routes
  
  if [ $? -eq 0 ]; then
    echo "[startup] Tailscale connected successfully"
    tailscale status
  else
    echo "[startup] ERROR: Failed to connect to Tailscale"
    kill $TAILSCALED_PID 2>/dev/null || true
  fi
else
  echo "[startup] No Tailscale auth key provided, skipping Tailscale setup"
fi

# Start the wrapper server as openclaw user
echo "[startup] Starting OpenClaw wrapper server as openclaw user..."
exec su -s /bin/bash openclaw -c "cd /app && node src/server.js"
