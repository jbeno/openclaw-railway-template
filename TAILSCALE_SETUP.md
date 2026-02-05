# Tailscale Setup Guide

This guide shows you how to set up Tailscale for secure, private access to your OpenClaw Railway instance.

## Why Tailscale?

By default, your Railway deployment is publicly accessible via a Railway URL. With Tailscale, you can:
- **Lock down access** - Only devices on your Tailscale network can reach OpenClaw
- **No port forwarding** - Works through NAT and firewalls
- **Encrypted** - All traffic is encrypted via WireGuard
- **Cross-platform** - Access from Mac, Windows, Linux, iOS, Android

## Prerequisites

1. **Tailscale account** - Sign up at https://tailscale.com (free for personal use)
2. **Tailscale installed** on your devices (Mac, phone, etc.)
3. **Railway volume** mounted at `/data` (for persistent Tailscale state)

## Step 1: Install Tailscale on Your Devices

Install Tailscale on any devices you want to use to access OpenClaw:

- **Mac:** https://tailscale.com/download/mac
- **iOS:** App Store → "Tailscale"
- **Android:** Play Store → "Tailscale"
- **Windows/Linux:** https://tailscale.com/download

Sign in to the same Tailscale account on all devices.

## Step 2: Generate Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Click **"Generate auth key..."**
3. Settings:
   - ✅ **Reusable** (allows container restarts)
   - ✅ **Ephemeral** (auto-removes device when container stops)
   - **Expiration:** 90 days (or your preference)
4. Click **Generate key**
5. Copy the key (starts with `tskey-auth-...`)

## Step 3: Add to Railway

In your Railway project:

1. Go to **Variables** tab
2. Click **+ New Variable**
3. Add:
   ```
   TAILSCALE_AUTH_KEY=tskey-auth-xxx...
   ```
4. (Optional) Customize hostname:
   ```
   TAILSCALE_HOSTNAME=openclaw-railway
   ```
5. Click **Add** and **redeploy**

## Step 4: Configure OpenClaw for Tailscale Access

After your Railway container joins your Tailscale network, update OpenClaw's gateway config:

### Option A: Via Web UI (Easiest)

1. Access Railway's **public URL** one last time (before we lock it down)
2. Go to `/setup` → **Run Doctor** or manually edit config
3. Update gateway settings:
   ```json
   {
     "gateway": {
       "bind": "0.0.0.0",
       "tailscale": {
         "mode": "serve"
       }
     }
   }
   ```
4. Restart OpenClaw

### Option B: Via openclaw CLI

If you have terminal access (via Railway's web terminal or SSH):

```bash
openclaw config set gateway.bind "0.0.0.0"
openclaw config set gateway.tailscale.mode "serve"
openclaw gateway restart
```

## Step 5: Access via Tailscale

1. Go to https://login.tailscale.com/admin/machines
2. Find `openclaw-railway` (or your custom hostname)
3. Copy its Tailscale IP (e.g., `100.x.x.x`)
4. Access OpenClaw:
   ```
   http://100.x.x.x:18789/?token=your-gateway-token
   ```

🎉 **Success!** The public Railway URL is now inaccessible. Only devices on your Tailscale network can reach OpenClaw.

## Verification

### Test Public URL is Blocked
Try accessing the old Railway URL - it should timeout or refuse connection.

### Test Tailscale URL Works
Access `http://100.x.x.x:18789/?token=...` from a device on your Tailscale network - should work!

## Mobile Access

Install Tailscale on your phone, log in with the same account, and access the Tailscale IP from your mobile browser. Works anywhere with internet!

## Troubleshooting

### Container Won't Join Tailscale

**Check logs:**
```bash
railway logs
```

Look for `[startup] Tailscale connected successfully`

**Common issues:**
- Auth key expired (generate new one)
- Auth key already used (generate reusable key)
- Missing Railway volume at `/data`

### Can't Access via Tailscale IP

**Verify gateway bind:**
```bash
openclaw config get gateway.bind
```
Should be `"0.0.0.0"` (not `"loopback"`)

**Verify Tailscale mode:**
```bash
openclaw config get gateway.tailscale.mode
```
Should be `"serve"`

**Check firewall:**
Make sure Railway's internal firewall allows traffic from Tailscale interfaces.

### Locked Out Completely

If you can't access OpenClaw at all:

1. Go to Railway Variables
2. **Remove** `TAILSCALE_AUTH_KEY` temporarily
3. Redeploy
4. Access via public URL
5. Fix config
6. Re-add Tailscale key

## Security Notes

- **Auth key storage:** Railway encrypts environment variables
- **Tailscale state:** Stored in `/data/tailscale/` on the volume
- **Gateway token:** Always use a strong gateway token (even with Tailscale)
- **Key rotation:** Rotate Tailscale auth keys every 90 days

## Advanced: Tailscale ACLs

You can further restrict access using Tailscale ACLs:

1. Go to https://login.tailscale.com/admin/acls
2. Add rules like:
   ```json
   {
     "acls": [
       {
         "action": "accept",
         "src": ["autogroup:members"],
         "dst": ["tag:openclaw:*"]
       }
     ]
   }
   ```

This allows fine-grained control over who can access OpenClaw on your network.

---

**Questions?** Check the [Tailscale docs](https://tailscale.com/kb/) or [OpenClaw docs](https://docs.openclaw.ai).
