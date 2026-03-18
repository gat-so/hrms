#!/bin/bash
# Clean up a PR preview environment by PR number.
# Removes app containers and volumes, and drops the site from shared MariaDB.
# Usage: cleanup-preview.sh <pr_number>
set -e

PR_NUM="$1"

if [ -z "$PR_NUM" ]; then
    echo "Usage: cleanup-preview.sh <pr_number>"
    exit 1
fi

PREVIEW_BASE="/opt/hrms/preview"

# Validate PR_NUM is a positive integer
if ! echo "${PR_NUM}" | grep -qE '^[0-9]+$'; then
    echo "ERROR: Invalid PR number: ${PR_NUM}"
    exit 1
fi

TRACKER_FILE="${PREVIEW_BASE}/.pr-${PR_NUM}"

if [ -f "${TRACKER_FILE}" ]; then
    PREVIEW_ID=$(cat "${TRACKER_FILE}")

    # Validate PREVIEW_ID contains only safe characters
    if ! echo "${PREVIEW_ID}" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        echo "ERROR: Invalid preview ID in tracker file: ${PREVIEW_ID}"
        exit 1
    fi

    DEPLOY_DIR="${PREVIEW_BASE}/${PREVIEW_ID}"
    PROJECT_NAME="hrms-preview-${PREVIEW_ID}"

    # Verify DEPLOY_DIR is inside PREVIEW_BASE
    RESOLVED_DIR=$(realpath -m "${DEPLOY_DIR}" 2>/dev/null || echo "${DEPLOY_DIR}")
    if [ "${RESOLVED_DIR##${PREVIEW_BASE}/}" = "${RESOLVED_DIR}" ]; then
        echo "ERROR: DEPLOY_DIR ${DEPLOY_DIR} is not inside ${PREVIEW_BASE}"
        exit 1
    fi

    if [ -d "${DEPLOY_DIR}" ]; then
        # Read env to get site info for database cleanup
        if [ -f "${DEPLOY_DIR}/.env" ]; then
            SITE_NAME=$(grep '^SITE_NAME=' "${DEPLOY_DIR}/.env" | cut -d= -f2)
            DB_ROOT_PASSWORD=$(grep '^DB_ROOT_PASSWORD=' "${DEPLOY_DIR}/.env" | cut -d= -f2)

            # Drop the site from shared MariaDB before tearing down containers
            if [ -n "${SITE_NAME}" ] && [ -n "${DB_ROOT_PASSWORD}" ]; then
                echo "Dropping site ${SITE_NAME} from shared MariaDB..."
                docker compose -p "${PROJECT_NAME}" --env-file "${DEPLOY_DIR}/.env" \
                    exec -T backend \
                    bench drop-site "${SITE_NAME}" --mariadb-root-password "${DB_ROOT_PASSWORD}" --force \
                    2>/dev/null || echo "WARNING: Could not drop site (may not exist or backend not running)"
            fi
        fi

        cd "${DEPLOY_DIR}"
        docker compose -p "${PROJECT_NAME}" down -v --remove-orphans 2>/dev/null || true
        sudo rm -rf "${DEPLOY_DIR}"
    fi

    rm -f "${TRACKER_FILE}"
    echo "Preview for PR #${PR_NUM} (${PREVIEW_ID}) cleaned up."
else
    echo "No preview found for PR #${PR_NUM}."
fi
