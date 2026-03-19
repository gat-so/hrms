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

# Bootstrap .env from .env.example on first deploy
if [ ! -f "${DEPLOY_DIR}/.env" ]; then
    if [ ! -f "${DEPLOY_DIR}/.env.example" ]; then
        echo "ERROR: ${DEPLOY_DIR}/.env.example not found. Cannot bootstrap .env."
        exit 1
    fi
    echo "First deploy detected — bootstrapping .env from .env.example"
    ( umask 077 && cp "${DEPLOY_DIR}/.env.example" "${DEPLOY_DIR}/.env" )

    # Auto-generate passwords replacing placeholders
    DB_PASS=$(openssl rand -hex 16) || { echo "ERROR: Failed to generate DB_ROOT_PASSWORD"; exit 1; }
    ADMIN_PASS=$(openssl rand -hex 16) || { echo "ERROR: Failed to generate ADMIN_PASSWORD"; exit 1; }
    if [ -z "${DB_PASS}" ] || [ -z "${ADMIN_PASS}" ]; then
        echo "ERROR: openssl rand produced empty output"
        exit 1
    fi
    sed -i "s/^DB_ROOT_PASSWORD=.*/DB_ROOT_PASSWORD=${DB_PASS}/" "${DEPLOY_DIR}/.env"
    sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=${ADMIN_PASS}/" "${DEPLOY_DIR}/.env"

    # Allow env var overrides for domain and site name
    if [ -n "${TRAEFIK_DOMAIN}" ]; then
        # Sanitize for sed: escape \, &, and the | delimiter
        SAFE_DOMAIN=$(printf '%s' "${TRAEFIK_DOMAIN}" | tr -d '\n' | sed 's/[\\&|]/\\&/g')
        sed -i "s|^TRAEFIK_DOMAIN=.*|TRAEFIK_DOMAIN=${SAFE_DOMAIN}|" "${DEPLOY_DIR}/.env"
        sed -i "s|^SITE_NAME=.*|SITE_NAME=${SAFE_DOMAIN}|" "${DEPLOY_DIR}/.env"
    fi

    echo "Generated .env with auto-generated passwords at ${DEPLOY_DIR}/.env"
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
