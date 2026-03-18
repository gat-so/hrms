#!/bin/bash
# Clean up stale PR preview deployments.
# Removes previews whose PRs are closed/merged or that have exceeded the stale age.
# Does NOT touch shared infrastructure — only preview app containers and volumes.
# Run via cron: 0 2 * * * /opt/hrms/scripts/cleanup-previews.sh
set -e

PREVIEW_DIR="/opt/hrms/preview"
GITHUB_REPO="${GITHUB_REPO:-gat-so/hrms}"
STALE_HOURS="${STALE_HOURS:-72}"

echo "=== Cleaning up stale PR previews ==="

if [ ! -d "$PREVIEW_DIR" ]; then
    echo "No preview directory found."
    exit 0
fi

# Iterate over PR tracker files to find all active previews
for tracker_file in ${PREVIEW_DIR}/.pr-*; do
    [ -f "$tracker_file" ] || continue

    PR_NUM=$(basename "$tracker_file" | sed 's/\.pr-//')

    # Validate PR_NUM is a positive integer
    if ! echo "${PR_NUM}" | grep -qE '^[0-9]+$'; then
        echo "Skipping invalid tracker file: ${tracker_file}"
        continue
    fi

    UUID=$(cat "$tracker_file")

    # Validate UUID contains only safe characters
    if ! echo "${UUID}" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        echo "Skipping invalid UUID in tracker: ${tracker_file}"
        continue
    fi

    DEPLOY_DIR="${PREVIEW_DIR}/${UUID}"
    PROJECT_NAME="hrms-preview-${UUID}"

    if [ ! -d "${DEPLOY_DIR}" ]; then
        echo "Preview directory missing for PR #${PR_NUM} (${UUID}), cleaning up tracker..."
        rm -f "$tracker_file"
        continue
    fi

    # Check if PR is still open (requires GitHub CLI)
    if command -v gh &> /dev/null; then
        PR_STATE=$(gh pr view "$PR_NUM" --repo "$GITHUB_REPO" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
    else
        PR_STATE="UNKNOWN"
    fi

    # Check age based on last deployment marker, falling back to directory mtime
    MARKER_FILE="${DEPLOY_DIR}/.last_deployed"
    if [ -f "$MARKER_FILE" ]; then
        LAST_DEPLOY_TIME=$(stat -c %Y "$MARKER_FILE" 2>/dev/null || stat -f %m "$MARKER_FILE")
    else
        LAST_DEPLOY_TIME=$(stat -c %Y "$DEPLOY_DIR" 2>/dev/null || stat -f %m "$DEPLOY_DIR")
    fi
    DIR_AGE_HOURS=$(( ($(date +%s) - ${LAST_DEPLOY_TIME}) / 3600 ))

    if [ "$PR_STATE" = "CLOSED" ] || [ "$PR_STATE" = "MERGED" ] || [ "$DIR_AGE_HOURS" -gt "$STALE_HOURS" ]; then
        echo "Cleaning up PR #${PR_NUM} / ${UUID} (state: ${PR_STATE}, age: ${DIR_AGE_HOURS}h)..."

        # Drop site from shared MariaDB before tearing down
        if [ -f "${DEPLOY_DIR}/.env" ]; then
            SITE_NAME=$(grep '^SITE_NAME=' "${DEPLOY_DIR}/.env" | cut -d= -f2-)
            DB_ROOT_PASSWORD=$(grep '^DB_ROOT_PASSWORD=' "${DEPLOY_DIR}/.env" | cut -d= -f2-)

            if [ -n "${SITE_NAME}" ] && [ -n "${DB_ROOT_PASSWORD}" ]; then
                docker compose -p "${PROJECT_NAME}" --env-file "${DEPLOY_DIR}/.env" \
                    exec -T backend \
                    bench drop-site "${SITE_NAME}" --mariadb-root-password "${DB_ROOT_PASSWORD}" --force \
                    2>/dev/null || true
            fi
        fi

        cd "${DEPLOY_DIR}" || {
            echo "ERROR: Cannot cd to ${DEPLOY_DIR}, skipping"
            continue
        }
        docker compose -p "${PROJECT_NAME}" down -v --remove-orphans 2>/dev/null || true

        # Verify DEPLOY_DIR is inside PREVIEW_DIR before removal
        DEPLOY_REAL=$(realpath "${DEPLOY_DIR}")
        PREVIEW_REAL=$(realpath "${PREVIEW_DIR}")
        if [ "${DEPLOY_REAL}" = "${PREVIEW_REAL}" ] || [ "${DEPLOY_REAL#${PREVIEW_REAL}/}" != "${DEPLOY_REAL}" ]; then
            sudo rm -rf "${DEPLOY_DIR}"
        else
            echo "ERROR: ${DEPLOY_DIR} resolves outside ${PREVIEW_DIR}, skipping removal"
            continue
        fi
        rm -f "$tracker_file"

        echo "  Done."
    else
        echo "Keeping PR #${PR_NUM} / ${UUID} (state: ${PR_STATE}, age: ${DIR_AGE_HOURS}h)"
    fi
done

echo "=== Cleanup complete ==="
