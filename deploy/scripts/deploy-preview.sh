#!/bin/bash
# Deploy a PR preview environment on the VPS
# Each push creates a fresh deployment with a unique ID, tearing down the previous one.
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

PREVIEW_BASE="/opt/hrms/preview"
UUID=$(head -c 4 /dev/urandom | xxd -p)
SITE_NAME="hrms-${UUID}.${DOMAIN}"
DEPLOY_DIR="${PREVIEW_BASE}/${UUID}"
PROJECT_NAME="hrms-preview-${UUID}"

# --- Tear down any previous preview for this PR ---
TRACKER_FILE="${PREVIEW_BASE}/.pr-${PR_NUM}"
if [ -f "${TRACKER_FILE}" ]; then
    OLD_UUID=$(cat "${TRACKER_FILE}")
    OLD_DIR="${PREVIEW_BASE}/${OLD_UUID}"
    OLD_PROJECT="hrms-preview-${OLD_UUID}"
    if [ -d "${OLD_DIR}" ]; then
        echo "Tearing down previous preview ${OLD_UUID} for PR #${PR_NUM}..."
        cd "${OLD_DIR}"
        docker compose -p "${OLD_PROJECT}" down -v --remove-orphans 2>/dev/null || true
        sudo rm -rf "${OLD_DIR}"
    fi
fi

# Track this deployment for the PR
echo "${UUID}" > "${TRACKER_FILE}"

# Create deploy directory
sudo mkdir -p ${DEPLOY_DIR}
sudo chown ${USER}:${USER} ${DEPLOY_DIR}

# Clone the PR branch
git clone -b ${BRANCH} --depth 1 ${REPO_URL} ${DEPLOY_DIR}/repo
cd ${DEPLOY_DIR}/repo

# Create preview .env
DB_PASSWORD=$(openssl rand -hex 16)
ADMIN_PASSWORD=$(openssl rand -hex 16)

cat > ${DEPLOY_DIR}/.env << EOF
ENVIRONMENT=preview
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
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
docker compose -p ${PROJECT_NAME} \
    --env-file .env \
    up -d --remove-orphans

# Output the preview URL (used by CI to post comment)
echo "PREVIEW_UUID=${UUID}"
echo "PREVIEW_URL=https://${SITE_NAME}"
echo "Preview deployed at: https://${SITE_NAME}"
