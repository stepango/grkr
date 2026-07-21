# bin/lib/linear_issue_stages.sh
# Facade for Linear stage bodies (docs/design-linear-issue-stages-split.md).
#
# Stages-split slices 1–5 complete: this file is **source-only** (no stage function
# bodies). Concern siblings hold the extracted bodies:
#   - linear_issue_stages_refusal.sh       — ensure_linear_refusal_checkpoint (slice 1)
#   - linear_issue_stages_research_plan.sh — ensure_linear_checkpoint_stage +
#                                           ensure_linear_implement_in_progress (slice 4)
#   - linear_issue_stages_implement.sh     — run_linear_decision_stage +
#                                           handle_linear_decision_refuse +
#                                           run_linear_implement_stage (slice 5)
#   - linear_issue_stages_test.sh          — ensure_linear_test_checkpoint (slice 2)
#   - linear_issue_stages_publish.sh       — ensure_linear_publish_complete (slice 3)
#
# Source order (design §4): refusal → research_plan → implement → test → publish.
# refusal + research_plan before implement is required (implement calls
# ensure_linear_implement_in_progress + ensure_linear_refusal_checkpoint).
#
# linear_issue.sh still sources only this facade after linear_mutate.sh.
# Public function names stable; ambient call-time resolution unchanged.
#
# Historical Linear thinning (design-linear-issue-thinning.md) moved stage bodies
# out of linear_issue.sh into this file (slices 1–5 → product tip f6b34d4 / #133).
# This facade completed the next LOC-hygiene pass (concern modules + thin entry).
#
# Ambient deps resolved at call time from sourcing context (bin/grkr or direct test
# sourcing of linear_issue.sh after its prerequisites) — see each sibling header.
#
# Mirrors github_issue.sh vertical extract pattern for Linear + Gleam facade hygiene:
#   - github_issue.sh owns GitHub-specific ensure_* / publish_* / bootstrap/decision/implement/finalize.
#   - linear_issue.sh stays thin sequencer + load/meta/progress seed + decode / run_provider / project_root.
#   - stages facade sources Linear stage concern siblings only (no bodies).
#   - process_linear_issue call sites unchanged; external --linear-issue contract identical.
#   - Shared helpers stay shared / provider-agnostic.
#
# No behavior change. GitHub untouched. GRKR_ISSUE_PROVIDER default unchanged.
# linear_mutate.sh must be sourced before this file so maybe_apply_linear_mutation exists.

# Source Linear refusal stage body (stages-split slice 1). Fail closed if missing
# so tests that copy lib/ cannot silently omit the sibling.
REFUSAL_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_issue_stages_refusal.sh"
if [ -f "$REFUSAL_LIB_CANDIDATE" ]; then
  . "$REFUSAL_LIB_CANDIDATE"
else
  echo "❌ missing Linear stages refusal module: $REFUSAL_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source Linear research/plan + implement_in_progress (stages-split slice 4). Fail closed
# if missing so tests that copy lib/ cannot silently omit the sibling. Sourced before
# implement (design: refusal + research_plan before implement).
RESEARCH_PLAN_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_issue_stages_research_plan.sh"
if [ -f "$RESEARCH_PLAN_LIB_CANDIDATE" ]; then
  . "$RESEARCH_PLAN_LIB_CANDIDATE"
else
  echo "❌ missing Linear stages research_plan module: $RESEARCH_PLAN_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source Linear decision/implement orchestration (stages-split slice 5). Fail closed
# if missing so tests that copy lib/ cannot silently omit the sibling.
IMPLEMENT_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_issue_stages_implement.sh"
if [ -f "$IMPLEMENT_LIB_CANDIDATE" ]; then
  . "$IMPLEMENT_LIB_CANDIDATE"
else
  echo "❌ missing Linear stages implement module: $IMPLEMENT_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source Linear test stage body (stages-split slice 2). Fail closed if missing
# so tests that copy lib/ cannot silently omit the sibling.
TEST_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_issue_stages_test.sh"
if [ -f "$TEST_LIB_CANDIDATE" ]; then
  . "$TEST_LIB_CANDIDATE"
else
  echo "❌ missing Linear stages test module: $TEST_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source Linear publish stage body (stages-split slice 3). Fail closed if missing
# so tests that copy lib/ cannot silently omit the sibling.
PUBLISH_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/linear_issue_stages_publish.sh"
if [ -f "$PUBLISH_LIB_CANDIDATE" ]; then
  . "$PUBLISH_LIB_CANDIDATE"
else
  echo "❌ missing Linear stages publish module: $PUBLISH_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi
