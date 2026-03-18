#!/bin/bash
# Clean up a PR preview environment by PR number
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
    UUID=$(cat "${TRACKER_FILE}")

    # Validate UUID contains only safe characters
    if ! echo "${UUID}" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        echo "ERROR: Invalid UUID in tracker file: ${UUID}"
        exit 1
    fi

    DEPLOY_DIR="${PREVIEW_BASE}/${UUID}"
    PROJECT_NAME="hrms-preview-${UUID}"

    # Verify DEPLOY_DIR is inside PREVIEW_BASE
    RESOLVED_DIR=$(realpath -m "${DEPLOY_DIR}" 2>/dev/null || echo "${DEPLOY_DIR}")
    if [ "${RESOLVED_DIR##${PREVIEW_BASE}/}" = "${RESOLVED_DIR}" ]; then
        echo "ERROR: DEPLOY_DIR ${DEPLOY_DIR} is not inside ${PREVIEW_BASE}"
        exit 1
    fi

    if [ -d "${DEPLOY_DIR}" ]; then
        cd "${DEPLOY_DIR}"
        docker compose -p "${PROJECT_NAME}" down -v --remove-orphans 2>/dev/null || true
        sudo rm -rf "${DEPLOY_DIR}"
    fi

    rm -f "${TRACKER_FILE}"
    echo "Preview for PR #${PR_NUM} (${UUID}) cleaned up."
else
    echo "No preview found for PR #${PR_NUM}."
fi
