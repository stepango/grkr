#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

# Check if using Linear issue provider
ISSUE_PROVIDER=${GRKR_ISSUE_PROVIDER:-github}
if [ "$ISSUE_PROVIDER" = "linear" ]; then
  exec gleam run -m grkr/issue_provider/main
fi

REPO=${REPO:-}
PROJECT_OWNER=${PROJECT_OWNER:-}
PROJECT_NUMBER=${PROJECT_NUMBER:-}
STATUS_FIELD_NAME=${STATUS_FIELD_NAME:-Status}
TODO_VALUE=${TODO_VALUE:-Todo}
PRIORITY_FIELD_NAME=${PRIORITY_FIELD_NAME:-Priority}
PRIORITY_MODE=${PRIORITY_MODE:-}
PRIORITY_ORDER=${PRIORITY_ORDER:-}

GRKR_DIR="$GRKR_ROOT/.grkr"
STATE_DIR="$GRKR_DIR/state"
ACTIVE_JOBS_FILE="$STATE_DIR/active_jobs.json"

require_config_value() {
  local name=$1
  local value=${2-}

  if [ -z "$value" ]; then
    printf 'Missing required config value: %s\n' "$name" >&2
    exit 1
  fi
}

normalize_priority_mode() {
  local value=${1-}

  value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  case "$value" in
    *number*)
      printf 'number\n'
      ;;
    *select*)
      printf 'single_select\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

slugify_text() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' \
    | cut -c1-80
}

task_slug_for_issue() {
  local issue=$1
  local title=$2
  local title_slug

  title_slug=$(slugify_text "$title")
  [ -n "$title_slug" ] || title_slug="task"
  printf 'issue-%s-%s\n' "$issue" "$title_slug"
}

require_config_value "REPO" "$REPO"
require_config_value "PROJECT_OWNER" "$PROJECT_OWNER"
require_config_value "PROJECT_NUMBER" "$PROJECT_NUMBER"
require_config_value "STATUS_FIELD_NAME" "$STATUS_FIELD_NAME"
require_config_value "TODO_VALUE" "$TODO_VALUE"
require_config_value "PRIORITY_FIELD_NAME" "$PRIORITY_FIELD_NAME"

mkdir -p "$STATE_DIR"

if [ -f "$ACTIVE_JOBS_FILE" ]; then
  active_issue_numbers_json=$(jq -c '[keys[]? | select(test("^issue:[0-9]+:")) | split(":")[1] | tonumber] | unique' "$ACTIVE_JOBS_FILE")
else
  active_issue_numbers_json='[]'
fi

project_items_user_graphql_query() {
  local cursor_clause=${1:-}

  cat <<EOF
query {
  user(login: "$PROJECT_OWNER") {
    projectV2(number: $PROJECT_NUMBER) {
      items(first: 100$cursor_clause) {
        nodes {
          id
          fieldValues(first: 50) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field {
                  ... on ProjectV2FieldCommon {
                    name
                  }
                }
              }
              ... on ProjectV2ItemFieldNumberValue {
                number
                field {
                  ... on ProjectV2FieldCommon {
                    name
                  }
                }
              }
            }
          }
          content {
            __typename
            ... on Issue {
              number
              title
              updatedAt
              state
              repository {
                nameWithOwner
              }
              assignees(first: 20) {
                nodes {
                  login
                }
              }
            }
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
}
EOF
}

project_items_org_graphql_query() {
  local cursor_clause=${1:-}

  cat <<EOF
query {
  organization(login: "$PROJECT_OWNER") {
    projectV2(number: $PROJECT_NUMBER) {
      items(first: 100$cursor_clause) {
        nodes {
          id
          fieldValues(first: 50) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field {
                  ... on ProjectV2FieldCommon {
                    name
                  }
                }
              }
              ... on ProjectV2ItemFieldNumberValue {
                number
                field {
                  ... on ProjectV2FieldCommon {
                    name
                  }
                }
              }
            }
          }
          content {
            __typename
            ... on Issue {
              number
              title
              updatedAt
              state
              repository {
                nameWithOwner
              }
              assignees(first: 20) {
                nodes {
                  login
                }
              }
            }
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
}
EOF
}

fetch_project_items_json() {
  local mode=${1:-user}
  local cursor=""
  local cursor_clause=""
  local query
  local page_json
  local nodes_json
  local has_next
  local end_cursor
  local tmp_file
  local tmp_next
  local connection_filter

  case "$mode" in
    user)
      connection_filter='.data.user.projectV2.items'
      ;;
    organization)
      connection_filter='.data.organization.projectV2.items'
      ;;
    *)
      return 1
      ;;
  esac

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/grkr-project-items.XXXXXX")
  printf '[]\n' > "$tmp_file"

  while true; do
    if [ -n "$cursor" ]; then
      cursor_clause=", after: \"$cursor\""
    else
      cursor_clause=""
    fi

    if [ "$mode" = "user" ]; then
      query=$(project_items_user_graphql_query "$cursor_clause")
    else
      query=$(project_items_org_graphql_query "$cursor_clause")
    fi

    page_json=$(gh api graphql -f query="$query" 2>/dev/null || true)
    if [ -z "$page_json" ]; then
      rm -f "$tmp_file"
      return 1
    fi

    if [ "$(printf '%s' "$page_json" | jq -r "($connection_filter // empty) | type // empty")" != "object" ]; then
      rm -f "$tmp_file"
      return 1
    fi

    nodes_json=$(printf '%s' "$page_json" | jq -c "($connection_filter.nodes // [])")
    tmp_next=$(mktemp "${TMPDIR:-/tmp}/grkr-project-items.XXXXXX")
    jq --argjson nodes "$nodes_json" '. + $nodes' "$tmp_file" > "$tmp_next"
    mv "$tmp_next" "$tmp_file"

    has_next=$(printf '%s' "$page_json" | jq -r "($connection_filter.pageInfo.hasNextPage // false)")
    if [ "$has_next" != "true" ]; then
      break
    fi

    end_cursor=$(printf '%s' "$page_json" | jq -r "($connection_filter.pageInfo.endCursor // empty)")
    if [ -z "$end_cursor" ]; then
      break
    fi
    cursor=$end_cursor
  done

  jq -c '{items: .}' "$tmp_file"
  rm -f "$tmp_file"
}

fetch_project_items_with_fallback() {
  local items_json

  items_json=$(fetch_project_items_json user 2>/dev/null || true)
  if [ -n "$items_json" ]; then
    printf '%s\n' "$items_json"
    return 0
  fi

  items_json=$(fetch_project_items_json organization 2>/dev/null || true)
  if [ -n "$items_json" ]; then
    printf '%s\n' "$items_json"
    return 0
  fi

  gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --limit 1000 --format json
}

bot_login=$(gh api user --jq .login)
project_items_json=$(fetch_project_items_with_fallback)
project_fields_json=$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --limit 1000 --format json)

priority_field_json=$(printf '%s' "$project_fields_json" | jq -c --arg field_name "$PRIORITY_FIELD_NAME" '
  ((if type == "object" and has("fields") then .fields else . end) | if type == "array" then . else [] end
    | map(select(.name == $field_name))
    | .[0]) // {}
')

detected_priority_mode=$(printf '%s' "$priority_field_json" | jq -r '.dataType // .type // empty')
priority_mode=$(normalize_priority_mode "${PRIORITY_MODE:-$detected_priority_mode}")
[ -n "$priority_mode" ] || priority_mode="single_select"

if [ "$priority_mode" = "single_select" ] && [ -n "$PRIORITY_ORDER" ]; then
  priority_order_json=$(printf '%s' "$PRIORITY_ORDER" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')
elif [ "$priority_mode" = "single_select" ]; then
  priority_order_json=$(printf '%s' "$priority_field_json" | jq -c '[.options[]?.name]')
else
  priority_order_json='[]'
fi

candidate_json=$(printf '%s' "$project_items_json" | jq -c \
  --arg bot_login "$bot_login" \
  --arg repo "$REPO" \
  --arg status_field "$STATUS_FIELD_NAME" \
  --arg todo_value "$TODO_VALUE" \
  --arg priority_field "$PRIORITY_FIELD_NAME" \
  --arg priority_mode "$priority_mode" \
  --argjson priority_order "$priority_order_json" \
  --argjson active_issue_numbers "$active_issue_numbers_json" '
  def arrayify:
    if . == null then []
    elif type == "array" then .
    elif type == "object" and (.nodes | type == "array") then .nodes
    elif type == "object" and (.items | type == "array") then .items
    else []
    end;
  def field_entries:
    (if type == "object" and has("fieldValues") then .fieldValues elif type == "object" and has("fields") then .fields else [] end) | arrayify;
  def normalize_repo_name($value):
    if $value == null then ""
    elif ($value | type) == "string" then
      ($value | sub("^https?://github\\.com/"; "") | sub("\\.git$"; ""))
    elif ($value | type) == "object" then
      normalize_repo_name(
        if ($value.nameWithOwner // "") != "" then
          $value.nameWithOwner
        elif (($value.owner.login // "") != "" and ($value.name // "") != "") then
          ($value.owner.login + "/" + $value.name)
        else
          ($value.url // "")
        end
      )
    else
      ""
    end;
  def field_value($field_name):
    (field_entries | map(select((.field.name // .name // .fieldName // "") == $field_name)) | .[0]) // {};
  def field_text($field_name):
    (field_value($field_name) | .name // .optionName // .text // .value // "");
  def maybe_number:
    if . == null or . == "" then null else (tonumber? // null) end;
  def field_number($field_name):
    (field_value($field_name) | (.number // .value // .text // null) | maybe_number);
  def assignee_logins:
    ([ .assignees, .content.assignees, .content.issue.assignees, .issue.assignees ]
      | map(arrayify)
      | add
      | map(.login // empty)
      | map(select(length > 0))
      | unique);
  def issue_number:
    (.content.number // .content.issue.number // .issue.number // .number // null);
  def issue_title:
    (.content.title // .content.issue.title // .issue.title // .title // "");
  def issue_updated_at:
    (.content.updatedAt // .content.issue.updatedAt // .issue.updatedAt // .updatedAt // "");
  def issue_state:
    (.content.state // .content.issue.state // .issue.state // .state // "");
  def repo_name:
    normalize_repo_name(.content.repository // .content.issue.repository // .repository // "");
  def status_name:
    ((if (.status | type) == "object" then .status.name else null end) // (if (.status | type) == "string" then .status else null end) // field_text($status_field));
  def priority_name:
    ((if (.priority | type) == "object" then .priority.name else null end) // (if (.priority | type) == "string" then .priority else null end) // field_text($priority_field));
  def priority_number:
    (((if (.priority | type) == "object" then (.priority.number // .priority.value) else null end) // field_number($priority_field) // null) | maybe_number);
  def priority_sort:
    if $priority_mode == "number" then
      if .priority_number == null then 9223372036854775807 else (0 - .priority_number) end
    else
      (.priority_name as $priority_name | ($priority_order | index($priority_name))) // 9223372036854775807
    end;

  ((if type == "object" and has("items") then .items else . end) | if type == "array" then . else [] end)
  | map({
      project_item_id: (.id // ""),
      issue_number: issue_number,
      issue_title: issue_title,
      issue_updated_at: issue_updated_at,
      issue_state: issue_state,
      repo_name: repo_name,
      status_name: status_name,
      priority_name: priority_name,
      priority_number: priority_number,
      assignee_logins: assignee_logins
    })
  | map(select(.issue_number != null))
  | map(select((.assignee_logins | index($bot_login)) != null))
  | map(select(.status_name == $todo_value))
  | map(select((.issue_state | ascii_upcase) == "OPEN"))
  | map(select(.repo_name == $repo))
  | map(select((.issue_number as $issue_number | ($active_issue_numbers | index($issue_number))) == null))
  | map(. + { priority_sort: priority_sort })
  | sort_by([.priority_sort, .issue_updated_at, .issue_number])
  | .[0] // empty
')

if [ -z "$candidate_json" ]; then
  printf 'SELECTED=0\n'
  exit 0
fi

issue_number=$(printf '%s' "$candidate_json" | jq -r '.issue_number')
issue_title=$(printf '%s' "$candidate_json" | jq -r '.issue_title')
project_item_id=$(printf '%s' "$candidate_json" | jq -r '.project_item_id')
issue_updated_at=$(printf '%s' "$candidate_json" | jq -r '.issue_updated_at')
priority_name=$(printf '%s' "$candidate_json" | jq -r '.priority_name // empty')
priority_number=$(printf '%s' "$candidate_json" | jq -r '.priority_number // empty')
job_key="issue:${issue_number}:execution"
task_slug=$(task_slug_for_issue "$issue_number" "$issue_title")

printf 'SELECTED=1\n'
printf 'ISSUE_NUMBER=%s\n' "$issue_number"
printf 'JOB_KEY=%q\n' "$job_key"
printf 'TASK_SLUG=%q\n' "$task_slug"
printf 'PROJECT_ITEM_ID=%q\n' "$project_item_id"
printf 'ISSUE_TITLE=%q\n' "$issue_title"
printf 'ISSUE_UPDATED_AT=%q\n' "$issue_updated_at"
printf 'PRIORITY_NAME=%q\n' "$priority_name"
printf 'PRIORITY_NUMBER=%q\n' "$priority_number"
