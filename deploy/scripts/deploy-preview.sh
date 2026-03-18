#!/bin/bash
# Deploy a PR preview environment on the VPS
# Usage: deploy-preview.sh <pr_number> <repo_url> <branch> <preview_domain> <image_repo> <image_tag>
set -e

PR_NUM="$1"
REPO_URL="$2"
BRANCH="$3"
DOMAIN="${4:-preview.example.com}"
IMAGE_REPO="${5:-frappe/bench}"
IMAGE_TAG="${6:-latest}"

if [ -z "$PR_NUM" ] || [ -z "$REPO_URL" ] || [ -z "$BRANCH" ]; then
    echo "Usage: deploy-preview.sh <pr_number> <repo_url> <branch> [preview_domain] [image_repo] [image_tag]"
    exit 1
fi

DEPLOY_DIR="/opt/hrms/preview/pr-${PR_NUM}"
SITE_NAME="hrms-${PR_NUM}.${DOMAIN}"
DB_PASSWORD=$(openssl rand -hex 16)
ADMIN_PASSWORD=$(openssl rand -hex 16)

# Create preview directory
sudo mkdir -p ${DEPLOY_DIR}
sudo chown ${USER}:${USER} ${DEPLOY_DIR}

# Clone the PR branch
if [ -d "${DEPLOY_DIR}/repo" ]; then
    cd ${DEPLOY_DIR}/repo
    git fetch origin
    git checkout ${BRANCH}
    git reset --hard origin/${BRANCH}
else
    git clone -b ${BRANCH} ${REPO_URL} ${DEPLOY_DIR}/repo
    cd ${DEPLOY_DIR}/repo
fi

# Create preview .env
cat > ${DEPLOY_DIR}/.env << EOF
ENVIRONMENT=preview
COMPOSE_PROJECT_NAME=hrms-pr-${PR_NUM}
SITE_NAME=${SITE_NAME}
DB_ROOT_PASSWORD=${DB_PASSWORD}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
TRAEFIK_DOMAIN=${SITE_NAME}
HTTP_PORT=0
SOCKETIO_PORT=0
FRAPPE_IMAGE=${IMAGE_REPO}
FRAPPE_IMAGE_TAG=${IMAGE_TAG}
FRAPPE_BRANCH=develop
ERPNEXT_BRANCH=develop
HRMS_REPO=${REPO_URL}
HRMS_BRANCH=${BRANCH}
EOF

# Copy and start deployment
cp ${DEPLOY_DIR}/repo/deploy/docker-compose.yml ${DEPLOY_DIR}/docker-compose.yml

cd ${DEPLOY_DIR}
docker compose -p hrms-pr-${PR_NUM} \
    --env-file .env \
    up -d --remove-orphans

# Touch marker file for stale cleanup tracking
touch ${DEPLOY_DIR}/.last_deployed

echo "Preview deployed at: https://${SITE_NAME}"
