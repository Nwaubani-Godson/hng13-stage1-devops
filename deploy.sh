#!/bin/bash

# ============================
# HNG13-Stage1-DevOps Deployment Script
# Fully automated Docker + Nginx deploy
# Includes idempotency and --cleanup flag
# ============================

set -euo pipefail

# ----- Logging -----
LOG_FILE="deploy_$(date +'%Y%m%d_%H%M%S').log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== HNG13-Stage1-DevOps Deployment Started ====="

# ----- Check for cleanup flag -----
CLEANUP=false
if [ "${1:-}" == "--cleanup" ]; then
    CLEANUP=true
fi

# ----- Collect Parameters -----
read -rp "GitHub Repository URL: " REPO_URL
read -rp "GitHub Personal Access Token (PAT): " PAT
read -rp "Branch name (default: main): " BRANCH
BRANCH=${BRANCH:-main}

read -rp "Remote server username: " REMOTE_USER
read -rp "Remote server IP: " REMOTE_IP
read -rp "SSH private key path: " SSH_KEY
read -rp "Application internal container port: " APP_PORT

# ----- Repository and Deployment Variables -----
REPO_NAME=$(basename "$REPO_URL" .git)
APP_DIR="/home/$REMOTE_USER/hng13_stage1_app"
IMAGE_NAME="hng13_stage1_app_image"
CONTAINER_NAME="hng13_stage1_app_cont"

# ----- SSH Helper -----
SSH_CMD="ssh -i $SSH_KEY -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_IP"

# ----- Cleanup Mode -----
if [ "$CLEANUP" = true ]; then
    echo "===== CLEANUP MODE ====="
    read -rp "Delete all app files, Docker image/container, and Nginx config? [yes/NO]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
        $SSH_CMD bash <<EOF
set -euo pipefail
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true
docker rmi $IMAGE_NAME 2>/dev/null || true
rm -rf $APP_DIR
sudo rm -f /etc/nginx/sites-available/hng13_stage1_app
sudo rm -f /etc/nginx/sites-enabled/hng13_stage1_app
sudo nginx -t && sudo systemctl reload nginx || true
EOF
    fi
    exit 0
fi

# ----- Clone Repo Locally for Verification -----
if [ -d "$REPO_NAME" ]; then
    echo "Repository exists locally, pulling latest changes..."
    git -C "$REPO_NAME" pull origin "$BRANCH"
else
    echo "Cloning repository..."
    git clone -b "$BRANCH" "https://$PAT@${REPO_URL#https://}" "$REPO_NAME"
fi

# Verify Dockerfile/docker-compose.yml exists
if [ ! -f "$REPO_NAME/Dockerfile" ] && [ ! -f "$REPO_NAME/docker-compose.yml" ]; then
    echo "ERROR: No Dockerfile or docker-compose.yml found in repo."
    exit 1
fi

# ----- Prepare Remote Environment -----
$SSH_CMD bash <<'EOF'
set -euo pipefail
LOG_FILE="deploy_$(date +'%Y%m%d_%H%M%S').log"
exec > >(tee -a "$LOG_FILE") 2>&1
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y docker.io docker-compose nginx rsync curl git 
sudo systemctl enable docker --now
sudo systemctl enable nginx --now
sudo usermod -aG docker $USER || true
EOF

# ----- Transfer Project Files -----
rsync -av --exclude='.git' -e "ssh -i $SSH_KEY" "$REPO_NAME/" "$REMOTE_USER@$REMOTE_IP:$APP_DIR/"

# ----- Deploy Docker Container & Configure Nginx -----
$SSH_CMD bash <<EOF
set -euo pipefail
cd "$APP_DIR"

# Build Docker image
docker build -t $IMAGE_NAME .

# Stop and remove old container if exists
if docker ps -a --format '{{.Names}}' | grep -Eq "^$CONTAINER_NAME\$"; then
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
fi

# Remove dangling networks (idempotency)
docker network prune -f || true

# Run container on host port 80
docker run -d --name $CONTAINER_NAME -p $APP_PORT:$APP_PORT $IMAGE_NAME

# Configure Nginx reverse proxy (overwrite if exists)
NGINX_CONF="/etc/nginx/sites-available/hng13_stage1_app"
sudo tee "$NGINX_CONF" > /dev/null <<NGINX_EOF
server {
    listen 80;
    server_name REMOTE_IP_PLACEHOLDER;

    location / {
        proxy_pass http://localhost:APP_PORT_PLACEHOLDER;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX_EOF

# Replace placeholders
sudo sed -i "s/REMOTE_IP_PLACEHOLDER/$REMOTE_IP/" "$NGINX_CONF"
sudo sed -i "s/APP_PORT_PLACEHOLDER/$APP_PORT/" "$NGINX_CONF"

# Link Nginx config (overwrite existing)
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Validate deployment
docker ps
curl -s http://localhost | head -n 5
EOF

echo "===== HNG13-Stage1-DevOps Deployment Finished Locally ====="
echo "Log file: $LOG_FILE"
