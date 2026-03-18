#!/bin/bash
# Deploy a specific environment (prod or dev) on the VPS.
# Ensures shared infrastructure is running before deploying app services.
# Usage: deploy-env.sh <environment> <github_org> <repo_name> <branch>
# Requires GITHUB_TOKEN env var for repo access
set -e

ENV="$1"
GITHUB_ORG="$2"
REPO_NAME="$3"
BRANCH="$4"

if [ -z "$ENV" ] || [ -z "$GITHUB_ORG" ] || [ -z "$REPO_NAME" ] || [ -z "$BRANCH" ]; then
    echo "Usage: deploy-env.sh <environment> <github_org> <repo_name> <branch>"
    exit 1
fi

if [ -z "${GITHUB_TOKEN}" ]; then
    echo "ERROR: GITHUB_TOKEN environment variable is required"
    exit 1
fi

REPO_URL="https://github.com/${GITHUB_ORG}/${REPO_NAME}.git"

# Set up ephemeral credential helper so the token is never written to .git/config
GIT_ASKPASS_SCRIPT=$(mktemp)
trap 'rm -f "${GIT_ASKPASS_SCRIPT}"' EXIT
printf '#!/bin/sh\necho "%s"\n' "${GITHUB_TOKEN}" > "${GIT_ASKPASS_SCRIPT}"
chmod 700 "${GIT_ASKPASS_SCRIPT}"
export GIT_ASKPASS="${GIT_ASKPASS_SCRIPT}"

DEPLOY_DIR="/opt/hrms/${ENV}"

# Ensure deploy directory exists
sudo mkdir -p "${DEPLOY_DIR}"
sudo chown "${USER}:${USER}" "${DEPLOY_DIR}"

# Clone or update repo
if [ -d "${DEPLOY_DIR}/repo" ]; then
    cd "${DEPLOY_DIR}/repo"
    git fetch origin
    git checkout "${BRANCH}"
    git reset --hard "origin/${BRANCH}"
else
    git clone -b "${BRANCH}" "${REPO_URL}" "${DEPLOY_DIR}/repo"
    cd "${DEPLOY_DIR}/repo"
fi

# Copy deployment files
cp deploy/docker-compose.yml "${DEPLOY_DIR}/docker-compose.yml"
cp "deploy/.env.${ENV}.example" "${DEPLOY_DIR}/.env.example"

# Require .env to exist (must be configured before first deploy)
if [ ! -f "${DEPLOY_DIR}/.env" ]; then
    echo "ERROR: ${DEPLOY_DIR}/.env not found."
    echo "Copy ${DEPLOY_DIR}/.env.example to ${DEPLOY_DIR}/.env and configure it before deploying."
    exit 1
fi

# Source .env to get DB_ROOT_PASSWORD for infra deployment
set -a
source "${DEPLOY_DIR}/.env"
set +a

# --- Ensure shared infrastructure is running ---
echo "Ensuring shared infrastructure for '${ENV}' is running..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "${SCRIPT_DIR}/deploy-infra.sh" "${ENV}"

# --- Deploy app services ---
cd "${DEPLOY_DIR}"
docker compose -p "hrms-${ENV}" \
    --env-file .env \
    pull
docker compose -p "hrms-${ENV}" \
    --env-file .env \
    up -d --remove-orphans

# Run migrations
docker compose -p "hrms-${ENV}" exec -T backend \
    bench --site "${SITE_NAME:-hrms.localhost}" migrate --skip-failing

# Clean up ephemeral credential helper
rm -f "${GIT_ASKPASS_SCRIPT}"

echo "Deployment of ${ENV} complete!"
