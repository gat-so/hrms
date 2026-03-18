#!/bin/bash
# Clean up a single PR preview environment
# Usage: cleanup-preview.sh <pr_number>
set -e

PR_NUM="$1"

if [ -z "$PR_NUM" ]; then
    echo "Usage: cleanup-preview.sh <pr_number>"
    exit 1
fi

DEPLOY_DIR="/opt/hrms/preview/pr-${PR_NUM}"

if [ -d "${DEPLOY_DIR}" ]; then
    cd ${DEPLOY_DIR}

    # Stop and remove containers, volumes
    docker compose -p hrms-pr-${PR_NUM} down -v --remove-orphans 2>/dev/null || true

    # Remove deploy directory
    sudo rm -rf ${DEPLOY_DIR}

    echo "Preview PR #${PR_NUM} cleaned up."
else
    echo "No preview found for PR #${PR_NUM}."
fi
