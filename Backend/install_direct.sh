#!/bin/bash
set -e

echo "🚀 Installing LightningCatcher Backend (No Docker)..."

# 1. Install Python and dependencies
echo "📦 Installing Python 3 and pip..."
if command -v yum &> /dev/null; then
    yum install -y python3 python3-pip
elif command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y python3 python3-pip
fi

# 2. Create app directory
echo "📁 Creating application directory..."
mkdir -p /opt/lightning-backend
cd /opt/lightning-backend

# 3. Copy files (will be done by deploy script)
# Files should already be in /root/LightningBackend

# 4. Install Python dependencies using Aliyun mirror
echo "📚 Installing Python packages..."
cd /root/LightningBackend
pip3 install -i https://mirrors.aliyun.com/pypi/simple/ --upgrade pip
pip3 install -i https://mirrors.aliyun.com/pypi/simple/ -r requirements.txt

# 5. Create systemd service
echo "⚙️ Creating systemd service..."
cat > /etc/systemd/system/lightning-backend.service <<EOF
[Unit]
Description=LightningCatcher Backend API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/LightningBackend
Environment="VOLC_API_KEY=e524bca9-0718-4fd4-9ab6-f6eb7cb63f7d"
ExecStart=/usr/bin/python3 -m gunicorn server:app --workers 2 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 6. Start service
echo "🏃 Starting service..."
systemctl daemon-reload
systemctl stop lightning-backend 2>/dev/null || true
systemctl enable lightning-backend
systemctl start lightning-backend

# 7. Check status
sleep 2
systemctl status lightning-backend --no-pager || true

echo "✅ Deployment Complete!"
echo "🌍 API should be available at: http://$(curl -s ifconfig.me):8000/docs"
echo "📊 To check logs: journalctl -u lightning-backend -f"
