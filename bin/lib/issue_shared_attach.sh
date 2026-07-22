# bin/lib/issue_shared_attach.sh
# Concern-split slice 1 (docs/design-issue-shared-concern-split.md):
# attach_issue_logs extracted from issue_shared.sh.
# Facade (issue_shared.sh) sources this sibling; bin/grkr still sources only the facade.
# Ambient call-time deps: CURRENT_ISSUE, LOGFILE, gh.
# Linear has no callers (no gh issue comments); safe to share here.
# Zero behavior change; stable public name attach_issue_logs.

attach_issue_logs() {
  local issue=${CURRENT_ISSUE:-}
  local comment_file
  [ -n "$issue" ] || return 0
  [ -f "$LOGFILE" ] || return 0
  comment_file=$(mktemp "${TMPDIR:-/tmp}/grkr-issue-log.XXXXXX") || return 0
  {
    printf '<details>\n<summary>Execution log</summary>\n\n```text\n'
    cat "$LOGFILE"
    printf '\n```\n</details>\n'
  } > "$comment_file"
  gh issue comment "$issue" --body-file "$comment_file" >/dev/null 2>&1 || true
  rm -f "$comment_file"
}
