# bin/lib/issue_shared.sh
# Stable facade path for neutral shared helpers (GitHub + Linear issue paths).
# bin/grkr sources only this file (BEFORE lib/linear_issue.sh and lib/github_issue.sh).
#
# Concern-split slices 1–5 **complete** (docs/design-issue-shared-concern-split.md):
# this file is **source-only** (no function bodies). Concern siblings hold bodies:
#   - issue_shared_coding_agent.sh — _grkr_coding_* + backends +
#     run_coding_agent_prompt + run_codex_prompt (slice 5)
#   - issue_shared_progress.sh     — run_progress_cli + checkpoint_marker (slice 2)
#   - issue_shared_test_write.sh   — build_command_list + cleanup_test_result_logs +
#     write_test_checkpoint_with_header (slice 4)
#   - issue_shared_line_limit.sh   — collect/check line-limit +
#     ensure_publishable_file_sizes (slice 3)
#   - issue_shared_attach.sh       — attach_issue_logs (slice 1)
# Historical "Slice 1–5" labels from shared-helpers extract (#136–#144 /
# design-grkr-shared-helpers-extract.md) are historical extract-into-shared order;
# do not confuse them with concern-split slice numbers in the design above.
#
# Source order (design §4, dependency-before-depender):
#   coding_agent → progress → test_write → line_limit → attach
#   (ensure_publishable calls run_codex_prompt; write_test_checkpoint calls
#    checkpoint_marker — call-time resolution after full facade source.)
#
# Ambient call-time deps (resolved in grkr / grkr-issue-workflow / templates):
# git_in_issue_context, stage_relevant_issue_files, persist_task_log_output,
# write_line_limit_fix_prompt, MAX_FILE_LINES, CURRENT_ISSUE_WORKTREE.
# Per-sibling ambient deps live in each sibling header. No re-exports; exact
# prior behavior. GRKR_ISSUE_PROVIDER default GitHub. No new flags.

# Source coding_agent sibling (concern-split slice 5). Fail closed if missing so
# tests that copy lib/ cannot silently omit the sibling. Sourced first so
# ensure_publishable_file_sizes (line_limit) ambient run_codex_prompt resolves.
CODING_AGENT_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/issue_shared_coding_agent.sh"
if [ -f "$CODING_AGENT_LIB_CANDIDATE" ]; then
  . "$CODING_AGENT_LIB_CANDIDATE"
else
  echo "❌ missing issue_shared coding_agent module: $CODING_AGENT_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source progress sibling (concern-split slice 2). Fail closed if missing.
PROGRESS_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/issue_shared_progress.sh"
if [ -f "$PROGRESS_LIB_CANDIDATE" ]; then
  . "$PROGRESS_LIB_CANDIDATE"
else
  echo "❌ missing issue_shared progress module: $PROGRESS_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source test_write sibling (concern-split slice 4). Fail closed if missing.
# progress is sourced above so checkpoint_marker resolves at call time.
TEST_WRITE_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/issue_shared_test_write.sh"
if [ -f "$TEST_WRITE_LIB_CANDIDATE" ]; then
  . "$TEST_WRITE_LIB_CANDIDATE"
else
  echo "❌ missing issue_shared test_write module: $TEST_WRITE_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source line_limit sibling (concern-split slice 3). Fail closed if missing.
# coding_agent is sourced above so ambient run_codex_prompt works at call time.
LINE_LIMIT_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/issue_shared_line_limit.sh"
if [ -f "$LINE_LIMIT_LIB_CANDIDATE" ]; then
  . "$LINE_LIMIT_LIB_CANDIDATE"
else
  echo "❌ missing issue_shared line_limit module: $LINE_LIMIT_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi

# Source attach sibling (concern-split slice 1). Fail closed if missing.
ATTACH_LIB_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/issue_shared_attach.sh"
if [ -f "$ATTACH_LIB_CANDIDATE" ]; then
  . "$ATTACH_LIB_CANDIDATE"
else
  echo "❌ missing issue_shared attach module: $ATTACH_LIB_CANDIDATE" >&2
  return 1 2>/dev/null || exit 1
fi
