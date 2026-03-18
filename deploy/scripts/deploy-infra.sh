#!/bin/bash
# Deploy shared infrastructure (MariaDB + Redis) for an environment tier.
# This is idempotent — safe to run multiple times.
# Usage: deploy-infra.sh <environment>
# Requires: DB_ROOT_PASSWORD env var or /opt/hrms/<environment>/.env file
set -e

ENV="$1"

if [ -z "$ENV" ]; then
    echo "Usage: deploy-infra.sh <environment>"
    echo "  environment: dev or prod"
    exit 1
fi

INFRA_DIR="/opt/hrms/${ENV}-infra"
INFRA_NETWORK="hrms-${ENV}-infra"
INFRA_PROJECT="hrms-${ENV}-infra"
ENV_FILE="/opt/hrms/${ENV}/.env"

# Get DB_ROOT_PASSWORD from env or target environment's .env file
if [ -z "${DB_ROOT_PASSWORD}" ] && [ -f "${ENV_FILE}" ]; then
    DB_ROOT_PASSWORD=$(grep '^DB_ROOT_PASSWORD=' "${ENV_FILE}" | cut -d= -f2)
fi

if [ -z "${DB_ROOT_PASSWORD}" ]; then
    echo "ERROR: DB_ROOT_PASSWORD not set and not found in ${ENV_FILE}"
    exit 1
fi

# Ensure directory exists
sudo mkdir -p "${INFRA_DIR}"
sudo chown "${USER}:${USER}" "${INFRA_DIR}"

# Find the infra compose file — check multiple locations
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DEPLOY_DIR="$(dirname "${SCRIPT_DIR}")"
INFRA_COMPOSE=""
for path in \
    "${REPO_DEPLOY_DIR}/docker-compose.infra.yml" \
    "${SCRIPT_DIR}/docker-compose.infra.yml" \
    "/opt/hrms/${ENV}/repo/deploy/docker-compose.infra.yml"; do
    if [ -f "$path" ]; then
        INFRA_COMPOSE="$path"
        break
    fi
done

if [ -z "${INFRA_COMPOSE}" ]; then
    echo "ERROR: docker-compose.infra.yml not found"
    exit 1
fi

cp "${INFRA_COMPOSE}" "${INFRA_DIR}/docker-compose.yml"

# Create/update .env for infrastructure
cat > "${INFRA_DIR}/.env" << EOF
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
INFRA_NETWORK=${INFRA_NETWORK}
EOF
chmod 600 "${INFRA_DIR}/.env"

# Start infrastructure
cd "${INFRA_DIR}"
docker compose -p "${INFRA_PROJECT}" \
    --env-file .env \
    up -d

echo "Infrastructure for '${ENV}' deployed on network '${INFRA_NETWORK}'"
