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
TRACKER_FILE="${PREVIEW_BASE}/.pr-${PR_NUM}"

if [ -f "${TRACKER_FILE}" ]; then
    UUID=$(cat "${TRACKER_FILE}")
    DEPLOY_DIR="${PREVIEW_BASE}/${UUID}"
    PROJECT_NAME="hrms-preview-${UUID}"

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
