#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"
. "$SCRIPT_DIR/grkr-comment-workflow.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

mkdir -p "$GRKR_ROOT/.grkr/state" "$GRKR_ROOT/.grkr/logs/jobs"
comment_state_init

comments_json=$(gh api "repos/$REPO/issues/comments" 2>/dev/null || true)
if [ -z "$comments_json" ]; then
  comments_json='[]'
fi

processed_count=0
skipped_count=0
failed_count=0
actionable_count=0

while IFS= read -r comment_json; do
  [ -n "$comment_json" ] || continue

  comment_id=$(printf '%s' "$comment_json" | jq -r '.id // empty')
  comment_body=$(printf '%s' "$comment_json" | jq -r '.body // ""')
  comment_updated_at=$(printf '%s' "$comment_json" | jq -r '.updated_at // empty')
  comment_body_hash=$(comment_body_sha "$comment_body")

  if ! comment_is_actionable_body "$comment_body"; then
    skipped_count=$((skipped_count + 1))
    continue
  fi

  actionable_count=$((actionable_count + 1))
  if [ -n "$comment_updated_at" ] && comment_state_entry_matches "$comment_id" "$comment_updated_at" "$comment_body_hash"; then
    echo "♻️ Skipping already processed comment #$comment_id."
    skipped_count=$((skipped_count + 1))
    continue
  fi

  echo "🔍 Processing comment #$comment_id..."
  if "$SCRIPT_DIR/worker-handle-comment.sh" "$comment_id"; then
    processed_count=$((processed_count + 1))
  else
    failed_count=$((failed_count + 1))
    echo "⚠️ Comment #$comment_id failed; continuing."
  fi
done < <(printf '%s' "$comments_json" | jq -c 'if type == "array" then .[] else empty end')

date -u +"%Y-%m-%dT%H:%M:%SZ" > "$(comment_last_scan_file)"
echo "✅ Processed $processed_count actionable comment(s)."
echo "ℹ️ Skipped $skipped_count comment(s)."
echo "ℹ️ Failed $failed_count comment(s)."
echo "SCHEDULED_COMMENTS=$processed_count"
echo "ACTIONABLE_COMMENTS=$actionable_count"
