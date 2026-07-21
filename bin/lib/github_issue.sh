# bin/lib/github_issue.sh
# Facade for GitHub stage bodies (docs/design-github-issue-stages-split.md).
#
# Stages-split slices 1–4 **complete**: this file is **source-only** (no stage
# function bodies). Concern siblings hold the extracted bodies:
#   - github_issue_stages_research_plan.sh — fetch_issue_comments_json +
#     checkpoint_comment_* + ensure_checkpoint_stage (slice 1)
#   - github_issue_stages_implement.sh     — bootstrap_github_issue_task +
#     run_github_decision_stage + handle_github_decision_refuse +
#     run_github_implement_stage + finalize_github_issue_complete (slice 4)
#   - github_issue_stages_test.sh          — write_test_checkpoint_file +
#     ensure_test_checkpoint (slice 2)
#   - github_issue_stages_publish.sh       — publish_issue_changes + alias +
#     ensure_pr_body_limit + extract_codex_pr_body + post_completion_comment +
#     alias (slice 3)
#
# Source order (design §4, dependency-before-depender readability):
#   research_plan → implement → test → publish
#
# bin/grkr still sources only this facade path. process_issue stays thin sequencer
# in bin/grkr. Public function names stable; ambient call-time resolution unchanged.
#
# Historical process_issue thinning (design-github-process-issue-thinning.md) moved
# stage bodies out of bin/grkr into this file (slices #112–#121 → tip a3d9702).
# Gleam thins: PR body helpers #147, completion summary #152.
# This facade completed the next LOC-hygiene pass (concern modules + thin entry),
# mirroring linear_issue_stages.sh stages-split (complete @ cb6b1b5 / #177).
#
# Ambient deps resolved at call time from sourcing context (bin/grkr or direct test
# sourcing after issue_shared + templates) — see each sibling header.
# Shared helpers stay in issue_shared.sh (frozen — no GitHub stage dump).
# Linear paths untouched. GRKR_ISSUE_PROVIDER default GitHub. No new flags.
# No checkpoint-json Gleam extract in this work.

# Source GitHub research/plan stage body (stages-split slice 1). Fail closed if missing
# so tests that copy lib/ cannot silently omit the sibling.
RESEARCH_PLAN_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/github_issue_stages_research_plan.sh"
if [ -f "$RESEARCH_PLAN_LIB_CANDIDATE" ]; then
  . "$RESEARCH_PLAN_LIB_CANDIDATE"
else
  echo "❌ missing GitHub stages research_plan module: $RESEARCH_PLAN_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source GitHub implement/bootstrap/decision/finalize cluster (stages-split slice 4).
# Fail closed if missing so tests that copy lib/ cannot silently omit the sibling.
IMPLEMENT_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/github_issue_stages_implement.sh"
if [ -f "$IMPLEMENT_LIB_CANDIDATE" ]; then
  . "$IMPLEMENT_LIB_CANDIDATE"
else
  echo "❌ missing GitHub stages implement module: $IMPLEMENT_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source GitHub test stage body (stages-split slice 2). Fail closed if missing.
TEST_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/github_issue_stages_test.sh"
if [ -f "$TEST_LIB_CANDIDATE" ]; then
  . "$TEST_LIB_CANDIDATE"
else
  echo "❌ missing GitHub stages test module: $TEST_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source GitHub publish+completion stage body (stages-split slice 3). Fail closed if missing.
PUBLISH_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/github_issue_stages_publish.sh"
if [ -f "$PUBLISH_LIB_CANDIDATE" ]; then
  . "$PUBLISH_LIB_CANDIDATE"
else
  echo "❌ missing GitHub stages publish module: $PUBLISH_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi
