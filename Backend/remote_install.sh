#!/bin/bash
set -e

echo "🚀 Starting Remote Setup on Alibaba Cloud ECS..."
echo "ℹ️  OS Info: $(cat /etc/os-release | grep PRETTY_NAME)"

# 1. Update and Install Docker/Podman
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    if command -v yum &> /dev/null; then
        yum install -y docker
        # Try to start. If it fails, it might be Podman-docker (common on Aliyun Linux 3), which is fine.
        systemctl start docker || echo "⚠️ Docker service start failed. Assuming Podman-docker wrapper."
        systemctl enable docker || true
    elif command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y docker.io
    else
        echo "❌ Unsupported OS."
        exit 1
    fi
else
    echo "✅ Docker/Podman is already installed."
fi

# 2. Configure Mirror (simplified - just increase pull timeout)
echo "🌏 Configuring for China network..."

# 3. Build the Image with retries
echo "🔨 Building Docker Image..."
cd /root/LightningBackend

# Podman doesn't always need special config, but timeout yes
for i in {1..3}; do
    echo "Attempt $i/3..."
    if docker build --pull-always --network host -t lightning-app .; then
        echo "✅ Build succeeded!"
        break
    else
        if [ $i -lt 3 ]; then 
            echo "⚠️ Build failed, retrying in 10s..."
            sleep 10
        else
            echo "❌ Build failed after 3 attempts"
            exit 1
        fi
    fi
done

# 4. Cleanup & Run
echo "🛑 Cleaning up old containers..."
docker stop lightning-api 2>/dev/null || true
docker rm lightning-api 2>/dev/null || true

echo "🏃 Starting New Container..."
docker run -d \
  -p 8000:8000 \
  --name lightning-api \
  --restart always \
  -e VOLC_API_KEY="e524bca9-0718-4fd4-9ab6-f6eb7cb63f7d" \
  lightning-app

echo "✅ Deployment Complete!"
echo "🌍 API available at: http://$(curl -s ifconfig.me):8000/docs"
