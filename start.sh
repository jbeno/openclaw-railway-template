#!/bin/bash
set -e

echo "[startup] OpenClaw Railway starting..."

# Auto-configure SSH credentials from persistent volume
if [ -d "/data/.credentials/ssh" ]; then
  echo "[startup] Configuring SSH credentials..."
  
  # Set up SSH for openclaw user
  mkdir -p /home/openclaw/.ssh
  chmod 700 /home/openclaw/.ssh
  
  # Copy all SSH credentials from persistent volume
  cp -r /data/.credentials/ssh/* /home/openclaw/.ssh/
  
  # Set correct permissions
  chmod 600 /home/openclaw/.ssh/*
  chmod 644 /home/openclaw/.ssh/*.pub 2>/dev/null || true
  
  # Ensure openclaw owns everything
  chown -R openclaw:openclaw /home/openclaw/.ssh
  
  echo "[startup] SSH credentials configured"
  
  # Add known hosts
  su - openclaw -c "ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null || true"
fi

# Configure git for openclaw user if credentials exist
if [ -f "/data/.credentials/email.json" ]; then
  # Extract email from credentials (generic approach)
  GIT_EMAIL=$(grep -o '"email"[[:space:]]*:[[:space:]]*"[^"]*"' /data/.credentials/email.json | cut -d'"' -f4)
  if [ -n "$GIT_EMAIL" ]; then
    echo "[startup] Configuring git..."
    su - openclaw -c "git config --global user.email '$GIT_EMAIL'"
    su - openclaw -c "git config --global user.name 'Hachi'"
    echo "[startup] Git configured"
  fi
fi

# Set up Moltbook credential symlinks if credentials exist
if [ -f "/data/.credentials/moltbook.json" ]; then
  echo "[startup] Setting up Moltbook credential symlinks..."
  
  # Create config directories
  mkdir -p /home/openclaw/.config/moltbook
  mkdir -p /data/.config/moltbook
  
  # Create symlink chain: ~/.config/moltbook/credentials.json → /data/.config/moltbook/credentials.json → /data/.credentials/moltbook.json
  ln -sf /data/.credentials/moltbook.json /data/.config/moltbook/credentials.json
  ln -sf /data/.config/moltbook/credentials.json /home/openclaw/.config/moltbook/credentials.json
  
  # Ensure openclaw owns the config directories
  chown -R openclaw:openclaw /home/openclaw/.config
  chown -R openclaw:openclaw /data/.config
  
  echo "[startup] Moltbook credentials configured"
fi

# Join Tailscale network if auth key is provided
# NOTE: This must run as root, then we'll switch to openclaw user for the app
if [ -n "$TAILSCALE_AUTH_KEY" ]; then
  echo "[startup] Tailscale auth key detected, joining network..."
  
  # Ensure tailscale state directory exists
  mkdir -p /data/tailscale
  chown openclaw:openclaw /data/tailscale
  
  # Start tailscaled as root (required)
  # Use userspace networking since Railway containers lack /dev/net/tun
  echo "[startup] Starting tailscaled daemon (userspace networking mode)..."
  tailscaled --state=/data/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock --tun=userspace-networking &
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
    
    # Expose the app via Tailscale HTTPS (accessible only from tailnet)
    echo "[startup] Enabling Tailscale serve on port 8080..."
    tailscale serve --bg 8080 || echo "[startup] WARNING: tailscale serve failed, app may only be accessible locally"
  else
    echo "[startup] ERROR: Failed to connect to Tailscale"
    kill $TAILSCALED_PID 2>/dev/null || true
  fi
else
  echo "[startup] No Tailscale auth key provided, skipping Tailscale setup"
fi

# Ensure data directories are owned by openclaw user
mkdir -p /data/.openclaw
chown -R openclaw:openclaw /data

# Schedule post-restart notification (run in background)
# Wait for gateway to be ready, then send a system event to wake the agent
(
  MAX_RETRIES=24
  RETRY_DELAY=5

  for i in $(seq 1 $MAX_RETRIES); do
    sleep $RETRY_DELAY

    # Check if gateway is responding
    if curl -s -f "http://127.0.0.1:18789/openclaw" > /dev/null 2>&1; then
      echo "[heartbeat] Gateway is ready, sending restart system event..."

      # Send an immediate system event (no cron job needed)
      su -s /bin/bash openclaw -c "
        export OPENCLAW_STATE_DIR=/data/.openclaw
        export OPENCLAW_WORKSPACE_DIR=/data/.openclaw/workspace
        openclaw system event --mode now --text 'Container restarted. All services online. Check system state and continue any pending work.'
      " && echo "[heartbeat] Restart system event sent" \
        || echo "[heartbeat] WARNING: Failed to send restart system event"

      break
    else
      echo "[heartbeat] Waiting for gateway (attempt $i/$MAX_RETRIES)..."
    fi
  done

  if [ "$i" -eq "$MAX_RETRIES" ]; then
    echo "[heartbeat] WARNING: Gateway did not become ready after ${MAX_RETRIES} attempts"
  fi
) &

echo "[startup] Post-restart notification scheduled in background"

# Start the wrapper server as openclaw user
echo "[startup] Starting OpenClaw wrapper server as openclaw user..."
exec su -s /bin/bash openclaw -c "cd /app && node src/server.js"
