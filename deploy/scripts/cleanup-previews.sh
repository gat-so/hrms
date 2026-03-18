#!/bin/bash
# Clean up stale PR preview deployments
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

for pr_dir in ${PREVIEW_DIR}/pr-*; do
    [ -d "$pr_dir" ] || continue

    PR_NUM=$(basename "$pr_dir" | sed 's/pr-//')

    # Check if PR is still open (requires GitHub CLI or curl with token)
    if command -v gh &> /dev/null; then
        PR_STATE=$(gh pr view "$PR_NUM" --repo "$GITHUB_REPO" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
    else
        PR_STATE="UNKNOWN"
    fi

    # Check age based on last deployment marker, falling back to directory mtime
    MARKER_FILE="$pr_dir/.last_deployed"
    if [ -f "$MARKER_FILE" ]; then
        LAST_DEPLOY_TIME=$(stat -c %Y "$MARKER_FILE" 2>/dev/null || stat -f %m "$MARKER_FILE")
    else
        LAST_DEPLOY_TIME=$(stat -c %Y "$pr_dir" 2>/dev/null || stat -f %m "$pr_dir")
    fi
    DIR_AGE_HOURS=$(( ($(date +%s) - ${LAST_DEPLOY_TIME}) / 3600 ))

    if [ "$PR_STATE" = "CLOSED" ] || [ "$PR_STATE" = "MERGED" ] || [ "$DIR_AGE_HOURS" -gt "$STALE_HOURS" ]; then
        echo "Cleaning up PR #${PR_NUM} (state: ${PR_STATE}, age: ${DIR_AGE_HOURS}h)..."

        cd "$pr_dir"
        docker compose -p "hrms-pr-${PR_NUM}" down -v --remove-orphans 2>/dev/null || true
        sudo rm -rf "$pr_dir"

        echo "  Done."
    else
        echo "Keeping PR #${PR_NUM} (state: ${PR_STATE}, age: ${DIR_AGE_HOURS}h)"
    fi
done

echo "=== Cleanup complete ==="
