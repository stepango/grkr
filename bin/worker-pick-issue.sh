#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/doctor.sh"
. "$SCRIPT_DIR/grkr-task-slug.sh"

doctor_init

if [ -f "$GRKR_CONFIG_FILE" ]; then
  . "$GRKR_CONFIG_FILE"
fi

# Ensure we run from the Gleam project root (supports GRKR_GLEAM_PROJECT_ROOT override for tests)
PROJECT_ROOT=${GRKR_GLEAM_PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}
cd "$PROJECT_ROOT"

# Gleam + node are now required (github_picker path uses them; linear too)
if ! command -v gleam >/dev/null 2>&1; then
  echo "❌ gleam is required but not installed or not in PATH" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "❌ node is required but not installed or not in PATH" >&2
  exit 1
fi

# Linear provider: delegate entirely to its Gleam module (keeps its own fetch + logic)
ISSUE_PROVIDER=${GRKR_ISSUE_PROVIDER:-github}
if [ "$ISSUE_PROVIDER" = "linear" ]; then
  exec gleam run -m grkr/issue_provider/main
fi

# GitHub path (default): config validation + state + GraphQL fetch via gh (kept for compat)
# Then thin delegation: pass the project_items_json to github_picker/main which does decode+pick+emit
REPO=${REPO:-}
PROJECT_OWNER=${PROJECT_OWNER:-}
PROJECT_NUMBER=${PROJECT_NUMBER:-}
STATUS_FIELD_NAME=${STATUS_FIELD_NAME:-Status}
TODO_VALUE=${TODO_VALUE:-Todo}
PRIORITY_FIELD_NAME=${PRIORITY_FIELD_NAME:-Priority}
PRIORITY_MODE=${PRIORITY_MODE:-}
PRIORITY_ORDER=${PRIORITY_ORDER:-}

# --- GraphQL query builders and fetch (kept to provide json input to Gleam picker;
#     Gleam config.load() now does validation + active_jobs load; shell require/active removed for thinness) ---
project_items_user_graphql_query() {
  local cursor_clause=${1:-}

  cat <<EOF
query {
  user(login: "$PROJECT_OWNER") {
    projectV2(number: $PROJECT_NUMBER) {
      items(first: 100, after: ${cursor_clause:-null}) {
        nodes {
          id
          fieldValues(first: 10) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field { ... on ProjectV2SingleSelectField { name } }
              }
              ... on ProjectV2ItemFieldNumberValue {
                number
                field { ... on ProjectV2NumberField { name } }
              }
            }
          }
          content {
            ... on Issue {
              number
              title
              updatedAt
              state
              repository { nameWithOwner }
              assignees(first: 10) {
                nodes { login }
              }
            }
          }
        }
        pageInfo { hasNextPage endCursor }
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
      items(first: 100, after: ${cursor_clause:-null}) {
        nodes {
          id
          fieldValues(first: 10) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field { ... on ProjectV2SingleSelectField { name } }
              }
              ... on ProjectV2ItemFieldNumberValue {
                number
                field { ... on ProjectV2NumberField { name } }
              }
            }
          }
          content {
            ... on Issue {
              number
              title
              updatedAt
              state
              repository { nameWithOwner }
              assignees(first: 10) {
                nodes { login }
              }
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}
EOF
}

fetch_project_items_json() {
  local scope="$1"  # "user" or "organization"
  local tmp_file
  tmp_file=$(mktemp)
  local cursor=""
  local all_nodes="[]"
  local has_next=true
  local attempts=0
  local max_attempts=10

  while [ "$has_next" = true ] && [ $attempts -lt $max_attempts ]; do
    attempts=$((attempts + 1))
    local query
    if [ "$scope" = "user" ]; then
      query=$(project_items_user_graphql_query "$cursor")
    else
      query=$(project_items_org_graphql_query "$cursor")
    fi

    gh api graphql -f query="$query" > "$tmp_file" 2>/dev/null || {
      rm -f "$tmp_file"
      return 1
    }

    local page_nodes
    page_nodes=$(jq -c '.data.user.projectV2.items.nodes // .data.organization.projectV2.items.nodes // []' "$tmp_file" 2>/dev/null || echo '[]')

    all_nodes=$(jq -c --argjson p "$page_nodes" --argjson a "$all_nodes" '$a + $p' "$tmp_file" 2>/dev/null || echo "$all_nodes")

    local page_info
    page_info=$(jq -c '.data.user.projectV2.items.pageInfo // .data.organization.projectV2.items.pageInfo // {"hasNextPage":false}' "$tmp_file" 2>/dev/null || echo '{"hasNextPage":false}')
    has_next=$(echo "$page_info" | jq -r '.hasNextPage // false' 2>/dev/null || echo false)
    cursor=$(echo "$page_info" | jq -r '.endCursor // ""' 2>/dev/null || echo "")

    if [ "$has_next" != "true" ]; then
      has_next=false
    fi
  done

  # Output normalized shape {items: [nodes...]} for decoder (accumulated from all pages via $all_nodes)
  # (was previously wrapping the last full GraphQL response, which broke extract_items_nodes)
  jq -n --argjson items "$all_nodes" '{items: $items}'
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

# --- Thin wrapper: fetch json (above), then delegate to Gleam for decode/pick/emit ---
bot_login=$(gh api user --jq .login)
project_items_json=$(fetch_project_items_with_fallback)

export BOT_LOGIN="$bot_login"

if [ -z "${project_items_json:-}" ]; then
  printf 'SELECTED=0\n'
  exit 0
fi

exec gleam run -m grkr/github_picker/main "$project_items_json"
