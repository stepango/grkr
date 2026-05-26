#!/bin/bash
set -euo pipefail

# worker-handle-comment.sh <comment_id>
# Full implementation per spec/parts/15-phase-3-detect-and-process-robot-comments.md
# (GitHub-only v2). Thin shell per bin/ conventions + AGENTS.md (delegates complex
# prompt/codex to external codex CLI; git worktree via git; gh reactions/comments).
# Handles: fetch context (comment + parent issue/PR + recent comments), eyes reaction,
# worktree (main for issue comments, PR head for PR comments per spec/12), build Codex
# prompt (raw cmd + title/body + recent + branch + policy), dispatch action via codex
# (answer-only/code-change/triage/refuse classification + reply text), post result
# comment, reactions (remove eyes + rocket on success; best-effort on fail), commit/push
# if changes, cleanup worktree. Always best-effort; exits 0 on completion (reap handles).
#
# Usage from supervisor scheduler (via spawn_workflow flock): worker-handle-comment.sh <id>
# Idempotency: scan phase already marks in processed_comments.json + last_scan before spawn.
# No re-entrancy needed; reactions provide visible status on GitHub.
#
# Test: bin/worker-handle-comment.sh 4146590566  (uses public gh reads; mutations || true)
# Requires: gh (authed for reads), codex, git, jq (via doctor).

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

if [ ! -f "$PROJECT_ROOT/gleam.toml" ]; then
    echo "Error: gleam.toml not found at $PROJECT_ROOT" >&2
    exit 1
fi

cd "$PROJECT_ROOT"

# doctor for paths + validation (gh, git, jq, codex etc.)
if [ -f "$SCRIPT_DIR/doctor.sh" ]; then
    # shellcheck source=bin/doctor.sh
    . "$SCRIPT_DIR/doctor.sh"
    doctor_init
fi

if [ -f "$PROJECT_ROOT/.grkr/config.sh" ]; then
    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/.grkr/config.sh"
fi

COMMENT_ID="${1:-}"

if [ -z "$COMMENT_ID" ]; then
    echo "Usage: worker-handle-comment.sh <comment_id>" >&2
    exit 1
fi

if ! [[ "$COMMENT_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: comment_id must be numeric (GitHub id)" >&2
    exit 1
fi

# Validate tools (non-fatal for some; codex/gh required for full flow)
if command -v doctor_validate_tools >/dev/null 2>&1; then
    doctor_validate_tools || echo "⚠️ doctor_validate_tools warnings (continuing with best-effort)" >&2
fi
if command -v doctor_validate_gh_auth >/dev/null 2>&1; then
    doctor_validate_gh_auth || echo "⚠️ gh auth warning (reads may work; writes best-effort)" >&2
fi
if command -v doctor_validate_codex >/dev/null 2>&1; then
    doctor_validate_codex || echo "⚠️ codex validation warning (will still attempt)" >&2
fi

REPO="${REPO:-stepango/grkr}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"
GRKR_DIR="${GRKR_DIR:-$PROJECT_ROOT/.grkr}"
WORKTREES_DIR="$GRKR_DIR/worktrees"

echo "🤖 worker-handle-comment: starting for comment_id=$COMMENT_ID repo=$REPO"

# --- 1. Fetch comment context + parent issue/PR ---
COMMENT_JSON=$(gh api "repos/$REPO/issues/comments/$COMMENT_ID" \
    --jq '{id: (.id|tostring), body, user_login: .user.login, html_url, issue_url, created_at, updated_at}' 2>/dev/null || echo '{}')

if [ "$(echo "$COMMENT_JSON" | jq -r '.id // ""')" = "" ]; then
    echo "⚠️ Could not fetch comment $COMMENT_ID (may be deleted or no access); treating as no-op success"
    exit 0
fi

RAW_BODY=$(echo "$COMMENT_JSON" | jq -r '.body // ""')
RAW_CMD=$(echo "$RAW_BODY" | sed -E 's/^@ *:robot: *//' | head -c 500 | tr '\n' ' ' | sed 's/  */ /g')
USER_LOGIN=$(echo "$COMMENT_JSON" | jq -r '.user_login // "unknown"')
HTML_URL=$(echo "$COMMENT_JSON" | jq -r '.html_url // ""')
ISSUE_URL=$(echo "$COMMENT_JSON" | jq -r '.issue_url // ""')
ISSUE_NUMBER=$(basename "$ISSUE_URL" | tr -d '\r\n')

# Fetch parent issue/PR for title/body (works for both issues and PRs)
ISSUE_JSON=$(gh api "repos/$REPO/issues/$ISSUE_NUMBER" \
    --jq '{number, title, body: (.body // ""), html_url, is_pr: (has("pull_request") and .pull_request != null), state}' 2>/dev/null || echo '{}')

ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title // "untitled"')
ISSUE_BODY=$(echo "$ISSUE_JSON" | jq -r '.body // ""' | head -c 2000)
IS_PR=$(echo "$ISSUE_JSON" | jq -r '.is_pr // false')
ISSUE_STATE=$(echo "$ISSUE_JSON" | jq -r '.state // "open"')

echo "   context: comment by @$USER_LOGIN on ${IS_PR:+PR }#$ISSUE_NUMBER \"$ISSUE_TITLE\" cmd=\"$RAW_CMD\""

# Fetch a few recent comments on the thread for prompt context (best effort)
RECENT_COMMENTS=$(gh api "repos/$REPO/issues/$ISSUE_NUMBER/comments?per_page=5&sort=created&direction=desc" \
    --jq '[.[] | {user: .user.login, body: (.body | .[0:120] | gsub("\n";" "))} ]' 2>/dev/null || echo '[]')

# --- 2. Add eyes reaction (pre-process per spec) ---
EYES_REACTION_ID=""
EYES_RESPONSE=$(gh api -X POST "repos/$REPO/issues/comments/$COMMENT_ID/reactions" \
    -f content=eyes 2>/dev/null || echo '{}')
EYES_REACTION_ID=$(echo "$EYES_RESPONSE" | jq -r '.id // ""' 2>/dev/null || true)
if [ -n "$EYES_REACTION_ID" ]; then
    echo "   + eyes reaction (id=$EYES_REACTION_ID)"
else
    echo "   ⚠️ eyes reaction add skipped/failed (best effort)"
fi

# Trap for best-effort cleanup + eyes removal on any exit
cleanup() {
    local exit_code=$?
    echo "   cleanup: exit=$exit_code worktree + eyes removal (best effort)"
    cd "$PROJECT_ROOT" 2>/dev/null || true
    if [ -n "${WORKTREE_DIR:-}" ] && [ -d "$WORKTREE_DIR" ]; then
        git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || rm -rf "$WORKTREE_DIR" 2>/dev/null || true
    fi
    if [ -n "$EYES_REACTION_ID" ]; then
        gh api -X DELETE "repos/$REPO/issues/comments/$COMMENT_ID/reactions/$EYES_REACTION_ID" --silent 2>/dev/null || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# --- 3. Create worktree (per spec/12 + 15) ---
mkdir -p "$WORKTREES_DIR"
WORKTREE_DIR="$WORKTREES_DIR/comment-$COMMENT_ID"
BRANCH_NAME="robot/comment-$COMMENT_ID"

# Base ref per spec/12:
# - issue comment: latest main
# - PR comment: PR head branch
if [ "$IS_PR" = "true" ]; then
    PR_HEAD_REF=$(gh api "repos/$REPO/pulls/$ISSUE_NUMBER" --jq '.head.ref // "main"' 2>/dev/null || echo "$MAIN_BRANCH")
    BASE_REF="origin/$PR_HEAD_REF"
    echo "   worktree: PR comment base=$BASE_REF"
else
    BASE_REF="origin/$MAIN_BRANCH"
    echo "   worktree: issue comment base=$BASE_REF"
fi

# Create (force clean if partial from prior crash)
git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
git branch -D "$BRANCH_NAME" 2>/dev/null || true
rm -rf "$WORKTREE_DIR" 2>/dev/null || true

if ! git fetch origin "$MAIN_BRANCH" --quiet 2>/dev/null; then
    echo "   ⚠️ fetch main failed (continuing)"
fi
if [ "$IS_PR" = "true" ]; then
    git fetch origin "$PR_HEAD_REF" --quiet 2>/dev/null || true
fi

if git worktree add -b "$BRANCH_NAME" "$WORKTREE_DIR" "$BASE_REF" 2>&1 | tail -3; then
    echo "   + worktree created at $WORKTREE_DIR (branch $BRANCH_NAME)"
else
    echo "   ⚠️ worktree create failed; falling back to temp dir (no git ops)"
    WORKTREE_DIR=$(mktemp -d "$WORKTREES_DIR/comment-$COMMENT_ID.XXXXXX")
    mkdir -p "$WORKTREE_DIR"
fi

ORIGINAL_DIR=$(pwd)
cd "$WORKTREE_DIR" || { echo "   failed cd to worktree"; exit 1; }

# Configure git author for any commits (per spec/12)
git config user.name "${GIT_AUTHOR_NAME:-grkr-bot}" || true
git config user.email "${GIT_AUTHOR_EMAIL:-grkr@noreply.github.com}" || true
git config commit.gpgsign false || true

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "$BRANCH_NAME")

# --- 4+5. Build Codex prompt + execute action (classification + reply) ---
POLICY_SNIPPET="Follow AGENTS.md, spec/parts/*, and grkr v2 rules: minimal targeted changes only; always prefer answer/refuse over broad edits; respect 1000 LOC/file limit; use worktrees; post checkpoints for complex work; GitHub-only in this phase (no Linear mutations here). Be concise and professional."

PROMPT="You are grkr, the autonomous repo robot.

RAW COMMAND (from @:robot: comment #$COMMENT_ID by @$USER_LOGIN):
$RAW_CMD

CONTEXT:
- Repo: $REPO
- ${IS_PR:+PR }Issue #$ISSUE_NUMBER: $ISSUE_TITLE
  State: $ISSUE_STATE
  URL: $(echo "$ISSUE_JSON" | jq -r '.html_url // ""')
- Issue/PR body (truncated): ${ISSUE_BODY:0:800}
- Recent thread comments (newest first, truncated): $(echo "$RECENT_COMMENTS" | jq -c .)
- Current worktree branch: $CURRENT_BRANCH (base: $BASE_REF)
- Policy: $POLICY_SNIPPET

TASK:
Classify the intent of the RAW COMMAND and respond as one of:
- answer-only: provide helpful reply, no code changes
- code-change: describe + (if safe/minimal) note that edit would be made here
- triage: suggest next step or label
- refuse: politely decline with short reason (e.g. too vague, out of scope, needs more info)

OUTPUT FORMAT (exact, parseable):
CLASS: <answer-only|code-change|triage|refuse>
REPLY: <1-6 sentence professional reply text for posting as GitHub comment. Include classification and any caveats. Do NOT include raw prompt.>
CHANGES: <short description of any code intent or N/A>

Do not execute external commands yourself; only describe. Keep REPLY under 1200 chars."

echo "   building codex prompt (len=$(echo "$PROMPT" | wc -c | tr -d ' '))"

CODEX_OUTPUT=""
if command -v codex >/dev/null 2>&1; then
    # Updated flag per current codex (avoid deprecation); capture final model output
    # Pipe prompt via stdin to avoid arg length/quoting issues
    CODEX_OUTPUT=$(echo "$PROMPT" | timeout 120 codex exec --sandbox workspace-write 2>&1 | tail -80 || echo "CLASS: refuse
REPLY: Codex invocation timed out or failed for command: $RAW_CMD. Treating as non-actionable for now.
CHANGES: N/A")
else
    CODEX_OUTPUT="CLASS: answer-only
REPLY: (codex CLI not available in this env; stub reply for command: $RAW_CMD on #$ISSUE_NUMBER)
CHANGES: N/A"
fi

echo "   codex raw output (truncated): ${CODEX_OUTPUT:0:300}..."

# Parse structured output (robust: take LAST CLASS/REPLY/CHANGES in output, tolerate codex UI noise)
CLASS=$(echo "$CODEX_OUTPUT" | grep -i '^CLASS:' | tail -1 | cut -d: -f2- | tr -d ' \r' | tr '[:upper:]' '[:lower:]' || echo "answer-only")
REPLY=$(echo "$CODEX_OUTPUT" | awk 'BEGIN{IGNORECASE=1} /^REPLY:/ {capture=1; sub(/^REPLY:[ \t]*/,""); buf=$0; next} /^CHANGES:/ {capture=0} capture {buf=buf "\n" $0} END {print buf}' | head -c 1800 | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "Processed @:robot: $RAW_CMD (parse issue; see job log for full codex output)")
CHANGES=$(echo "$CODEX_OUTPUT" | grep -i '^CHANGES:' | tail -1 | cut -d: -f2- | tr -d '\r' | sed 's/^[ \t]*//' || echo "N/A")

case "$CLASS" in
    code-change|answer-only|triage|refuse) ;;
    *) CLASS="answer-only" ;;
esac

echo "   parsed: class=$CLASS changes=$CHANGES"

# --- 6+7. Comment result + optional commit/push ---
RESULT_BODY="**grkr** processed your \`@:robot: $RAW_CMD\` (comment $COMMENT_ID)

**Classification:** $CLASS
**Reply/Notes:** $REPLY

**Changes intent:** $CHANGES
**Worktree:** $BRANCH_NAME (cleaned)
**Context:** ${IS_PR:+PR }#$ISSUE_NUMBER \"$ISSUE_TITLE\"

(Generated via Codex per spec/15; see job log for full prompt/output. This is GitHub-only v2 slice.)"

# Post as comment on the issue/PR (use gh issue comment which works for both)
if gh issue comment "$ISSUE_NUMBER" --body "$RESULT_BODY" --repo "$REPO" >/dev/null 2>&1; then
    echo "   + posted result comment on #$ISSUE_NUMBER"
else
    echo "   ⚠️ failed to post result comment (best effort; continuing)"
fi

# If code-change and we have real changes in worktree (codex didn't edit; we only describe), optionally stage a marker
if [ "$CLASS" = "code-change" ] && [ -d .git ] && [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then
    git add -A 2>/dev/null || true
    git commit -m "robot(comment-$COMMENT_ID): $CLASS for $RAW_CMD

$REPLY

[grkr v2 worker-handle-comment]" 2>/dev/null || true
    if git push --force-with-lease origin "$BRANCH_NAME" 2>/dev/null; then
        echo "   + pushed branch $BRANCH_NAME (code-change)"
    else
        echo "   ⚠️ push skipped (no perms or no changes)"
    fi
fi

# --- 8. Update reactions (success: remove eyes + rocket) ---
if [ -n "$EYES_REACTION_ID" ]; then
    gh api -X DELETE "repos/$REPO/issues/comments/$COMMENT_ID/reactions/$EYES_REACTION_ID" --silent 2>/dev/null || true
    EYES_REACTION_ID=""  # prevent double in trap
fi

if gh api -X POST "repos/$REPO/issues/comments/$COMMENT_ID/reactions" -f content=rocket --silent 2>/dev/null; then
    echo "   + rocket reaction (success path)"
else
    echo "   ⚠️ rocket reaction add failed (best effort)"
fi

# --- 9. Cleanup (explicit before trap) ---
cd "$ORIGINAL_DIR" 2>/dev/null || true
if [ -n "${WORKTREE_DIR:-}" ] && [ -d "$WORKTREE_DIR" ] && [ "$WORKTREE_DIR" != "$PROJECT_ROOT" ]; then
    git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || rm -rf "$WORKTREE_DIR" 2>/dev/null || true
    echo "   + worktree removed"
fi

# Disable trap cleanup (already done)
trap - EXIT INT TERM

echo "✅ worker-handle-comment.sh complete for $COMMENT_ID (class=$CLASS, exit=0)"
exit 0
