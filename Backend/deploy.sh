#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# LightningCatcher Deploy Script
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Usage:
#   ./deploy.sh              # Deploy and restart server
#   ./deploy.sh --logs       # Tail live server logs
#   ./deploy.sh --status     # Check server status
#   ./deploy.sh --stop       # Stop server
#
# Server: 115.191.62.158 (Volcengine ECS)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -e

SERVER="root@115.191.62.158"
REMOTE_DIR="/root/lightning"
LOCAL_BACKEND="$(cd "$(dirname "$0")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[deploy]${NC} $1"; }
warn() { echo -e "${YELLOW}[deploy]${NC} $1"; }
err()  { echo -e "${RED}[deploy]${NC} $1"; }

# ── Helper commands ──────────────────────────────────────────────────

if [[ "$1" == "--logs" ]]; then
    log "Tailing server logs..."
    ssh "$SERVER" "tail -f /var/log/lightning/server.log"
    exit 0
fi

if [[ "$1" == "--status" ]]; then
    log "Checking server status..."
    ssh "$SERVER" "systemctl status lightning 2>/dev/null || echo 'Service not found, checking process...'; ps aux | grep '[u]vicorn' | head -3"
    echo ""
    log "Health check:"
    curl -s "http://115.191.62.158:8000/health" 2>/dev/null | python3 -m json.tool || err "Server not responding"
    exit 0
fi

if [[ "$1" == "--stop" ]]; then
    log "Stopping server..."
    ssh "$SERVER" "systemctl stop lightning 2>/dev/null; pkill -f 'uvicorn.*server:app' 2>/dev/null || true"
    log "Server stopped"
    exit 0
fi

# ── Main deploy ──────────────────────────────────────────────────────

log "Deploying LightningCatcher Backend to $SERVER"
log "Local source: $LOCAL_BACKEND"

# 1. Setup remote directories
log "Setting up remote directories..."
ssh "$SERVER" "mkdir -p $REMOTE_DIR /var/log/lightning /var/lib/lightning/tasks"

# 2. Upload files
log "Uploading files..."
scp "$LOCAL_BACKEND/server.py" "$SERVER:$REMOTE_DIR/server.py"
scp "$LOCAL_BACKEND/requirements.txt" "$SERVER:$REMOTE_DIR/requirements.txt"

# 3. Install dependencies
log "Installing Python dependencies..."
ssh "$SERVER" "cd $REMOTE_DIR && pip3 install -r requirements.txt -q"

# 4. Create systemd service
log "Configuring systemd service..."
ssh "$SERVER" "cat > /etc/systemd/system/lightning.service << 'EOF'
[Unit]
Description=LightningCatcher Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/lightning
ExecStart=/usr/bin/python3 -m uvicorn server:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF"

# 5. Restart service
log "Restarting service..."
ssh "$SERVER" "systemctl daemon-reload && systemctl enable lightning && systemctl restart lightning"

# 6. Wait and verify
log "Waiting for server to start..."
sleep 3

HEALTH=$(curl -s "http://115.191.62.158:8000/health" 2>/dev/null)
if echo "$HEALTH" | grep -q '"ok"'; then
    log "✅ Deploy successful!"
    echo "$HEALTH" | python3 -m json.tool
else
    err "❌ Server not responding, checking logs..."
    ssh "$SERVER" "journalctl -u lightning -n 20 --no-pager"
fi

log "Done. Useful commands:"
echo "  ./deploy.sh --logs     # Tail live logs"
echo "  ./deploy.sh --status   # Check status"
echo "  ./deploy.sh --stop     # Stop server"
echo "  ssh $SERVER 'cat /var/log/lightning/server.log'   # Full log"
echo "  ssh $SERVER 'cat /var/log/lightning/error.log'    # Errors only"
echo "  ssh $SERVER 'cat /var/log/lightning/requests.log' # API requests"
