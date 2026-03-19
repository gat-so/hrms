#!/bin/bash
# Deploy a PR preview environment on the VPS.
# Previews connect to the target environment's shared infrastructure (MariaDB + Redis)
# so data persists across re-deployments. Each PR gets a stable identity — pushing
# new commits to the same PR updates the preview without losing data.
#
# Usage: deploy-preview.sh <pr_number> <target_env> <github_org> <repo_name> <branch> <preview_domain> <image_repo> <image_tag>
# Requires GITHUB_TOKEN env var for repo access
set -e

PR_NUM="$1"
TARGET_ENV="$2"
GITHUB_ORG="$3"
REPO_NAME="$4"
BRANCH="$5"
DOMAIN="${6:-preview.example.com}"
IMAGE_REPO="${7:-frappe/bench}"
IMAGE_TAG="${8:-latest}"

if [ -z "$PR_NUM" ] || [ -z "$TARGET_ENV" ] || [ -z "$GITHUB_ORG" ] || [ -z "$REPO_NAME" ] || [ -z "$BRANCH" ]; then
    echo "Usage: deploy-preview.sh <pr_number> <target_env> <github_org> <repo_name> <branch> [preview_domain] [image_repo] [image_tag]"
    echo "  target_env: dev or prod (determines which shared infrastructure to use)"
    exit 1
fi

if [ -z "${GITHUB_TOKEN}" ]; then
    echo "ERROR: GITHUB_TOKEN environment variable is required"
    exit 1
fi

# Validate target_env
if [ "${TARGET_ENV}" != "dev" ] && [ "${TARGET_ENV}" != "prod" ]; then
    echo "ERROR: target_env must be 'dev' or 'prod', got '${TARGET_ENV}'"
    exit 1
fi

REPO_URL="https://github.com/${GITHUB_ORG}/${REPO_NAME}.git"

# Set up ephemeral credential helper so the token is never written to .git/config
GIT_ASKPASS_SCRIPT=$(mktemp)
trap 'rm -f "${GIT_ASKPASS_SCRIPT}"' EXIT
printf '#!/bin/sh\necho "%s"\n' "${GITHUB_TOKEN}" > "${GIT_ASKPASS_SCRIPT}"
chmod 700 "${GIT_ASKPASS_SCRIPT}"
export GIT_ASKPASS="${GIT_ASKPASS_SCRIPT}"

PREVIEW_BASE="/opt/hrms/preview"
INFRA_NETWORK="hrms-${TARGET_ENV}-infra"
TARGET_ENV_FILE="/opt/hrms/${TARGET_ENV}/.env"

# Reuse existing UUID for this PR (data persistence) or generate a new one
TRACKER_FILE="${PREVIEW_BASE}/.pr-${PR_NUM}"
if [ -f "${TRACKER_FILE}" ]; then
    UUID=$(cat "${TRACKER_FILE}")
else
    UUID=$(head -c 4 /dev/urandom | xxd -p)
fi

SITE_NAME="hrms-${UUID}.${DOMAIN}"
DEPLOY_DIR="${PREVIEW_BASE}/${UUID}"
PROJECT_NAME="hrms-preview-${UUID}"

# --- Ensure shared infrastructure is running ---
echo "Ensuring shared infrastructure for '${TARGET_ENV}' is running..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "${SCRIPT_DIR}/deploy-infra.sh" "${TARGET_ENV}"

# --- Get DB credentials (check infra .env first, then target env .env) ---
INFRA_ENV_FILE="/opt/hrms/${TARGET_ENV}-infra/.env"
if [ -z "${DB_ROOT_PASSWORD}" ] && [ -f "${INFRA_ENV_FILE}" ]; then
    DB_ROOT_PASSWORD=$(grep '^DB_ROOT_PASSWORD=' "${INFRA_ENV_FILE}" | cut -d= -f2-)
fi
if [ -z "${DB_ROOT_PASSWORD}" ] && [ -f "${TARGET_ENV_FILE}" ]; then
    DB_ROOT_PASSWORD=$(grep '^DB_ROOT_PASSWORD=' "${TARGET_ENV_FILE}" | cut -d= -f2-)
fi

if [ -z "${DB_ROOT_PASSWORD}" ]; then
    echo "ERROR: DB_ROOT_PASSWORD not found in ${INFRA_ENV_FILE} or ${TARGET_ENV_FILE}"
    exit 1
fi

# --- Acquire deploy lock to serialize concurrent deploys for the same PR ---
LOCK_FILE="${PREVIEW_BASE}/.pr-${PR_NUM}.lock"
exec 9>"${LOCK_FILE}"
flock -w 300 9 || {
    echo "ERROR: Timed out waiting for preview lock for PR #${PR_NUM}"
    exit 1
}

# --- Determine if this is a fresh deploy or update ---
IS_UPDATE=false
if [ -d "${DEPLOY_DIR}" ] && [ -f "${DEPLOY_DIR}/.env" ]; then
    IS_UPDATE=true
    echo "Updating existing preview for PR #${PR_NUM}..."
else
    echo "Creating new preview for PR #${PR_NUM}..."
fi

# Create deploy directory
sudo mkdir -p "${DEPLOY_DIR}"
sudo chown "${USER}:${USER}" "${DEPLOY_DIR}"

# Clone or update the PR branch
if [ -d "${DEPLOY_DIR}/repo" ]; then
    cd "${DEPLOY_DIR}/repo"
    git fetch origin
    git checkout "${BRANCH}"
    git reset --hard "origin/${BRANCH}"
else
    git clone -b "${BRANCH}" --depth 1 "${REPO_URL}" "${DEPLOY_DIR}/repo"
    cd "${DEPLOY_DIR}/repo"
fi

# Create/update preview .env (preserve ADMIN_PASSWORD on updates)
if [ "${IS_UPDATE}" = true ]; then
    ADMIN_PASSWORD=$(grep '^ADMIN_PASSWORD=' "${DEPLOY_DIR}/.env" | cut -d= -f2-)
else
    ADMIN_PASSWORD=$(openssl rand -hex 16)
fi

( umask 077 && cat > "${DEPLOY_DIR}/.env" << EOF
ENVIRONMENT=${TARGET_ENV}
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
SITE_NAME=${SITE_NAME}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
TRAEFIK_DOMAIN=${SITE_NAME}
INFRA_NETWORK=${INFRA_NETWORK}
HTTP_PORT=0
SOCKETIO_PORT=0
FRAPPE_IMAGE=${IMAGE_REPO}
FRAPPE_IMAGE_TAG=${IMAGE_TAG}
FRAPPE_BRANCH=develop
ERPNEXT_BRANCH=develop
HRMS_REPO=${REPO_URL}
HRMS_BRANCH=${BRANCH}
TARGET_ENV=${TARGET_ENV}
EOF
)

# Copy compose file
cp "${DEPLOY_DIR}/repo/deploy/docker-compose.yml" "${DEPLOY_DIR}/docker-compose.yml"

cd "${DEPLOY_DIR}"

# Stop existing containers (without removing volumes) then start fresh
# This ensures one-shot services (configurator, create-site) re-run
docker compose -p "${PROJECT_NAME}" \
    --env-file .env \
    down --remove-orphans 2>/dev/null || true

docker compose -p "${PROJECT_NAME}" \
    --env-file .env \
    up -d --remove-orphans

# --- Ensure nginx is on traefik_network (fallback for race conditions) ---
sleep 3
NGINX_CONTAINER=$(docker compose -p "${PROJECT_NAME}" --env-file .env ps nginx -q 2>/dev/null)
if [ -n "${NGINX_CONTAINER}" ]; then
    docker network connect traefik_network "${NGINX_CONTAINER}" 2>/dev/null || true
fi

# --- Diagnostics ---
echo ""
echo "=== Deployment Info ==="
echo "PROJECT_NAME=${PROJECT_NAME}"
echo "SITE_NAME=${SITE_NAME}"
echo "TRAEFIK_DOMAIN=${SITE_NAME}"
echo "TARGET_ENV=${TARGET_ENV}"
echo "INFRA_NETWORK=${INFRA_NETWORK}"
echo "IS_UPDATE=${IS_UPDATE}"
if [ -n "${NGINX_CONTAINER}" ]; then
    echo ""
    echo "--- nginx labels ---"
    docker inspect "${NGINX_CONTAINER}" --format '{{range $k,$v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' 2>/dev/null | grep traefik || true
    echo ""
    echo "--- nginx networks ---"
    docker inspect "${NGINX_CONTAINER}" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || true
fi
echo "=== End Diagnostics ==="

# --- Show create-site logs for debugging ---
echo ""
echo "=== create-site logs ==="
docker compose -p "${PROJECT_NAME}" --env-file .env logs create-site 2>/dev/null | tail -100
echo "=== End create-site logs ==="

# --- Verify site is accessible ---
echo ""
echo "Waiting for site to become accessible..."
MAX_RETRIES=${PREVIEW_HEALTH_RETRIES:-12}
RETRY_INTERVAL=10
HTTP_CODE="000"
for i in $(seq 1 ${MAX_RETRIES}); do
    sleep ${RETRY_INTERVAL}
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${SITE_NAME}/" 2>/dev/null || echo "000")
    echo "Attempt ${i}/${MAX_RETRIES}: HTTP ${HTTP_CODE}"
    if echo "${HTTP_CODE}" | grep -qE '^2'; then
        break
    fi
done

# Mark deployment time for stale-check
touch "${DEPLOY_DIR}/.last_deployed"

# Track this preview's UUID for the PR (for cleanup by PR number)
echo "${UUID}" > "${TRACKER_FILE}"

if ! echo "${HTTP_CODE}" | grep -qE '^2'; then
    echo ""
    echo "=== backend logs (last 30 lines) ==="
    docker compose -p "${PROJECT_NAME}" --env-file .env logs backend 2>/dev/null | tail -30
    echo "=== End backend logs ==="
    echo ""
    echo "ERROR: Site not accessible after ${MAX_RETRIES} attempts (last HTTP ${HTTP_CODE})"
    echo "PREVIEW_UUID=${UUID}"
    echo "PREVIEW_URL=https://${SITE_NAME}"
    exit 1
fi

# Output the preview URL (used by CI to post comment)
echo "PREVIEW_UUID=${UUID}"
echo "PREVIEW_URL=https://${SITE_NAME}"
echo "Preview deployed at: https://${SITE_NAME}"
if [ "${IS_UPDATE}" = true ]; then
    echo "Data preserved from previous deployment."
else
    SECRETS_FILE="${DEPLOY_DIR}/.admin_password"
    printf '%s\n' "${ADMIN_PASSWORD}" > "${SECRETS_FILE}"
    chmod 600 "${SECRETS_FILE}"
    echo "Fresh deployment. Admin password saved to ${SECRETS_FILE}"
fi

# Clean up ephemeral credential helper
rm -f "${GIT_ASKPASS_SCRIPT}"
