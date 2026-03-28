#!/bin/bash
set -euo pipefail

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/grkr-worker-pick-issue.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

cp bin/worker-pick-issue.sh "$tmpdir/worker-pick-issue.sh"
cp bin/doctor.sh "$tmpdir/doctor.sh"
chmod +x "$tmpdir/worker-pick-issue.sh" "$tmpdir/doctor.sh"

real_git=$(command -v git)
mkdir -p "$tmpdir/bin" "$tmpdir/.grkr/state"

cat > "$tmpdir/bin/git" <<EOF
#!/bin/bash
case "\$*" in
  'rev-parse --show-toplevel') printf '%s\n' "$tmpdir" ;;
  *) exec "$real_git" "\$@" ;;
esac
EOF

cat > "$tmpdir/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
  'api user')
    printf 'robot\n'
    ;;
  'project item-list')
    case "${GRKR_TEST_SCENARIO:-single_select}" in
      single_select)
        cat <<'JSON'
{"items":[
  {"id":"PVTI_5","content":{"number":5,"title":"Later candidate","updatedAt":"2026-03-20T10:00:00Z","state":"OPEN","repository":{"nameWithOwner":"stepango/grkr"}},"assignees":[{"login":"robot"}],"status":"Todo","priority":"P1"},
  {"id":"PVTI_2","content":{"number":2,"title":"Second oldest top priority","updatedAt":"2026-03-10T10:00:00Z","state":"OPEN","repository":{"nameWithOwner":"stepango/grkr"}},"assignees":[{"login":"robot"}],"status":"Todo","priority":"P0"},
  {"id":"PVTI_1","content":{"number":1,"title":"First top priority","updatedAt":"2026-03-10T10:00:00Z","state":"OPEN","repository":{"nameWithOwner":"stepango/grkr"}},"assignees":[{"login":"robot"}],"status":"Todo","priority":"P0"},
  {"id":"PVTI_4","content":{"number":4,"title":"Already active","updatedAt":"2026-03-01T10:00:00Z","state":"OPEN","repository":{"nameWithOwner":"stepango/grkr"}},"assignees":[{"login":"robot"}],"status":"Todo","priority":"P0"},
  {"id":"PVTI_8","content":{"number":8,"title":"Closed issue","updatedAt":"2026-03-02T10:00:00Z","state":"CLOSED","repository":{"nameWithOwner":"stepango/grkr"}},"assignees":[{"login":"robot"}],"status":"Todo","priority":"P0"},
  {"id":"PVTI_9","content":{"number":9,"title":"Wrong repo","updatedAt":"2026-03-02T10:00:00Z","state":"OPEN","repository":{"nameWithOwner":"other/repo"}},"assignees":[{"login":"robot"}],"status":"Todo","priority":"P0"},
  {"id":"PVTI_10","content":{"number":10,"title":"Wrong status","updatedAt":"2026-03-02T10:00:00Z","state":"OPEN","repository":{"nameWithOwner":"stepango/grkr"}},"assignees":[{"login":"robot"}],"status":"In Progress","priority":"P0"},
  {"id":"PVTI_11","content":{"number":11,"title":"Wrong assignee","updatedAt":"2026-03-02T10:00:00Z","state":"OPEN","repository":{"nameWithOwner":"stepango/grkr"}},"assignees":[{"login":"someone-else"}],"status":"Todo","priority":"P0"}
]}
JSON
        ;;
      number)
        cat <<'JSON'
{"items":[
  {"id":"PVTI_12","content":{"number":12,"title":"Highest number priority","updatedAt":"2026-03-11T10:00:00Z","state":"OPEN","repository":{"nameWithOwner":"stepango/grkr"}},"assignees":[{"login":"robot"}],"status":"Todo","priority":{"number":8}},
  {"id":"PVTI_13","content":{"number":13,"title":"Lower number priority","updatedAt":"2026-03-01T10:00:00Z","state":"OPEN","repository":{"nameWithOwner":"stepango/grkr"}},"assignees":[{"login":"robot"}],"status":"Todo","priority":{"number":4}}
]}
JSON
        ;;
    esac
    ;;
  'project field-list')
    case "${GRKR_TEST_SCENARIO:-single_select}" in
      single_select)
        cat <<'JSON'
[{"name":"Priority","type":"SINGLE_SELECT","options":[{"name":"P0"},{"name":"P1"},{"name":"P2"},{"name":"P3"}]}]
JSON
        ;;
      number)
        cat <<'JSON'
[{"name":"Priority","type":"NUMBER"}]
JSON
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "$tmpdir/bin/git" "$tmpdir/bin/gh"

cat > "$tmpdir/.grkr/config.sh" <<'EOF'
REPO="stepango/grkr"
PROJECT_OWNER="stepango"
PROJECT_NUMBER="7"
STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
BACKLOG_VALUE="Backlog"
PRIORITY_FIELD_NAME="Priority"
EOF

cat > "$tmpdir/.grkr/state/active_jobs.json" <<'EOF'
{
  "issue:4:execution": {
    "pid": 1234
  }
}
EOF

run_worker() {
  local scenario=$1
  local output_file=$2

  (
    cd "$tmpdir"
    PATH="$tmpdir/bin:$PATH" HOME="$tmpdir/home" GRKR_TEST_SCENARIO="$scenario" bash "$tmpdir/worker-pick-issue.sh" >"$output_file"
  )
}

single_select_output="$tmpdir/single-select.env"
run_worker single_select "$single_select_output"
. "$single_select_output"

[ "$SELECTED" = "1" ]
[ "$ISSUE_NUMBER" = "1" ]
[ "$JOB_KEY" = "issue:1:execution" ]
[ "$TASK_SLUG" = "issue-1-first-top-priority" ]
[ "$PROJECT_ITEM_ID" = "PVTI_1" ]
[ "$PRIORITY_NAME" = "P0" ]

cat > "$tmpdir/.grkr/config.sh" <<'EOF'
REPO="stepango/grkr"
PROJECT_OWNER="stepango"
PROJECT_NUMBER="7"
STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
BACKLOG_VALUE="Backlog"
PRIORITY_FIELD_NAME="Priority"
PRIORITY_MODE="number"
EOF

numeric_output="$tmpdir/number.env"
run_worker number "$numeric_output"
. "$numeric_output"

[ "$SELECTED" = "1" ]
[ "$ISSUE_NUMBER" = "12" ]
[ "$JOB_KEY" = "issue:12:execution" ]
[ "$TASK_SLUG" = "issue-12-highest-number-priority" ]
[ "$PROJECT_ITEM_ID" = "PVTI_12" ]
[ "$PRIORITY_NUMBER" = "8" ]
