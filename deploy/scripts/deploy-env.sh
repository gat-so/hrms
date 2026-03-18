#!/bin/bash
# Deploy a specific environment (prod or dev) on the VPS
# Usage: deploy-env.sh <environment> <repo_url> <branch>
set -e

ENV="$1"
REPO_URL="$2"
BRANCH="$3"

if [ -z "$ENV" ] || [ -z "$REPO_URL" ] || [ -z "$BRANCH" ]; then
    echo "Usage: deploy-env.sh <environment> <repo_url> <branch>"
    exit 1
fi

DEPLOY_DIR="/opt/hrms/${ENV}"

# Ensure deploy directory exists
sudo mkdir -p ${DEPLOY_DIR}
sudo chown ${USER}:${USER} ${DEPLOY_DIR}

# Clone or update repo
if [ -d "${DEPLOY_DIR}/repo" ]; then
    cd ${DEPLOY_DIR}/repo
    git fetch origin
    git checkout ${BRANCH}
    git reset --hard origin/${BRANCH}
else
    git clone -b ${BRANCH} ${REPO_URL} ${DEPLOY_DIR}/repo
    cd ${DEPLOY_DIR}/repo
fi

# Copy deployment files
cp deploy/docker-compose.yml ${DEPLOY_DIR}/docker-compose.yml
cp deploy/.env.${ENV}.example ${DEPLOY_DIR}/.env.example

# Create .env if it doesn't exist (first deploy)
if [ ! -f "${DEPLOY_DIR}/.env" ]; then
    cp ${DEPLOY_DIR}/.env.example ${DEPLOY_DIR}/.env
    echo "WARNING: Using example .env — update with real values!"
fi

# Deploy
cd ${DEPLOY_DIR}
export $(grep -v '^#' .env | xargs)

docker compose -p hrms-${ENV} \
    --env-file .env \
    pull
docker compose -p hrms-${ENV} \
    --env-file .env \
    up -d --remove-orphans

# Run migrations
docker compose -p hrms-${ENV} exec -T backend \
    bench --site ${SITE_NAME:-hrms.localhost} migrate --skip-failing

echo "Deployment of ${ENV} complete!"
